#!/usr/bin/env python3
"""Build, verify, fetch and stage independently released linker inputs."""

import argparse
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "ci"))
import runtime  # noqa: E402 - existing checksum-pinned Linux producer

REPOSITORY = "lukewilliamboswell/roc-platform-template-rust"
ARTIFACT = "linker-inputs.tar.gz"
LOCK = ROOT / "linker-inputs.lock.json"
TARGET_FILES = {
    "x64musl": runtime.LIBRARIES,
    "arm64musl": runtime.LIBRARIES,
    "x64mac": ("libSystem.tbd",),
    "arm64mac": ("libSystem.tbd",),
}
NOTICE_FILES = (
    "licenses/musl.txt", "licenses/libunwind.txt", "licenses/zig.txt",
    "notices/THIRD_PARTY_NOTICES.md", "macos/interfaces.json", "macos/PROVENANCE.md",
)
DATA_FILES = {f"targets/{target}/{name}" for target, names in TARGET_FILES.items() for name in names}
MEMBERS = DATA_FILES | set(NOTICE_FILES) | {"dependency.json"}
HEX64 = re.compile(r"[0-9a-f]{64}")
HEX40 = re.compile(r"[0-9a-f]{40}")
TAG = re.compile(r"linker-inputs-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    Path(path).write_bytes(canonical(value))


def render_tbd(catalog):
    if catalog.get("schema_version") != 1 or catalog.get("library") != "libSystem":
        raise ValueError("Unsupported macOS interface catalog")
    symbols = catalog.get("symbols")
    if not isinstance(symbols, list) or len(symbols) != len(set(symbols)) or not all(re.fullmatch(r"_[A-Za-z0-9_$]+", s) for s in symbols):
        raise ValueError("macOS symbols must be unique C linker names")
    quoted = ", ".join(sorted(symbols))
    return (
        "--- !tapi-tbd\n"
        "tbd-version:     4\n"
        "targets:         [ x86_64-macos, arm64-macos ]\n"
        f"install-name:    '{catalog['install_name']}'\n"
        "current-version: 1.1\n"
        "compatibility-version: 1\n"
        "exports:\n"
        "  - targets:         [ x86_64-macos, arm64-macos ]\n"
        f"    symbols:         [ {quoted} ]\n"
        "...\n"
    ).encode()


def archive_contents(archive):
    contents = {}
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar:
            if member.name not in MEMBERS or member.name in contents or not member.isfile() or member.size > 64 * 1024 * 1024:
                raise ValueError(f"Unexpected linker-input archive member: {member.name}")
            contents[member.name] = tar.extractfile(member).read()
    if set(contents) != MEMBERS:
        raise ValueError(f"Archive inventory differs: missing={sorted(MEMBERS - set(contents))}")
    manifest = json.loads(contents["dependency.json"])
    if manifest.get("schema_version") != 1 or manifest.get("name") != "roc-platform-template-rust-linker-inputs":
        raise ValueError("Unsupported linker-input dependency manifest")
    expected_targets = {key: list(value) for key, value in TARGET_FILES.items()}
    if manifest.get("targets") != expected_targets:
        raise ValueError("Manifest target contract differs")
    hashes = manifest.get("files")
    if not isinstance(hashes, dict) or set(hashes) != MEMBERS - {"dependency.json"}:
        raise ValueError("Manifest file inventory differs")
    for name, expected in hashes.items():
        if not HEX64.fullmatch(expected) or digest(contents[name]) != expected:
            raise ValueError(f"Member digest mismatch: {name}")
    inputs = manifest.get("inputs", {})
    expected_fingerprint = digest(canonical(inputs))
    if manifest.get("input_fingerprint") != expected_fingerprint:
        raise ValueError("Input fingerprint mismatch")
    return contents


def write_archive(path, contents):
    with path.open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as zipped:
        with tarfile.open(fileobj=zipped, mode="w", format=tarfile.USTAR_FORMAT) as tar:
            for name, data in sorted(contents.items()):
                member = tarfile.TarInfo(name)
                member.size = len(data)
                member.mode = 0o644
                member.mtime = member.uid = member.gid = 0
                member.uname = member.gname = ""
                tar.addfile(member, io.BytesIO(data))


def build(output):
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="linker-inputs-build-") as temporary:
        runtime_output = Path(temporary) / "runtime"
        runtime.build(runtime_output)
        linux = runtime.inspect(runtime_output / runtime.ARTIFACT)
        catalog_bytes = (ROOT / "linker-inputs/macos/interfaces.json").read_bytes()
        catalog = json.loads(catalog_bytes)
        tbd = render_tbd(catalog)
        contents = {}
        for target in runtime.TARGETS:
            for name in runtime.LIBRARIES:
                contents[f"targets/{target}/{name}"] = linux[f"targets/{target}/{name}"]
        for target in ("x64mac", "arm64mac"):
            contents[f"targets/{target}/libSystem.tbd"] = tbd
        for name in ("musl.txt", "libunwind.txt", "zig.txt"):
            contents[f"licenses/{name}"] = linux[f"licenses/{name}"]
        contents["notices/THIRD_PARTY_NOTICES.md"] = (ROOT / "linker-inputs/THIRD_PARTY_NOTICES.md").read_bytes()
        contents["macos/interfaces.json"] = catalog_bytes
        contents["macos/PROVENANCE.md"] = (ROOT / "linker-inputs/macos/PROVENANCE.md").read_bytes()
        inputs = {
            "linux": read_json(ROOT / "runtime/source.json"),
            "macos_catalog_sha256": digest(catalog_bytes),
            "macos_generator_sha256": digest(Path(__file__).read_bytes()),
        }
        manifest = {
            "schema_version": 1,
            "name": "roc-platform-template-rust-linker-inputs",
            "targets": {key: list(value) for key, value in TARGET_FILES.items()},
            "inputs": inputs,
            "input_fingerprint": digest(canonical(inputs)),
            "files": {name: digest(data) for name, data in sorted(contents.items())},
        }
        contents["dependency.json"] = canonical(manifest)
        archive = output / ARTIFACT
        write_archive(archive, contents)
        archive_contents(archive)
        archive_sha = digest(archive.read_bytes())
        sbom = sbom_document(manifest, archive_sha)
        write_json(output / "linker-inputs.spdx.json", sbom)
        (output / "SHA256SUMS").write_text(f"{archive_sha}  {ARTIFACT}\n")
        proposed = {
            "schema_version": 1,
            "repository": REPOSITORY,
            "tag": os.environ.get("LINKER_INPUTS_TAG"),
            "archive": {"name": ARTIFACT, "sha256": archive_sha, "size": archive.stat().st_size},
            "source": {"commit": os.environ.get("GITHUB_SHA"), "ref": "refs/heads/main"},
            "signer": {
                "repository": "lukewilliamboswell/roc-automation",
                "workflow": ".github/workflows/publish-linker-inputs.yml",
                "source_commit": os.environ.get("PUBLISHER_SHA"),
            },
            "sbom_sha256": digest((output / "linker-inputs.spdx.json").read_bytes()),
            "input_fingerprint": manifest["input_fingerprint"],
        }
        write_json(output / "linker-inputs.lock.proposed.json", proposed)
        release_manifest(output, proposed)


