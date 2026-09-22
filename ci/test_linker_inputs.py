"""Trust-boundary and reproducibility tests for aggregate linker inputs."""

import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).parents[1] / "scripts/linker_inputs.py"
SPEC = importlib.util.spec_from_file_location("linker_inputs", SCRIPT)
linker_inputs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(linker_inputs)


class LinkerInputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.archive = self.root / linker_inputs.ARTIFACT
        self.contents = {name: (name + "\n").encode() for name in linker_inputs.MEMBERS - {"dependency.json"}}
        inputs = {"linux": {"version": "pinned"}, "macos_catalog_sha256": "a" * 64,
                  "macos_generator_sha256": "b" * 64}
        manifest = {
            "schema_version": 1, "name": "roc-platform-template-rust-linker-inputs",
            "targets": {key: list(value) for key, value in linker_inputs.TARGET_FILES.items()},
            "inputs": inputs, "input_fingerprint": linker_inputs.digest(linker_inputs.canonical(inputs)),
            "files": {name: linker_inputs.digest(data) for name, data in sorted(self.contents.items())},
        }
        self.contents["dependency.json"] = linker_inputs.canonical(manifest)
        linker_inputs.write_archive(self.archive, self.contents)

    def lock(self):
        return {
            "schema_version": 1, "repository": linker_inputs.REPOSITORY, "tag": "linker-inputs-v1.0.0",
            "archive": {"name": linker_inputs.ARTIFACT, "sha256": linker_inputs.digest(self.archive.read_bytes()), "size": self.archive.stat().st_size},
            "source": {"commit": "a" * 40, "ref": "refs/heads/main"},
            "signer": {"repository": "lukewilliamboswell/roc-automation", "workflow": ".github/workflows/publish-linker-inputs.yml", "source_commit": "b" * 40},
            "sbom_sha256": "c" * 64,
            "input_fingerprint": json.loads(self.contents["dependency.json"])["input_fingerprint"],
        }

    def test_valid_archive_checks_and_stages_only_declared_files(self):
        contents = linker_inputs.check_archive(self.archive, linker_inputs.validate_lock(self.lock()))
        destination = self.root / "platform"
        linker_inputs.stage_contents(contents, destination)
        self.assertEqual((destination / "targets/x64mac/libSystem.tbd").read_bytes(), self.contents["targets/x64mac/libSystem.tbd"])
        self.assertEqual((destination / "linker-inputs/dependency.json").read_bytes(), self.contents["dependency.json"])

    def test_rejects_digest_size_fingerprint_and_extra_lock_fields(self):
        mutations = [
            lambda lock: lock["archive"].update(sha256="0" * 64),
            lambda lock: lock["archive"].update(size=lock["archive"]["size"] + 1),
            lambda lock: lock.update(input_fingerprint="0" * 64),
        ]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                lock = self.lock()
                mutate(lock)
                with self.assertRaises(ValueError):
                    linker_inputs.check_archive(self.archive, linker_inputs.validate_lock(lock))
        lock = self.lock() | {"unexpected": True}
        with self.assertRaises(ValueError):
            linker_inputs.validate_lock(lock)

    def test_rejects_traversal_links_duplicates_and_unknown_members(self):
        for name, kind in [("../escape", tarfile.REGTYPE), ("/escape", tarfile.REGTYPE),
                           ("targets/x64mac/libSystem.tbd", tarfile.REGTYPE), ("unknown", tarfile.SYMTYPE)]:
            with self.subTest(name=name, kind=kind):
                bad = self.root / (str(abs(hash((name, kind)))) + ".tar.gz")
                with tarfile.open(bad, "w:gz") as tar:
                    for member_name, data in self.contents.items():
                        member = tarfile.TarInfo(member_name)
                        member.size = len(data)
                        tar.addfile(member, io.BytesIO(data))
                    extra = tarfile.TarInfo(name)
                    extra.type = kind
                    extra.linkname = "/etc/passwd"
                    tar.addfile(extra, io.BytesIO(b"x") if kind == tarfile.REGTYPE else None)
                with self.assertRaises(ValueError):
                    linker_inputs.archive_contents(bad)

    def test_corruption_fails_before_any_staging(self):
        contents = dict(self.contents)
        contents["targets/x64musl/libc.a"] = b"corrupt"
        linker_inputs.write_archive(self.archive, contents)
        destination = self.root / "platform"
        with self.assertRaises(ValueError):
            linker_inputs.check_archive(self.archive)
        self.assertFalse(destination.exists())

    def test_destination_symlink_is_never_followed(self):
        outside = self.root / "outside"
        outside.mkdir()
        destination = self.root / "platform"
        destination.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(ValueError):
            linker_inputs.stage_contents(linker_inputs.archive_contents(self.archive), destination)
        self.assertEqual(list(outside.iterdir()), [])

    def test_tbd_is_catalog_only_and_deterministic(self):
        catalog = linker_inputs.read_json(Path(__file__).parents[1] / "linker-inputs/macos/interfaces.json")
        with patch.object(Path, "read_bytes", side_effect=AssertionError("renderer must not read files")):
            first = linker_inputs.render_tbd(catalog)
            second = linker_inputs.render_tbd(catalog)
        self.assertEqual(first, second)
        self.assertIn(b"x86_64-macos, arm64-macos", first)
        self.assertIn(b"/usr/lib/libSystem.B.dylib", first)

    def test_attestations_are_scoped_to_pinned_cross_repo_signer(self):
        with patch.object(linker_inputs.subprocess, "run") as run:
            linker_inputs.verify_attestations(self.archive, self.lock())
        self.assertEqual(run.call_count, 1)
        for call in run.call_args_list:
            args = call.args[0]
            self.assertEqual(args[args.index("--repo") + 1], linker_inputs.REPOSITORY)
            self.assertEqual(args[args.index("--signer-repo") + 1], "lukewilliamboswell/roc-automation")
            self.assertEqual(args[args.index("--source-digest") + 1], "a" * 40)
            self.assertIn("--deny-self-hosted-runners", args)
            self.assertEqual(args[args.index("--predicate-type") + 1], "https://slsa.dev/provenance/v1")


if __name__ == "__main__":
    unittest.main()
