"""Native orchestration tests with pinned fake tools and an independent SPDX oracle."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

import test_runtime_cli as fixtures
from runtime_sbom_oracle import sbom_document

ROOT = Path(__file__).resolve().parents[1]


class NativeCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = ROOT / '.blueprint' / 'runtime-candidate-tests'
        subprocess.run(['roc-stable', 'build', 'scripts/runtime_test.roc', f'--output={cls.binary}'],
                       cwd=ROOT, check=True, timeout=120)

    def exercise(self, fail_link=False, mutate_sbom=None):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        (root / 'runtime').mkdir()
        zig_script = ('#!' + sys.executable + '\n' + '''import json, os, pathlib, sys
args = sys.argv[1:]
if args == ['version']:
    print('0.16.0'); sys.exit(0)
with open(os.environ['FAKE_ZIG_LOG'], 'a') as log:
    log.write(json.dumps(args)+'\\n')
output = pathlib.Path(args[args.index('-o')+1])
if '-c' in args:
    output.write_bytes(b'compiled-object'); sys.exit(0)
for name in ('crt1.o','libunwind.a','libc.a','libzigc.a','libcompiler_rt.a'):
    paths = [pathlib.Path(arg) for arg in args if arg.endswith('/'+name)]
    assert len(paths) == 1 and paths[0].read_bytes() == name.encode(), name
assert '-nostdlib' in args
if os.environ.get('FAKE_LINK_FAIL') == '1':
    print('forced test link failure', file=sys.stderr); sys.exit(42)
output.write_text('#!'+sys.executable+'\\nimport os,pathlib\\npathlib.Path(os.environ["NATIVE_RAN"]).write_text("linked candidate")\\n')
output.chmod(0o755)
''').encode()
        zig_archive = root / 'fixture-zig.tar'
        with tarfile.open(zig_archive, 'w', format=tarfile.USTAR_FORMAT) as archive:
            member = tarfile.TarInfo('zig-fixture/zig')
            member.mode = 0o755
            member.size = len(zig_script)
            archive.addfile(member, io.BytesIO(zig_script))
        source = json.loads((ROOT / 'runtime/source.json').read_text())
        source.update(url='https://ziglang.org/fixture-zig.tar',
                      sha256=hashlib.sha256(zig_archive.read_bytes()).hexdigest())
        (root / 'runtime/source.json').write_text(json.dumps(source))
        (root / 'runtime/test-toolchains.json').write_text(json.dumps({
            'x64musl': {'url': source['url'], 'sha256': source['sha256'], 'directory': 'zig-fixture'}}))
        (root / 'runtime/smoke.c').write_bytes((ROOT / 'runtime/smoke.c').read_bytes())
        archive = fixtures.RuntimeArchiveTests().archive(
            root, lambda manifest, members: manifest.__setitem__('source', source), combined=True)
        candidate = root / 'linux-runtime.tar.gz'
        archive.rename(candidate)
        with tarfile.open(candidate) as content:
            manifest = json.load(content.extractfile('manifest.json'))
        digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
        (root / 'runtime-lock.proposed.json').write_text(json.dumps({'sha256': digest}))
        (root / 'SHA256SUMS').write_text(f'{digest}  linux-runtime.tar.gz\n')
        sbom = sbom_document(manifest, digest, created='2026-10-29T00:00:00Z')
        if mutate_sbom:
            mutate_sbom(sbom)
        (root / 'runtime.spdx.json').write_text(json.dumps(sbom))
        tools = root / 'bin'
        tools.mkdir()
        curl = tools / 'curl'
        curl.write_text('#!' + sys.executable + '\n' +
                        'import os, shutil, sys\n' +
                        "shutil.copyfile(os.environ['FAKE_ZIG_ARCHIVE'], sys.argv[sys.argv.index('--output')+1])\n")
        curl.chmod(0o755)
        uname = tools / 'uname'
        uname.write_text('#!' + sys.executable + '\nimport sys\n' +
                         "print('Linux' if sys.argv[1] == '-s' else 'x86_64')\n")
        uname.chmod(0o755)
        supplied = root / 'smoke-x64musl'
        supplied.write_text('#!' + sys.executable + '\nimport os,pathlib\n' +
                            'pathlib.Path(os.environ["FALLBACK_RAN"]).write_text("supplied binary")\n')
        supplied.chmod(0o755)
        env = dict(os.environ, PATH=str(tools)+os.pathsep+os.environ['PATH'],
                   FAKE_ZIG_ARCHIVE=str(zig_archive), FAKE_ZIG_LOG=str(root / 'zig.log'),
                   FAKE_LINK_FAIL='1' if fail_link else '0', NATIVE_RAN=str(root / 'native-ran'),
                   FALLBACK_RAN=str(root / 'fallback-ran'))
        run = subprocess.run([str(self.binary), 'test', '--directory', str(root), '--target', 'x64musl'],
                             cwd=root, env=env, capture_output=True, timeout=30)
        return temporary, root, run

    def test_consistent_candidate_links_extracted_libraries_and_runs_new_output(self):
        temp, root, run = self.exercise()
        with temp:
            self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
            self.assertEqual((root / 'native-ran').read_text(), 'linked candidate')
            self.assertFalse((root / 'fallback-ran').exists())
            commands = [json.loads(line) for line in (root / 'zig.log').read_text().splitlines()]
            self.assertEqual(len(commands), 2)
            self.assertIn('-nostdlib', commands[1])
            self.assertNotIn(str(root / 'smoke-x64musl'), commands[1])

    def test_link_failure_never_runs_supplied_or_new_smoke(self):
        temp, root, run = self.exercise(fail_link=True)
        with temp:
            self.assertNotEqual(run.returncode, 0)
            self.assertIn('forced test link failure', run.stderr.decode(errors='replace'))
            self.assertFalse((root / 'native-ran').exists())
            self.assertFalse((root / 'fallback-ran').exists())

    def test_sbom_mutations_fail_before_invoking_native_toolchain(self):
        mutations = {
            'file checksum': lambda doc: doc['files'][0]['checksums'][0].update(checksumValue='0'*64),
            'missing file': lambda doc: doc['files'].pop(),
            'extra file': lambda doc: doc['files'].append(dict(doc['files'][0])),
            'archive digest': lambda doc: next(p for p in doc['packages'] if p['SPDXID']=='SPDXRef-runtime')['checksums'][0].update(checksumValue='0'*64),
            'source URL': lambda doc: doc['packages'][0].update(downloadLocation='https://example.com/other'),
            'source hash': lambda doc: next(p for p in doc['packages'] if p['SPDXID']=='SPDXRef-sources')['checksums'][0].update(checksumValue='0'*64),
            'relationship': lambda doc: doc['relationships'].pop(),
        }
        for label, change in mutations.items():
            with self.subTest(label=label):
                temp, root, run = self.exercise(mutate_sbom=change)
                with temp:
                    self.assertNotEqual(run.returncode, 0)
                    self.assertIn('Candidate SBOM differs from verified inventory', run.stderr.decode(errors='replace'))
                    self.assertFalse((root / 'zig.log').exists())


if __name__ == '__main__':
    unittest.main()
