"""Independent archive-admission tests against the compiled Roc consumer."""
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

ROOT = Path(__file__).resolve().parents[1]
BINARY = os.environ.get('ROC_RUNTIME_BINARY')
LIBRARIES = ('crt1.o', 'libc.a', 'libunwind.a', 'libzigc.a', 'libcompiler_rt.a')
LICENSES = ('licenses/musl.txt', 'licenses/libunwind.txt', 'licenses/zig.txt')


class RuntimeArchiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        global BINARY
        if BINARY:
            BINARY = str(Path(BINARY).resolve())
        else:
            executable = ROOT / '.blueprint' / 'runtime-cli-tests'
            executable.parent.mkdir(exist_ok=True)
            subprocess.run(['roc-stable', 'build', 'scripts/runtime.roc', f'--output={executable}'],
                           cwd=ROOT, check=True, timeout=120)
            BINARY = str(executable)

    def archive(self, directory, mutate=None, combined=False):
        all_files = {f'targets/{target}/{name}': name.encode() for target in ('x64musl', 'arm64musl') for name in LIBRARIES}
        all_files.update({name: b'license' for name in LICENSES})
        manifest = {'schema_version': 1, 'source': json.loads((ROOT / 'runtime/source.json').read_text()),
                    'targets': {'x64musl': 'x86_64-linux-musl', 'arm64musl': 'aarch64-linux-musl'},
                    'files': {name: hashlib.sha256(data).hexdigest() for name, data in all_files.items()}}
        members = [(name, data, tarfile.REGTYPE) for name, data in all_files.items()
                   if combined or not name.startswith('targets/arm64musl/')]
        if mutate:
            mutate(manifest, members)
        members.append(('manifest.json', json.dumps(manifest).encode(), tarfile.REGTYPE))
        archive = Path(directory) / 'candidate.tar'
        with tarfile.open(archive, 'w', format=tarfile.USTAR_FORMAT) as tar:
            for name, data, kind in members:
                info = tarfile.TarInfo(name)
                info.type = kind
                info.size = len(data) if kind == tarfile.REGTYPE else 0
                if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE):
                    info.linkname = '../../outside'
                tar.addfile(info, io.BytesIO(data) if kind == tarfile.REGTYPE else None)
        return archive

    def verdict(self, mutate=None, passes=False, combined=False):
        with tempfile.TemporaryDirectory() as temp:
            archive = self.archive(temp, mutate, combined)
            run = subprocess.run([BINARY, 'inspect', str(archive), 'all' if combined else 'x64musl'],
                                 cwd=ROOT, capture_output=True, timeout=20)
            if passes:
                self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
            else:
                self.assertNotEqual(run.returncode, 0)

    def test_target_archive_passes(self):
        self.verdict(passes=True)

    def test_combined_archive_passes(self):
        self.verdict(passes=True, combined=True)

    def test_duplicate_member_fails(self):
        self.verdict(lambda manifest, members: members.append(members[0]))

    def test_missing_member_fails(self):
        self.verdict(lambda manifest, members: members.pop())

    def test_unexpected_member_fails(self):
        self.verdict(lambda manifest, members: members.append(('unexpected', b'', tarfile.REGTYPE)))

    def test_traversal_fails(self):
        self.verdict(lambda manifest, members: members.append(('../outside', b'', tarfile.REGTYPE)))

    def test_symlink_fails(self):
        self.verdict(lambda manifest, members: members.__setitem__(0, (members[0][0], b'', tarfile.SYMTYPE)))

    def test_hardlink_fails(self):
        self.verdict(lambda manifest, members: members.__setitem__(0, (members[0][0], b'', tarfile.LNKTYPE)))

    def test_fifo_fails(self):
        self.verdict(lambda manifest, members: members.__setitem__(0, (members[0][0], b'', tarfile.FIFOTYPE)))

    def test_wrong_member_hash_fails(self):
        self.verdict(lambda manifest, members: manifest['files'].__setitem__(members[0][0], '0' * 64))

    def test_missing_manifest_hash_fails(self):
        self.verdict(lambda manifest, members: manifest['files'].pop(members[0][0]))

    def test_extra_manifest_hash_fails(self):
        self.verdict(lambda manifest, members: manifest['files'].__setitem__('unexpected', '0' * 64))

    def test_wrong_target_mapping_fails(self):
        self.verdict(lambda manifest, members: manifest['targets'].__setitem__('x64musl', 'aarch64-linux-musl'))

    def test_wrong_source_pin_fails(self):
        self.verdict(lambda manifest, members: manifest['source'].__setitem__('sha256', '0' * 64))

    def install_candidate(self, prepare=None, mutate=None):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        (root / 'runtime').mkdir()
        (root / 'runtime/source.json').write_bytes((ROOT / 'runtime/source.json').read_bytes())
        archive = self.archive(root, mutate=mutate, combined=True)
        if prepare:
            prepare(root)
        run = subprocess.run([BINARY, 'install-candidate', str(archive)], cwd=root,
                             capture_output=True, timeout=20)
        return temporary, root, run

    def test_install_validates_every_member_before_writing(self):
        temp, root, run = self.install_candidate(
            mutate=lambda manifest, members: manifest['files'].__setitem__(members[-1][0], '0' * 64))
        with temp:
            self.assertNotEqual(run.returncode, 0)
            self.assertFalse((root / 'platform').exists())

    def test_install_rejects_symlinked_platform(self):
        def prepare(root):
            (root / 'outside').mkdir()
            (root / 'platform').symlink_to(root / 'outside', target_is_directory=True)
        temp, root, run = self.install_candidate(prepare=prepare)
        with temp:
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(list((root / 'outside').iterdir()), [])

    def test_install_rejects_symlinked_target_parent(self):
        def prepare(root):
            (root / 'outside').mkdir()
            (root / 'platform/targets').mkdir(parents=True)
            (root / 'platform/targets/x64musl').symlink_to(root / 'outside', target_is_directory=True)
        temp, root, run = self.install_candidate(prepare=prepare)
        with temp:
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(list((root / 'outside').iterdir()), [])

    def test_successful_install_writes_only_declared_files(self):
        temp, root, run = self.install_candidate()
        with temp:
            self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
            expected = {f'targets/{target}/{name}' for target in ('x64musl', 'arm64musl') for name in LIBRARIES}
            expected.update(f'runtime/{name}' for name in LICENSES)
            expected.add('runtime/manifest.json')
            actual = {str(path.relative_to(root / 'platform'))
                      for path in (root / 'platform').rglob('*') if path.is_file()}
            self.assertEqual(actual, expected)

    def fetch_fixture(self, corrupt=False, broken_download=False, mutate_lock=None, symlink=False, dirty_producer=False):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        checkout = root / 'checkout'
        subprocess.run(['git', 'clone', '--quiet', '--local', '--shared', str(ROOT), str(checkout)],
                       check=True, capture_output=True, timeout=20)
        fingerprint = subprocess.run([BINARY, 'fingerprint'], cwd=checkout, capture_output=True,
                                     check=True, timeout=20).stdout.decode().strip()
        archive = self.archive(root)
        data = archive.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        cache = root / 'cache'
        cache.mkdir()
        cached = cache / digest
        if symlink:
            cached.symlink_to(archive)
        else:
            cached.write_bytes(b'x' * len(data) if corrupt else data)
        record = {'asset': 'link-inputs-x64musl.tar', 'sha256': digest, 'size': len(data)}
        lock = {'schema_version': 1, 'kind': 'link-inputs',
                'repository': 'lukewilliamboswell/roc-platform-template-rust',
                'release': 'linker-inputs-sha256-' + '0' * 64,
                'manifest': {'asset': 'build-input-release.json', 'sha256': '0' * 64},
                'source': {'repository': 'lukewilliamboswell/roc-platform-template-rust',
                           'sha': '1' * 40, 'ref': 'refs/heads/fixture',
                           'workflow': 'lukewilliamboswell/roc-platform-template-rust/.github/workflows/runtime-release.yml',
                           'input_fingerprint': fingerprint},
                'targets': {'x64musl': record, 'arm64musl': dict(record, asset='link-inputs-arm64musl.tar')}}
        if mutate_lock:
            mutate_lock(lock)
        (checkout / 'runtime/link-inputs.lock.json').write_text(json.dumps(lock))
        if dirty_producer:
            source = checkout / 'runtime/source.json'
            source.write_text(source.read_text() + '\n')
        tools = root / 'bin'
        tools.mkdir()
        curl = tools / 'curl'
        curl.write_text('#!' + sys.executable + '\n' +
                        "import os, pathlib, shutil, sys\n" +
                        "pathlib.Path(os.environ['FAKE_CURL_LOG']).write_text('\\n'.join(sys.argv[1:]))\n" +
                        "shutil.copyfile(os.environ['FAKE_CURL_SOURCE'], sys.argv[sys.argv.index('--output') + 1])\n")
        curl.chmod(0o755)
        if broken_download:
            archive.write_bytes(b'broken download')
        log = root / 'curl.log'
        env = dict(os.environ, ROC_LINK_INPUT_CACHE=str(cache), FAKE_CURL_LOG=str(log),
                   FAKE_CURL_SOURCE=str(archive), PATH=str(tools) + os.pathsep + os.environ['PATH'])
        run = subprocess.run([BINARY, 'fetch', '--target', 'x64musl'], cwd=checkout,
                             env=env, capture_output=True, timeout=20)
        return temporary, checkout, cache, digest, log, run

    def test_verified_cache_hit_needs_no_network(self):
        temp, checkout, cache, digest, log, run = self.fetch_fixture()
        with temp:
            self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
            self.assertFalse(log.exists())
            self.assertTrue((checkout / 'platform/targets/x64musl/libc.a').is_file())

    def test_same_size_corrupt_cache_is_rehashed_and_downloaded_exactly(self):
        temp, checkout, cache, digest, log, run = self.fetch_fixture(corrupt=True)
        with temp:
            self.assertEqual(run.returncode, 0, run.stderr.decode(errors='replace'))
            self.assertEqual(hashlib.sha256((cache / digest).read_bytes()).hexdigest(), digest)
            self.assertIn('https://github.com/lukewilliamboswell/roc-platform-template-rust/releases/download/' +
                          'linker-inputs-sha256-' + '0' * 64 + '/link-inputs-x64musl.tar', log.read_text())

    def test_wrong_download_digest_fails_and_removes_cache(self):
        temp, checkout, cache, digest, log, run = self.fetch_fixture(corrupt=True, broken_download=True)
        with temp:
            self.assertNotEqual(run.returncode, 0)
            self.assertTrue(log.exists())
            self.assertFalse((cache / digest).exists())
            self.assertFalse((checkout / 'platform/targets/x64musl/libc.a').exists())

    def test_stale_fingerprint_fails_without_network(self):
        temp, checkout, cache, digest, log, run = self.fetch_fixture(
            mutate_lock=lambda lock: lock['source'].__setitem__('input_fingerprint', '0' * 64))
        with temp:
            self.assertNotEqual(run.returncode, 0)
            self.assertFalse(log.exists())

    def test_uncommitted_producer_changes_fail_without_network(self):
        temp, checkout, cache, digest, log, run = self.fetch_fixture(dirty_producer=True)
        with temp:
            self.assertNotEqual(run.returncode, 0)
            self.assertFalse(log.exists())

    def test_wrong_producer_identity_fails_without_network(self):
        temp, checkout, cache, digest, log, run = self.fetch_fixture(
            mutate_lock=lambda lock: lock['source'].__setitem__('workflow', 'wrong'))
        with temp:
            self.assertNotEqual(run.returncode, 0)
            self.assertFalse(log.exists())

    def test_symlink_cache_entry_fails_without_network(self):
        temp, checkout, cache, digest, log, run = self.fetch_fixture(symlink=True)
        with temp:
            self.assertNotEqual(run.returncode, 0)
            self.assertFalse(log.exists())

    def reject_native_metadata(self, change, expected_error):
        native_binary = ROOT / '.blueprint' / 'runtime-native-cli-tests'
        if not hasattr(type(self), '_native_binary'):
            subprocess.run(['roc-stable', 'build', 'scripts/runtime_test.roc', f'--output={native_binary}'],
                           cwd=ROOT, check=True, timeout=120)
            type(self)._native_binary = str(native_binary)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'runtime').mkdir()
            (root / 'runtime/source.json').write_bytes((ROOT / 'runtime/source.json').read_bytes())
            archive = self.archive(root, combined=True)
            archive.rename(root / 'linux-runtime.tar.gz')
            digest = hashlib.sha256((root / 'linux-runtime.tar.gz').read_bytes()).hexdigest()
            (root / 'runtime-lock.proposed.json').write_text(json.dumps({'sha256': digest}))
            (root / 'SHA256SUMS').write_text(f'{digest}  linux-runtime.tar.gz\n')
            (root / 'runtime.spdx.json').write_text(json.dumps({'creationInfo': {'created': '2026-10-29T00:00:00Z'}}))
            tools = root / 'bin'
            tools.mkdir()
            helper = ('#!' + sys.executable + '\n' +
                      'import pathlib, sys\n' +
                      "name = pathlib.Path(sys.argv[0]).name\n" +
                      "if name == 'uname': print('Linux' if sys.argv[1] == '-s' else 'x86_64')\n" +
                      "elif name == 'date': print(sys.argv[3])\n" +
                      "else: pathlib.Path('unexpected-download').write_text('called'); sys.exit(91)\n")
            for name in ('uname', 'date', 'curl'):
                executable = tools / name
                executable.write_text(helper)
                executable.chmod(0o755)
            change(root)
            env = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'])
            run = subprocess.run([type(self)._native_binary, 'test', '--directory', str(root),
                                  '--target', 'x64musl'], cwd=root, env=env, capture_output=True, timeout=20)
            self.assertNotEqual(run.returncode, 0)
            self.assertIn(expected_error, run.stderr.decode(errors='replace'))
            self.assertFalse((root / 'unexpected-download').exists())

    def test_native_candidate_rejects_wrong_archive_digest_before_download(self):
        self.reject_native_metadata(
            lambda root: (root / 'runtime-lock.proposed.json').write_text(json.dumps({'sha256': '0' * 64})),
            'Candidate archive differs from declared digest')

    def test_native_candidate_rejects_wrong_checksum_file_before_download(self):
        self.reject_native_metadata(lambda root: (root / 'SHA256SUMS').write_text('wrong'),
                                    'Candidate checksum file differs from archive')

    def test_native_candidate_rejects_wrong_sbom_before_download(self):
        self.reject_native_metadata(lambda root: None,
                                    'Candidate SBOM differs from verified inventory')

    def test_native_candidate_rejects_missing_timestamp_before_download(self):
        self.reject_native_metadata(lambda root: (root / 'runtime.spdx.json').write_text('{}'),
                                    'Candidate SBOM creation time is missing')

    def test_unsupported_schema_fails(self):
        self.verdict(lambda manifest, members: manifest.__setitem__('schema_version', 99))


if __name__ == '__main__':
    unittest.main()
