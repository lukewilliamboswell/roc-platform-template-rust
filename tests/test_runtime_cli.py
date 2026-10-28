"""Independent archive-admission tests against the compiled Roc consumer."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
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

    def test_unsupported_schema_fails(self):
        self.verdict(lambda manifest, members: manifest.__setitem__('schema_version', 99))


if __name__ == '__main__':
    unittest.main()
