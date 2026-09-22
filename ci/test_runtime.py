"""Regression checks for the runtime download/extraction trust boundary."""
import io
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

import runtime


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / runtime.ARTIFACT
        self.contents = {name: (name + '\n').encode() for name in runtime.RUNTIME_FILES | runtime.LICENSE_FILES}
        manifest = {'schema_version': 1, 'targets': runtime.TARGETS,
                    'files': {name: runtime.digest(data) for name, data in self.contents.items()}}
        self.contents['manifest.json'] = json.dumps(manifest).encode()
        self.write_archive()

    def write_archive(self, extra=None):
        with tarfile.open(self.archive, 'w:gz') as tar:
            for name, data in self.contents.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            if extra:
                tar.addfile(extra, io.BytesIO(b'x' * extra.size))

    def test_complete_archive_installs_both_targets_and_licenses(self):
        with patch.object(runtime, 'ROOT', self.root):
            runtime.install(self.archive)
        for name, data in self.contents.items():
            path = self.root / 'platform' / (name if name.startswith('targets/') else 'runtime/' + name)
            self.assertEqual(path.read_bytes(), data)

    def test_rejects_unsafe_and_duplicate_members_without_writes(self):
        for name, kind in [('../escape', tarfile.REGTYPE), ('/escape', tarfile.REGTYPE),
                           ('targets/x64musl/libc.a', tarfile.REGTYPE),
                           ('targets/x64musl/evil', tarfile.SYMTYPE),
                           ('licenses/extra', tarfile.LNKTYPE)]:
            with self.subTest(name=name, kind=kind):
                info = tarfile.TarInfo(name)
                info.type = kind
                info.linkname = '/etc/passwd'
                self.write_archive(extra=info)
                with patch.object(runtime, 'ROOT', self.root), self.assertRaises(ValueError):
                    runtime.install(self.archive)
                self.assertFalse((self.root / 'platform').exists())

    def test_corrupted_member_fails_before_installation(self):
        self.contents['targets/x64musl/libc.a'] = b'corrupted'
        self.write_archive()
        with patch.object(runtime, 'ROOT', self.root), self.assertRaises(ValueError):
            runtime.install(self.archive)
        self.assertFalse((self.root / 'platform').exists())

    def test_missing_target_fails(self):
        del self.contents['targets/arm64musl/crt1.o']
        self.write_archive()
        with self.assertRaises(ValueError):
            runtime.inspect(self.archive)

    def test_symlink_destination_is_not_followed(self):
        outside = self.root / 'outside'
        outside.mkdir()
        (self.root / 'platform').symlink_to(outside, target_is_directory=True)
        with patch.object(runtime, 'ROOT', self.root), self.assertRaises(ValueError):
            runtime.install(self.archive)
        self.assertEqual(list(outside.iterdir()), [])

    def lock(self):
        return {'repository': runtime.REPOSITORY, 'tag': 'runtime-v1.0.0',
                'source_commit': 'a' * 40, 'sha256': runtime.digest(self.archive.read_bytes())}

    def download(self, url, destination):
        Path(destination).write_bytes(self.archive.read_bytes())

    def test_failed_provenance_or_sbom_never_installs(self):
        for failures in [[subprocess.CalledProcessError(1, 'gh')],
                         [None, subprocess.CalledProcessError(1, 'gh')]]:
            with self.subTest(failures=len(failures)), \
                 patch.object(runtime, 'read_json', return_value=self.lock()), \
                 patch.object(runtime, 'download', side_effect=self.download), \
                 patch.object(runtime, 'command', side_effect=failures), \
                 patch.object(runtime, 'install') as install:
                with self.assertRaises(subprocess.CalledProcessError):
                    runtime.fetch()
                install.assert_not_called()

    def test_archive_digest_checked_before_attestations(self):
        lock = self.lock()
        lock['sha256'] = '0' * 64
        with patch.object(runtime, 'read_json', return_value=lock), \
             patch.object(runtime, 'download', side_effect=self.download), \
             patch.object(runtime, 'command') as command, \
             patch.object(runtime, 'install') as install:
            with self.assertRaises(ValueError):
                runtime.fetch()
            command.assert_not_called()
            install.assert_not_called()

    def test_both_attestations_are_scoped_to_reviewed_identity(self):
        with patch.object(runtime, 'read_json', return_value=self.lock()), \
             patch.object(runtime, 'download', side_effect=self.download), \
             patch.object(runtime, 'command') as command, \
             patch.object(runtime, 'install') as install:
            runtime.fetch()
            self.assertEqual(command.call_count, 2)
            predicates = set()
            for call in command.call_args_list:
                args = call.args[0]
                for flag, value in [('--repo', runtime.REPOSITORY),
                                    ('--signer-workflow', runtime.REPOSITORY + '/' + runtime.WORKFLOW),
                                    ('--source-ref', 'refs/heads/main'), ('--source-digest', 'a' * 40)]:
                    self.assertEqual(args[args.index(flag) + 1], value)
                self.assertIn('--deny-self-hosted-runners', args)
                predicates.add(args[args.index('--predicate-type') + 1])
            self.assertEqual(predicates, {'https://slsa.dev/provenance/v1', 'https://spdx.dev/Document'})
            install.assert_called_once()

    def test_unbootstrapped_lock_does_not_download(self):
        with patch.object(runtime, 'read_json', return_value={'tag': None}), \
             patch.object(runtime, 'download') as download:
            with self.assertRaisesRegex(ValueError, 'not bootstrapped'):
                runtime.fetch()
            download.assert_not_called()


if __name__ == '__main__':
    unittest.main()
