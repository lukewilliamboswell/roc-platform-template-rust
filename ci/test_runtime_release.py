"""Release orchestration must fail closed before publication."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import runtime
import runtime_release as release


class CandidateTests(unittest.TestCase):
    def setUp(self):
        import io
        import json
        import tarfile
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.contents = {name: name.encode() for name in runtime.RUNTIME_FILES | runtime.LICENSE_FILES}
        self.manifest = {'schema_version': 1, 'targets': runtime.TARGETS,
                         'source': runtime.read_json(runtime.ROOT / 'runtime/source.json'),
                         'files': {name: runtime.digest(data) for name, data in self.contents.items()}}
        self.contents['manifest.json'] = json.dumps(self.manifest).encode()
        with tarfile.open(self.directory / runtime.ARTIFACT, 'w:gz') as tar:
            for name, data in self.contents.items():
                member = tarfile.TarInfo(name)
                member.size = len(data)
                tar.addfile(member, io.BytesIO(data))
        self.sha = runtime.digest((self.directory / runtime.ARTIFACT).read_bytes())
        runtime.write_json(self.directory / 'runtime-lock.proposed.json', {'sha256': self.sha})
        self.sbom = runtime.sbom_document(self.manifest, self.sha)
        runtime.write_json(self.directory / 'runtime.spdx.json', self.sbom)
        (self.directory / 'SHA256SUMS').write_text(f'{self.sha}  {runtime.ARTIFACT}\n')

    def test_complete_consistent_inventory_accepted(self):
        self.assertEqual(release.check_candidate(self.directory)['sha256'], self.sha)

    def test_mismatched_sbom_rejected(self):
        import copy
        mutations = {
            'file checksum': lambda doc: doc['files'][0]['checksums'][0].update(checksumValue='0' * 64),
            'missing file': lambda doc: doc['files'].pop(),
            'extra file': lambda doc: doc['files'].append(copy.deepcopy(doc['files'][0])),
            'archive digest': lambda doc: next(p for p in doc['packages'] if p['SPDXID'] == 'SPDXRef-runtime')['checksums'][0].update(checksumValue='0' * 64),
            'source URL': lambda doc: doc['packages'][0].update(downloadLocation='https://example.com/other.tar.xz'),
            'source hash': lambda doc: next(p for p in doc['packages'] if p['SPDXID'] == 'SPDXRef-sources')['checksums'][0].update(checksumValue='0' * 64),
            'relationship': lambda doc: doc['relationships'].pop(),
        }
        for label, mutate in mutations.items():
            with self.subTest(label=label):
                document = copy.deepcopy(self.sbom)
                mutate(document)
                runtime.write_json(self.directory / 'runtime.spdx.json', document)
                with self.assertRaisesRegex(ValueError, 'SBOM differs'):
                    release.check_candidate(self.directory)

    def test_archive_source_must_match_reviewed_source(self):
        reviewed = self.manifest['source'] | {'sha256': '0' * 64}
        original = runtime.read_json
        def read(path):
            return reviewed if path == runtime.ROOT / 'runtime/source.json' else original(path)
        with patch.object(runtime, 'read_json', side_effect=read), self.assertRaisesRegex(ValueError, 'reviewed source pin'):
            release.check_candidate(self.directory)

    def test_incorrect_checksum_sidecar_rejected(self):
        (self.directory / 'SHA256SUMS').write_text('0' * 64 + f'  {runtime.ARTIFACT}\n')
        with self.assertRaisesRegex(ValueError, 'checksum file'):
            release.check_candidate(self.directory)

    def test_native_test_links_extracted_libraries_not_downloaded_smoke(self):
        # A success-only binary supplied by the build must never be executed.
        supplied = self.directory / 'smoke-x64musl'
        supplied.write_text('#!/bin/sh\nexit 0\n')
        def link(zig, libraries, target, output, env):
            self.assertEqual(target, 'x64musl')
            for name in runtime.LIBRARIES:
                self.assertEqual((libraries / name).read_bytes(), self.contents[f'targets/x64musl/{name}'])
            self.assertNotEqual(output, supplied)
        with patch.object(release.platform, 'system', return_value='Linux'), \
             patch.object(release.platform, 'machine', return_value='x86_64'), \
             patch.object(runtime, 'install_zig', return_value=Path('/trusted/zig')), \
             patch.object(runtime, 'link_smoke', side_effect=link) as linker, \
             patch.object(runtime, 'command') as run:
            release.test_candidate(self.directory, 'x64musl')
        linker.assert_called_once()
        run.assert_called_once()
        self.assertNotEqual(run.call_args.args[0][0], supplied)

    def test_link_failure_cannot_fall_back_to_supplied_smoke(self):
        with patch.object(release.platform, 'system', return_value='Linux'), \
             patch.object(release.platform, 'machine', return_value='x86_64'), \
             patch.object(runtime, 'install_zig', return_value=Path('/trusted/zig')), \
             patch.object(runtime, 'link_smoke', side_effect=subprocess.CalledProcessError(1, 'zig')), \
             patch.object(runtime, 'command') as run, self.assertRaises(subprocess.CalledProcessError):
            release.test_candidate(self.directory, 'x64musl')
        run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
