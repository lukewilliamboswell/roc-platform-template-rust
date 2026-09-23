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

    def test_unbootstrapped_lock_does_not_download(self):
        with patch.object(runtime, 'LOCK', self.root / 'missing.lock.json'), \
             patch.object(runtime, 'download') as download:
            with self.assertRaisesRegex(ValueError, 'publisher-generated'):
                runtime.fetch()
            download.assert_not_called()

    def locked_target(self, cache_bytes=None):
        archive = self.root / 'target.tar'
        target = 'x64musl'
        names = {f'targets/{target}/{name}' for name in runtime.LIBRARIES} | runtime.LICENSE_FILES | {'manifest.json'}
        with tarfile.open(archive, 'w') as tar:
            for name in sorted(names):
                data = self.contents[name]
                member = tarfile.TarInfo(name)
                member.size = len(data)
                tar.addfile(member, io.BytesIO(data))
        data = archive.read_bytes()
        fingerprint = 'f' * 64
        records = {}
        for name in runtime.TARGETS:
            records[name] = {'asset': f'link-inputs-{name}.tar', 'sha256': runtime.digest(data), 'size': len(data)}
        lock = {
            'schema_version': 1, 'kind': 'link-inputs', 'repository': runtime.REPOSITORY,
            'release': 'linker-inputs-sha256-' + 'a' * 64,
            'manifest': {'asset': runtime.RELEASE_MANIFEST, 'sha256': 'b' * 64},
            'source': {'repository': runtime.REPOSITORY, 'sha': 'c' * 40,
                       'ref': 'refs/heads/change-runtime',
                       'workflow': runtime.REPOSITORY + '/' + runtime.WORKFLOW,
                       'input_fingerprint': fingerprint},
            'targets': records,
        }
        lock_path = self.root / 'link-inputs.lock.json'
        runtime.write_json(lock_path, lock)
        cache = self.root / 'cache'
        cache.mkdir()
        if cache_bytes is not None:
            (cache / runtime.digest(data)).write_bytes(cache_bytes)
        return target, data, fingerprint, lock_path, cache

    def test_locked_cache_hit_is_rehashed_without_network(self):
        target, data, fingerprint, lock_path, cache = self.locked_target()
        (cache / runtime.digest(data)).write_bytes(data)
        with patch.object(runtime, 'ROOT', self.root), patch.object(runtime, 'LOCK', lock_path), \
             patch.object(runtime, 'input_fingerprint', return_value=fingerprint), \
             patch.dict(runtime.os.environ, {'ROC_LINK_INPUT_CACHE': str(cache)}), \
             patch.object(runtime, 'download') as download:
            runtime.fetch_locked([target])
        download.assert_not_called()
        self.assertTrue((self.root / f'platform/targets/{target}/libc.a').is_file())

    def test_corrupt_cache_entry_is_replaced_from_exact_release(self):
        target, data, fingerprint, lock_path, cache = self.locked_target(b'corrupt')
        def replace(url, destination):
            self.assertIn('linker-inputs-sha256-', url)
            Path(destination).write_bytes(data)
        with patch.object(runtime, 'ROOT', self.root), patch.object(runtime, 'LOCK', lock_path), \
             patch.object(runtime, 'input_fingerprint', return_value=fingerprint), \
             patch.dict(runtime.os.environ, {'ROC_LINK_INPUT_CACHE': str(cache)}), \
             patch.object(runtime, 'download', side_effect=replace) as download:
            runtime.fetch_locked([target])
        download.assert_called_once()


if __name__ == '__main__':
    unittest.main()
