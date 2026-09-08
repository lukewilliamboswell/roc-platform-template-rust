"""Release orchestration must fail closed before publication."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import runtime
import runtime_release as release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.sha = 'a' * 40
        self.tag = 'runtime-v1.0.0'
        self.env = {'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_REF': 'refs/heads/main',
                    'GITHUB_REPOSITORY': runtime.REPOSITORY, 'GITHUB_SHA': self.sha,
                    'RUNTIME_TAG': self.tag}
        self.lock = {'tag': self.tag, 'source_commit': self.sha, 'repository': runtime.REPOSITORY}

    def test_invalid_versions_rejected(self):
        for version in ['v1.0.0', '01.0.0', '1.0', '1.0.0\ninjected=value', '../1.0.0']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                release.release_tag(version)
        self.assertEqual(release.release_tag('1.0.0'), self.tag)

    def test_publication_rejects_untrusted_context(self):
        for key, value in [('GITHUB_EVENT_NAME', 'pull_request'), ('GITHUB_REF', 'refs/heads/feature'),
                           ('GITHUB_REPOSITORY', 'other/repository')]:
            with self.subTest(key=key), patch.dict(os.environ, self.env | {key: value}, clear=True), \
                 patch.object(subprocess, 'check_output') as command, self.assertRaises(ValueError):
                release.publication_context()
            command.assert_not_called()

    def test_publication_rejects_wrong_checkout(self):
        with patch.dict(os.environ, self.env, clear=True), \
             patch.object(subprocess, 'check_output', return_value='b' * 40), self.assertRaises(ValueError):
            release.publication_context()

    def test_existing_tag_or_api_failure_prevents_release(self):
        for response in ['[{"ref":"refs/tags/runtime-v1.0.0"}]', subprocess.CalledProcessError(1, 'gh')]:
            with self.subTest(response=response), \
                 patch.object(release, 'publication_context', return_value=(self.tag, self.sha)), \
                 patch.object(release, 'check_candidate', return_value=self.lock), \
                 patch.object(subprocess, 'check_output', side_effect=[response]), \
                 patch.object(runtime, 'command') as command:
                with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                    release.publish(Path('unused'))
                command.assert_not_called()

    def test_candidate_identity_checked_before_github_writes(self):
        with patch.object(release, 'publication_context', return_value=(self.tag, self.sha)), \
             patch.object(release, 'check_candidate', return_value=self.lock | {'source_commit': 'b' * 40}), \
             patch.object(subprocess, 'check_output') as command, self.assertRaises(ValueError):
            release.preflight(Path('unused'))
        command.assert_not_called()

    def test_smoke_does_not_execute_unverified_candidate(self):
        with patch.object(release, 'check_candidate', side_effect=ValueError('bad digest')), \
             patch.object(runtime, 'command') as command, self.assertRaises(ValueError):
            release.test_candidate(Path('unused'), 'x64musl')
        command.assert_not_called()

    def test_pr_request_defaults_to_non_release_version(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp) / 'output'
            with patch.dict(os.environ, {'GITHUB_OUTPUT': str(output)}, clear=True):
                release.request()
            self.assertEqual(output.read_text(), 'tag=runtime-v0.0.0\n')



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