def sbom_document(manifest, archive_sha, created=None):
    files = []
    relationships = [{"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES", "relatedSpdxElement": "SPDXRef-archive"}]
    for index, (name, sha) in enumerate(sorted(manifest["files"].items())):
        identifier = f"SPDXRef-file-{index}"
        files.append({"fileName": name, "SPDXID": identifier, "checksums": [{"algorithm": "SHA256", "checksumValue": sha}], "licenseConcluded": "NOASSERTION", "copyrightText": "NOASSERTION"})
        relationships.append({"spdxElementId": "SPDXRef-archive", "relationshipType": "CONTAINS", "relatedSpdxElement": identifier})
    return {
        "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT",
        "name": "Roc Rust platform linker inputs", "documentNamespace": f"https://github.com/{REPOSITORY}/linker-inputs/{archive_sha}",
        "creationInfo": {"creators": ["Tool: linker_inputs.py"], "created": created or "1970-01-01T00:00:00Z"},
        "packages": [{"name": ARTIFACT, "SPDXID": "SPDXRef-archive", "downloadLocation": "NOASSERTION", "filesAnalyzed": True, "licenseDeclared": "NOASSERTION", "copyrightText": "NOASSERTION", "checksums": [{"algorithm": "SHA256", "checksumValue": archive_sha}]}],
        "files": files, "relationships": relationships,
    }


