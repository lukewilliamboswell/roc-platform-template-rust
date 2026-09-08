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


if __name__ == '__main__':
    unittest.main()
