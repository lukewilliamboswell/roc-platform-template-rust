#!/usr/bin/env python3
"""Independent integration assertions over the exact release candidate files.

Run through `blueprint run release-evidence-test -- dist` after prepare-sbom.
The harness invokes the released checker; it never regenerates accepted SBOMs.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
args = [arg for arg in sys.argv[1:] if arg != "--"]
DIRECTORY = (ROOT / (args[0] if args else "dist")).resolve()
sys.argv[1:] = []


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ReleaseEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = read(DIRECTORY / "release-evidence.json")
        cls.manifests = sorted(DIRECTORY.glob("*.sbom-manifest.json"))
        if len(cls.manifests) != 4:
            raise AssertionError("exactly four deliverables need bound SBOM manifests")
        cls.platform_manifest = next(path for path in cls.manifests if ".tar.zst." in path.name)
        cls.platform = read(cls.platform_manifest)["subject"]["filename"]
        cls.inventory = read(DIRECTORY / (cls.platform + ".sbom-inventory.json"))

    def check(self, manifest, inventory, artifacts, success=True):
        result = subprocess.run(
            ["blueprint-sbom", "check", "--manifest", str(manifest),
             "--inventory", str(inventory), "--artifacts", str(artifacts)],
            capture_output=True, text=True, timeout=30,
        )
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)

    def test_explicit_asset_set_matches_bound_evidence(self):
        listed = (DIRECTORY / "release-assets.txt").read_text().splitlines()
        self.assertEqual(len(listed), len(set(listed)))
        expected = {Path(entry["path"]).name for entry in self.evidence["files"]}
        # SHA256SUMS and notes are appended only after this phase is validated.
        expected.add("release-evidence.json")
        self.assertEqual({Path(path).name for path in listed}, expected)
        for entry in self.evidence["files"]:
            path = DIRECTORY / Path(entry["path"]).name
            self.assertTrue(path.is_file() and not path.is_symlink())
            self.assertEqual(path.stat().st_size, entry["size"])
            self.assertEqual(sha(path), entry["sha256"])

    def test_every_subject_manifest_checks_against_final_bytes(self):
        for manifest in self.manifests:
            with self.subTest(manifest=manifest.name):
                name = read(manifest)["subject"]["filename"]
                self.check(manifest, DIRECTORY / (name + ".sbom-inventory.json"), DIRECTORY)

    def test_native_graph_preserves_targets_containment_and_gaps(self):
        self.assertEqual(self.inventory["target"], "source")
        components = {entry["id"]: entry for entry in self.inventory["components"]}
        by_name = {entry["name"]: entry for entry in components.values()}
        edges = self.inventory["relationships"]
        for target, system in [("x64mac", "x86_64-darwin"), ("arm64mac", "aarch64-darwin"),
                               ("x64musl", "x86_64-linux"), ("arm64musl", "aarch64-linux")]:
            host = by_name[f"targets/{target}/libhost.a"]
            self.assertEqual(host["target"], system)
            self.assertEqual(len(host["sha256"]), 64)
            self.assertIn({"from": host["id"], "to": "rust-std-" + target, "relation": "contains"},
                          [{key: edge[key] for key in ["from", "to", "relation"]} for edge in edges])
        for target in ["x64musl", "arm64musl"]:
            libc = by_name[f"targets/{target}/libc.a"]
            self.assertTrue(any(edge["from"] == libc["id"] and edge["to"] == "musl-" + target
                                and edge["relation"] == "contains" for edge in edges))
        self.assertTrue(any(edge["to"] == "rustc" and edge["relation"] == "dependsOn"
                            and edge["scope"] == "build" for edge in edges))
        self.assertFalse(any(edge["to"] == "rustc" and edge["relation"] == "contains" for edge in edges))
        gaps = {entry["scope"]: entry["status"] for entry in self.inventory["coverage"]}
        self.assertEqual(gaps["supplier-linker-input-sboms"], "incomplete")
        self.assertEqual(gaps["rust-native-closure"], "incomplete")
        self.assertEqual(gaps["cargo-dependencies"], "verified-empty")

    def test_examples_reference_platform_without_claiming_it_is_embedded(self):
        path = next(DIRECTORY.glob("*-examples-*.zip.sbom-inventory.json"))
        inventory = read(path)
        self.assertTrue(any(edge["to"] == "platform" and edge["relation"] == "dependsOn"
                            for edge in inventory["relationships"]))
        self.assertFalse(any(edge["to"] == "platform" and edge["relation"] == "contains"
                             for edge in inventory["relationships"]))

    def test_changed_subject_missing_sidecar_and_changed_inventory_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary)
            for path in DIRECTORY.glob(self.platform + "*"):
                if path.is_file():
                    shutil.copyfile(path, destination / path.name)
            manifest = destination / self.platform_manifest.name
            inventory = destination / (self.platform + ".sbom-inventory.json")
            subject = destination / self.platform
            original = subject.read_bytes()
            subject.write_bytes(original + b"changed")
            self.check(manifest, inventory, destination, success=False)
            subject.write_bytes(original)
            cdx = destination / (self.platform + ".cdx.json")
            cdx.rename(destination / "missing.cdx.json")
            self.check(manifest, inventory, destination, success=False)
            (destination / "missing.cdx.json").rename(cdx)
            data = read(inventory)
            data["target"] = "aarch64-darwin"
            inventory.write_text(json.dumps(data))
            self.check(manifest, inventory, destination, success=False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