def release_manifest(output, proposed):
    assets = []
    for name in (ARTIFACT, "SHA256SUMS", "linker-inputs.spdx.json", "linker-inputs.lock.proposed.json"):
        path = output / name
        assets.append({"name": name, "sha256": digest(path.read_bytes()), "size": path.stat().st_size})
    manifest = {
        "schema_version": 1,
        "release_tag": proposed["tag"],
        "source": {"repository": REPOSITORY, "commit": proposed["source"]["commit"], "ref": proposed["source"]["ref"]},
        "assets": assets,
        "input_fingerprint": proposed["input_fingerprint"],
        "targets": sorted(TARGET_FILES),
        "dependencies": ["musl", "LLVM libunwind", "Zig runtime", "project-authored macOS libSystem interface"],
        "license_summary": "See THIRD_PARTY_NOTICES.md and license files inside the archive",
    }
    write_json(output / "dependency.json", manifest)


def validate_lock(lock):
    required = {"schema_version", "repository", "tag", "archive", "source", "signer", "sbom_sha256", "input_fingerprint"}
    if set(lock) != required or lock["schema_version"] != 1 or lock["repository"] != REPOSITORY or not TAG.fullmatch(lock["tag"] or ""):
        raise ValueError("Invalid or unbootstrapped linker-input lock")
    archive = lock["archive"]
    if set(archive) != {"name", "sha256", "size"} or archive["name"] != ARTIFACT or not HEX64.fullmatch(archive["sha256"]) or not isinstance(archive["size"], int) or archive["size"] <= 0:
        raise ValueError("Invalid locked archive identity")
    source, signer = lock["source"], lock["signer"]
    if set(source) != {"commit", "ref"} or not HEX40.fullmatch(source["commit"] or "") or source["ref"] != "refs/heads/main":
        raise ValueError("Invalid locked source identity")
    if set(signer) != {"repository", "workflow", "source_commit"} or not HEX40.fullmatch(signer["source_commit"] or ""):
        raise ValueError("Invalid signer identity")
    if not HEX64.fullmatch(lock["sbom_sha256"] or "") or not HEX64.fullmatch(lock["input_fingerprint"] or ""):
        raise ValueError("Invalid locked metadata digest")
    return lock


def check_archive(path, lock=None):
    path = Path(path)
    if lock:
        if path.stat().st_size != lock["archive"]["size"] or digest(path.read_bytes()) != lock["archive"]["sha256"]:
            raise ValueError("Locked archive content hash or size mismatch")
    contents = archive_contents(path)
    if lock and json.loads(contents["dependency.json"])["input_fingerprint"] != lock["input_fingerprint"]:
        raise ValueError("Locked input fingerprint mismatch")
    return contents


def verify_attestations(path, lock):
    signer = lock["signer"]
    identity = f"{signer['repository']}/{signer['workflow']}"
    subprocess.run(["gh", "attestation", "verify", str(path), "--repo", REPOSITORY,
                    "--signer-repo", signer["repository"], "--signer-workflow", identity,
                    "--signer-digest", signer["source_commit"],
                    "--source-ref", lock["source"]["ref"], "--source-digest", lock["source"]["commit"],
                    "--deny-self-hosted-runners", "--predicate-type", "https://slsa.dev/provenance/v1"], check=True)


