"""Independent process tests for the examples driver's verdict and deadline."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ExampleDriverTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        cls.runner = Path(cls.build.name) / 'examples'
        subprocess.run(['roc-stable', 'build', 'scripts/examples.roc',
                        f'--output={cls.runner}'], cwd=ROOT, check=True)

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def run_case(self, program, expected='ok\n', unlisted=False, empty=False, duplicate=False):
        with tempfile.TemporaryDirectory() as directory:
            suite = Path(directory)
            (suite / 'examples/demo').mkdir(parents=True)
            (suite / 'examples/demo/main.roc').write_text('app [main!] { pf: platform "unused" }')
            if unlisted:
                (suite / 'examples/unlisted.roc').write_text('app [main!] { pf: platform "unused" }')
            (suite / 'spec.json').write_text(json.dumps({
                'schema_version': 1, 'release': 'working-tree', 'dependencies': [],
                'apps': [{'path': 'examples/demo/main.roc', 'cases': [{'name': 'case', 'args': [],
                          'stdin': '', 'stdout': expected, 'stderr': '', 'exit_code': 0}]}]}))
            spec = json.loads((suite / 'spec.json').read_text())
            if empty:
                spec['apps'][0]['cases'] = []
            if duplicate:
                spec['apps'].append(spec['apps'][0])
            (suite / 'spec.json').write_text(json.dumps(spec))
            fake = suite / 'roc'
            fake.write_text('#!/usr/bin/env python3\nimport pathlib,sys\n'
                            'if sys.argv[1] == "build":\n'
                            ' p=pathlib.Path(next(a.split("=",1)[1] for a in sys.argv if a.startswith("--output=")))\n'
                            f' p.write_text({program!r})\n p.chmod(0o755)\n')
            fake.chmod(0o755)
            env = dict(os.environ, PATH=f'{suite}{os.pathsep}{os.environ["PATH"]}')
            return subprocess.run([str(self.runner), '--operation', 'run', '--suite', str(suite)],
                                  env=env, capture_output=True, timeout=20)

    def test_matching_output_passes(self):
        self.assertEqual(self.run_case('#!/bin/sh\nprintf "ok\\n"\n').returncode, 0)

    def test_wrong_output_fails(self):
        self.assertNotEqual(self.run_case('#!/bin/sh\nprintf "wrong\\n"\n').returncode, 0)

    def test_unlisted_application_fails(self):
        result = self.run_case('#!/bin/sh\nprintf "ok\\n"\n', unlisted=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'Every working-tree example application', result.stderr)

    def test_empty_cases_fail(self):
        result = self.run_case('#!/bin/sh\nprintf "ok\\n"\n', empty=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'Suite needs nonempty cases', result.stderr)

    def test_duplicate_applications_fail(self):
        result = self.run_case('#!/bin/sh\nprintf "ok\\n"\n', duplicate=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'Suite contains duplicate applications', result.stderr)

    def test_hang_fails_with_driver_deadline(self):
        # Parent timeout is deliberately longer: the driver's own deadline must fail first.
        self.assertNotEqual(self.run_case('#!/bin/sh\nexec sleep 60\n').returncode, 0)


if __name__ == '__main__':
    unittest.main()