def download(lock, destination, asset=ARTIFACT):
    url = f"https://github.com/{REPOSITORY}/releases/download/{lock['tag']}/{asset}"
    with urllib.request.urlopen(url, timeout=120) as response, open(destination, "wb") as output:
        shutil.copyfileobj(response, output)


def stage_contents(contents, destination):
    # Keep lexical components so a symlink at the staging root remains visible;
    # resolve() here would follow it before the trust-boundary check.
    destination = Path(destination).absolute()
    planned = {}
    for name, data in contents.items():
        if name.startswith("targets/"):
            target = destination / name
        else:
            target = destination / "linker-inputs" / name
        relative = target.relative_to(destination)
        scoped = [destination]
        cursor = destination
        for component in relative.parts:
            cursor = cursor / component
            scoped.append(cursor)
        if any(part.is_symlink() for part in scoped if part.exists()):
            raise ValueError(f"Refusing symlinked staging destination: {target}")
        planned[target] = data
    for target, data in planned.items():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)


def test_native(archive, target):
    if target not in runtime.TARGETS:
        raise ValueError("Native execution is defined only for Linux targets")
    machine = subprocess.check_output(["uname", "-m"], text=True).strip()
    native = {"x86_64": "x64musl", "aarch64": "arm64musl"}.get(machine)
    if subprocess.check_output(["uname", "-s"], text=True).strip() != "Linux" or native != target:
        raise ValueError(f"{target} must be tested on its native Linux architecture")
    contents = check_archive(archive)
    source = read_json(ROOT / "runtime/source.json")
    toolchain = read_json(ROOT / "runtime/test-toolchains.json")[target]
    with tempfile.TemporaryDirectory(prefix="linker-input-native-") as temporary:
        work = Path(temporary)
        libraries = work / "libraries"
        libraries.mkdir()
        for name in runtime.LIBRARIES:
            (libraries / name).write_bytes(contents[f"targets/{target}/{name}"])
        zig = runtime.install_zig(work, toolchain, source["zig_version"])
        smoke = work / "smoke"
        runtime.link_smoke(zig, libraries, target, smoke, runtime.zig_env(work / "cache"))
        subprocess.run([smoke], check=True)


def fetch_and_check(stage_to=None):
    if not LOCK.exists():
        raise ValueError("No adopted linker-input release; publish v1, review its proposed lock, then add linker-inputs.lock.json")
    lock = validate_lock(read_json(LOCK))
    with tempfile.TemporaryDirectory(prefix="linker-inputs-download-") as temporary:
        archive = Path(temporary) / ARTIFACT
        sbom = Path(temporary) / "linker-inputs.spdx.json"
        download(lock, archive)
        download(lock, sbom, sbom.name)
        contents = check_archive(archive, lock)
        if digest(sbom.read_bytes()) != lock["sbom_sha256"]:
            raise ValueError("Locked SPDX SBOM digest mismatch")
        verify_attestations(archive, lock)
        verify_attestations(sbom, lock)
        if stage_to:
            stage_contents(contents, stage_to)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("check")
    check.add_argument("archive", type=Path, nargs="?")
    stage = commands.add_parser("stage")
    stage.add_argument("archive", type=Path)
    stage.add_argument("--destination", type=Path, default=ROOT / "platform")
    commands.add_parser("fetch")
    build_parser = commands.add_parser("build", help=argparse.SUPPRESS)
    build_parser.add_argument("--output", type=Path, default=ROOT / "dist/linker-inputs")
    native_parser = commands.add_parser("test-native", help=argparse.SUPPRESS)
    native_parser.add_argument("archive", type=Path)
    native_parser.add_argument("--target", choices=runtime.TARGETS, required=True)
    args = parser.parse_args()
    if args.command == "build":
        build(args.output)
    elif args.command == "test-native":
        test_native(args.archive, args.target)
    elif args.command == "fetch":
        fetch_and_check(ROOT / "platform")
    elif args.command == "check":
        if args.archive:
            check_archive(args.archive)
        else:
            fetch_and_check()
    else:
        check_archive(args.archive)
        stage_contents(archive_contents(args.archive), args.destination)


if __name__ == "__main__":
    main()
