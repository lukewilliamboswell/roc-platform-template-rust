#!/usr/bin/env python3
"""Build, inspect, and consume the independently released Linux runtime.

Normal installation requires a reviewed digest and both GitHub attestations.
install-candidate is explicitly for testing an unpublished local build.
"""
import argparse
import datetime
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
TARGETS = {"x64musl": "x86_64-linux-musl", "arm64musl": "aarch64-linux-musl"}
LIBRARIES = ("crt1.o", "libc.a", "libunwind.a", "libzigc.a", "libcompiler_rt.a")
ARTIFACT = "linux-runtime.tar.gz"
WORKFLOW = ".github/workflows/runtime-release.yml"
REPOSITORY = "lukewilliamboswell/roc-platform-template-rust"
LOCK = ROOT / "runtime/link-inputs.lock.json"
LEGACY_LOCK = ROOT / "runtime/lock.json"
RELEASE_MANIFEST = "build-input-release.json"
PRODUCER_INPUTS = (
    "ci/runtime.py", "ci/runtime_release.py", "runtime/source.json",
    "runtime/smoke.c", "runtime/test-toolchains.json", WORKFLOW,
)
RUNTIME_FILES = {f"targets/{target}/{name}" for target in TARGETS for name in LIBRARIES}
LICENSE_FILES = {"licenses/musl.txt", "licenses/libunwind.txt", "licenses/zig.txt"}
MEMBERS = RUNTIME_FILES | LICENSE_FILES | {"manifest.json"}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def canonical_json(path, value):
    Path(path).write_bytes(json.dumps(value, sort_keys=True, separators=(",", ":")).encode() + b"\n")


def download(url, destination):
    if not url.startswith("https://"):
        raise ValueError("Downloads must use HTTPS")
    with urllib.request.urlopen(url, timeout=120) as response, open(destination, "wb") as output:
        shutil.copyfileobj(response, output)


def check_sha(path, expected):
    if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("A reviewed SHA-256 digest is required")
    if digest(Path(path).read_bytes()) != expected:
        raise ValueError(f"SHA-256 mismatch: {path}")


def command(args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def install_zig(work, toolchain, version):
    archive = work / "zig.tar.xz"
    download(toolchain["url"], archive)
    check_sha(archive, toolchain["sha256"])
    with tarfile.open(archive) as tar:
        tar.extractall(work, filter="data")
    zig = work / toolchain["directory"] / "zig"
    actual = subprocess.check_output([zig, "version"], text=True).strip()
    if actual != version:
        raise ValueError("Downloaded Zig version differs from source pin")
    return zig


def zig_env(cache):
    env = {key: value for key, value in os.environ.items() if not key.startswith("ZIG_")}
    env.update(ZIG_GLOBAL_CACHE_DIR=str(cache), ZIG_LOCAL_CACHE_DIR=str(cache / "local"))
    return env


def link_smoke(zig, libraries, target, output, env):
    """Link only the supplied runtime files, never implicit Zig runtime libraries."""
    triple = TARGETS[target]
    obj = output.with_suffix(".o")
    command([zig, "cc", "-target", triple, "-mcpu=baseline", "-O2", "-funwind-tables",
             "-c", ROOT / "runtime/smoke.c", "-o", obj], env=env)
    command([zig, "cc", "-target", triple, "-static", "-nostdlib", libraries / "crt1.o",
             obj, libraries / "libunwind.a", libraries / "libc.a", libraries / "libzigc.a",
             libraries / "libcompiler_rt.a", "-o", output], env=env)


def build(output):
    """Zig compiles its vendored C/assembly sources into a fresh cache per target."""
    source = read_json(ROOT / "runtime/source.json")
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    # Zig incorporates build paths into cache keys and some generated archives.
    # A stable, repository-scoped root makes independent invocations identical.
    # Refuse an existing path instead of deleting a possibly user-controlled tree.
    work = ROOT / ".runtime-build-work"
    if work.exists() or work.is_symlink():
        raise ValueError(f"Runtime build workspace already exists: {work}")
    work.mkdir()
    try:
        zig = install_zig(work, source | {"directory": f"zig-x86_64-linux-{source['zig_version']}"}, source["zig_version"])
        zig_root = zig.parent
        stage = work / "stage"
        stage.mkdir()
        for target, triple in TARGETS.items():
            cache = work / f"cache-{target}"
            env = zig_env(cache)
            log = output / f"build-{target}.log"
            with log.open("w") as handle:
                command([zig, "cc", "-target", triple, "-mcpu=baseline", "-static", "-O2",
                         "-funwind-tables", "-lunwind", "-v", ROOT / "runtime/smoke.c",
                         "-o", work / f"smoke-{target}"], env=env, stdout=handle, stderr=subprocess.STDOUT)
            # The cache contains intermediate crt1.o files as well. Select exactly
            # the files from Zig's final linker command, never the first glob match.
            links = [shlex.split(line) for line in log.read_text().splitlines()
                     if line.startswith("ld.lld ") and f"-o {work / f'smoke-{target}'} " in line]
            if len(links) != 1:
                raise ValueError(f"Expected one final linker command; inspect {log}")
            for name in LIBRARIES:
                matches = [Path(item) for item in links[0] if Path(item).name == name]
                if len(matches) != 1 or not matches[0].resolve().is_relative_to(cache.resolve()):
                    raise ValueError(f"Ambiguous or external runtime input: {name}")
                dest = stage / "targets" / target / name
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(matches[0], dest)
        licenses = stage / "licenses"
        licenses.mkdir()
        for dest, src in {"musl.txt": "lib/libc/musl/COPYRIGHT",
                          "libunwind.txt": "lib/libunwind/LICENSE.TXT", "zig.txt": "LICENSE"}.items():
            shutil.copyfile(zig_root / src, licenses / dest)
        manifest = {"schema_version": 1, "source": source, "targets": TARGETS,
                    "files": {name: digest((stage / name).read_bytes()) for name in sorted(RUNTIME_FILES | LICENSE_FILES)}}
        write_json(stage / "manifest.json", manifest)
        # Stable archive metadata; reproducibility of compiler output is tested
        # separately and is not implied merely by normalizing tar headers.
        with (output / ARTIFACT).open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT) as tar:
                for name in sorted(MEMBERS):
                    data = (stage / name).read_bytes()
                    info = tarfile.TarInfo(name)
                    info.size = len(data)
                    info.mode = 0o644
                    tar.addfile(info, io.BytesIO(data))
        inspect(output / ARTIFACT)
        write_json(output / "runtime.spdx.json", sbom_document(manifest, digest((output / ARTIFACT).read_bytes())))
        sha = digest((output / ARTIFACT).read_bytes())
        (output / "SHA256SUMS").write_text(f"{sha}  {ARTIFACT}\n")
        write_json(output / "runtime-lock.proposed.json", {
            "repository": REPOSITORY, "tag": os.environ.get("RUNTIME_TAG"), "sha256": sha,
            "source_commit": os.environ.get("GITHUB_SHA")})
        print(f"Built {output / ARTIFACT}: {sha}")
    finally:
        shutil.rmtree(work)


def input_fingerprint():
    """Hash committed producer inputs; release candidates must identify reviewed bytes."""
    lines = []
    for name in PRODUCER_INPUTS:
        blob = subprocess.check_output(["git", "rev-parse", f"HEAD:{name}"], text=True).strip()
        if not re.fullmatch(r"[0-9a-f]{40}", blob):
            raise ValueError(f"Producer input is not committed: {name}")
        lines.append(f"{name}\0{blob}\n")
    return digest("".join(lines).encode())


def prepare_release(directory):
    """Convert the tested combined candidate into target-scoped deterministic tar files."""
    directory = Path(directory)
    contents = inspect(directory / ARTIFACT)
    assets = {}
    for target in TARGETS:
        asset = f"link-inputs-{target}.tar"
        path = directory / asset
        names = sorted(
            {name for name in contents if name.startswith(f"targets/{target}/")}
            | LICENSE_FILES | {"manifest.json"}
        )
        with tarfile.open(path, "w", format=tarfile.USTAR_FORMAT) as tar:
            for name in names:
                data = contents[name]
                info = tarfile.TarInfo(name)
                info.size = len(data)
                info.mode = 0o644
                info.mtime = 0
                tar.addfile(info, io.BytesIO(data))
        assets[target] = {"asset": asset, "sha256": digest(path.read_bytes()), "size": path.stat().st_size}
    source_sha = os.environ.get("GITHUB_SHA", "")
    source_ref = os.environ.get("GITHUB_REF", "")
    manifest = {
        "schema_version": 1,
        "kind": "link-inputs",
        "source": {
            "repository": REPOSITORY,
            "sha": source_sha,
            "ref": source_ref,
            "workflow": f"{REPOSITORY}/{WORKFLOW}",
            "input_fingerprint": input_fingerprint(),
        },
        "assets": assets,
    }
    if not re.fullmatch(r"[0-9a-f]{40}", source_sha) or not source_ref.startswith("refs/heads/"):
        raise ValueError("Release preparation requires an exact GitHub branch commit")
    canonical_json(directory / RELEASE_MANIFEST, manifest)


def inspect_target_archive(archive, target):
    expected = {f"targets/{target}/{name}" for name in LIBRARIES} | LICENSE_FILES | {"manifest.json"}
    contents = {}
    with tarfile.open(archive, "r:") as tar:
        for member in tar:
            if member.name not in expected or member.name in contents or not member.isfile() or member.size > 64 * 1024 * 1024:
                raise ValueError(f"Unexpected linker-input archive member: {member.name}")
            contents[member.name] = tar.extractfile(member).read()
    if set(contents) != expected:
        raise ValueError("Linker-input archive is incomplete")
    manifest = json.loads(contents["manifest.json"])
    for name in expected - {"manifest.json"}:
        if digest(contents[name]) != manifest.get("files", {}).get(name):
            raise ValueError(f"Linker-input member digest mismatch: {name}")
    return contents


def install_target_archive(archive, target):
    contents = inspect_target_archive(archive, target)
    for name, data in contents.items():
        dest = ROOT / "platform" / (name if name.startswith("targets/") else "runtime/" + name)
        if any(path.is_symlink() for path in [dest, *dest.parents]):
            raise ValueError(f"Symlink in linker-input destination: {dest}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)


def sbom_document(manifest, archive_sha, created=None):
    """An explicit SPDX inventory; no guessed upstream versions from stripped archives."""
    source = manifest["source"]
    packages = []
    for name, license_id in [("musl", "MIT"), ("libunwind", "Apache-2.0 WITH LLVM-exception"), ("zig-runtime", "MIT")]:
        packages.append({"name": name, "SPDXID": f"SPDXRef-{name}",
                         "versionInfo": f"vendored-in-zig-{source['zig_version']}",
                         "downloadLocation": source["source_url"], "filesAnalyzed": False,
                         "licenseDeclared": license_id, "copyrightText": "NOASSERTION",
                         "comment": "Version identifies Zig's vendored revision, not an upstream release. See source archive checksum and included license."})
    packages.append({"name": "zig", "SPDXID": "SPDXRef-zig", "versionInfo": source["zig_version"],
                     "downloadLocation": source["url"], "filesAnalyzed": False,
                     "checksums": [{"algorithm": "SHA256", "checksumValue": source["sha256"]}],
                     "licenseDeclared": "NOASSERTION", "copyrightText": "NOASSERTION"})
    packages.append({"name": "zig-vendored-sources", "SPDXID": "SPDXRef-sources", "versionInfo": source["zig_version"],
                     "downloadLocation": source["source_url"], "filesAnalyzed": False,
                     "checksums": [{"algorithm": "SHA256", "checksumValue": source["source_sha256"]}],
                     "licenseDeclared": "NOASSERTION", "copyrightText": "NOASSERTION"})
    packages.append({"name": ARTIFACT, "SPDXID": "SPDXRef-runtime", "downloadLocation": "NOASSERTION",
                     "filesAnalyzed": False, "licenseDeclared": "NOASSERTION", "copyrightText": "NOASSERTION",
                     "checksums": [{"algorithm": "SHA256", "checksumValue": archive_sha}]})
    files, relationships = [], [{"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES", "relatedSpdxElement": "SPDXRef-runtime"}]
    for name in sorted(RUNTIME_FILES):
        file_id = "SPDXRef-file-" + name.replace("/", "-").replace(".", "-")
        component = ("zig-runtime" if name.endswith(("libzigc.a", "libcompiler_rt.a"))
                     else "libunwind" if name.endswith("libunwind.a") else "musl")
        files.append({"fileName": name, "SPDXID": file_id,
                      "checksums": [{"algorithm": "SHA256", "checksumValue": manifest["files"][name]}],
                      "licenseConcluded": "NOASSERTION", "copyrightText": "NOASSERTION"})
        relationships.extend([
            {"spdxElementId": "SPDXRef-runtime", "relationshipType": "CONTAINS", "relatedSpdxElement": file_id},
            {"spdxElementId": file_id, "relationshipType": "GENERATED_FROM", "relatedSpdxElement": f"SPDXRef-{component}"}])
    relationships.append({"spdxElementId": "SPDXRef-zig", "relationshipType": "BUILD_TOOL_OF", "relatedSpdxElement": "SPDXRef-runtime"})
    for component in ("musl", "libunwind", "zig-runtime"):
        relationships.append({"spdxElementId": f"SPDXRef-{component}", "relationshipType": "DESCENDANT_OF", "relatedSpdxElement": "SPDXRef-sources"})
    return {
        "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT",
        "name": "Roc Linux runtime", "documentNamespace": f"https://github.com/{REPOSITORY}/runtime/{archive_sha}",
        "creationInfo": {"creators": ["Tool: roc-runtime-builder"], "created": created or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
        "packages": packages, "files": files, "relationships": relationships}


def inspect(archive):
    """Never use extractall on runtime releases: accept only a fixed set of files."""
    contents = {}
    with tarfile.open(archive, "r:gz") as tar:
        for member in tar:
            if member.name not in MEMBERS or member.name in contents or not member.isfile() or member.size > 64 * 1024 * 1024:
                raise ValueError(f"Unexpected runtime archive member: {member.name}")
            contents[member.name] = tar.extractfile(member).read()
    if set(contents) != MEMBERS:
        raise ValueError("Runtime archive is incomplete")
    manifest = json.loads(contents["manifest.json"])
    if manifest.get("schema_version") != 1 or manifest.get("targets") != TARGETS:
        raise ValueError("Unsupported runtime manifest")
    if set(manifest.get("files", {})) != RUNTIME_FILES | LICENSE_FILES:
        raise ValueError("Manifest file list differs from runtime contract")
    for name, expected in manifest["files"].items():
        if digest(contents[name]) != expected:
            raise ValueError(f"Runtime member digest mismatch: {name}")
    return contents


def install(archive):
    contents = inspect(archive)
    # Validate the entire archive before modifying any destination. Do not write
    # through repository symlinks, including symlinked parent directories.
    destinations = {}
    for name, data in contents.items():
        dest = ROOT / "platform" / (name if name.startswith("targets/") else "runtime/" + name)
        platform_root = ROOT / "platform"
        scoped = [platform_root]
        cursor = platform_root
        for component in dest.relative_to(platform_root).parts:
            cursor = cursor / component
            scoped.append(cursor)
        if any(p.is_symlink() for p in scoped if p.exists()):
            raise ValueError(f"Symlink in runtime destination: {dest}")
        destinations[dest] = data
    for dest, data in destinations.items():
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)


def verify_attestations(archive, source_commit):
    for predicate in ("https://slsa.dev/provenance/v1", "https://spdx.dev/Document"):
        command(["gh", "attestation", "verify", archive, "--repo", REPOSITORY,
                 "--signer-workflow", f"{REPOSITORY}/{WORKFLOW}", "--source-ref", "refs/heads/main",
                 "--source-digest", source_commit, "--deny-self-hosted-runners",
                 "--predicate-type", predicate])


def fetch_legacy():
    lock = read_json(LEGACY_LOCK)
    if not isinstance(lock.get("tag"), str) or not re.fullmatch(r"runtime-v[0-9]+\.[0-9]+\.[0-9]+", lock["tag"]):
        raise ValueError("Runtime release is not bootstrapped. Publish runtime-release.yml, review its proposed lock, then commit runtime/lock.json. See runtime/README.md.")
    if lock.get("repository") != REPOSITORY or not re.fullmatch(r"[0-9a-f]{40}", lock.get("source_commit") or ""):
        raise ValueError("Runtime lock must pin the trusted repository and source commit")
    with tempfile.TemporaryDirectory(prefix="runtime-download-") as temp:
        archive = Path(temp) / ARTIFACT
        download(f"https://github.com/{REPOSITORY}/releases/download/{lock['tag']}/{ARTIFACT}", archive)
        check_sha(archive, lock["sha256"])
        verify_attestations(archive, lock["source_commit"])
        install(archive)


def fetch_locked(targets):
    """Use the reviewed content lock; the cache saves traffic but never supplies trust."""
    lock = read_json(LOCK)
    if (not isinstance(lock, dict)
            or set(lock) != {"schema_version", "kind", "repository", "release", "manifest", "source", "targets"}
            or lock.get("schema_version") != 1 or lock.get("kind") != "link-inputs"
            or lock.get("repository") != REPOSITORY
            or not re.fullmatch(r"linker-inputs-sha256-[0-9a-f]{64}", lock.get("release", ""))
            or set(lock.get("targets", {})) != set(TARGETS)):
        raise ValueError("Unsupported linker-input lock")
    manifest = lock.get("manifest")
    if (not isinstance(manifest, dict) or set(manifest) != {"asset", "sha256"}
            or manifest.get("asset") != RELEASE_MANIFEST
            or not re.fullmatch(r"[0-9a-f]{64}", manifest.get("sha256", ""))):
        raise ValueError("Invalid linker-input manifest identity")
    source = lock.get("source")
    if (not isinstance(source, dict)
            or set(source) != {"repository", "sha", "ref", "workflow", "input_fingerprint"}
            or source.get("repository") != REPOSITORY
            or not re.fullmatch(r"[0-9a-f]{40}", source.get("sha", ""))
            or not re.fullmatch(r"refs/heads/[A-Za-z0-9._/-]+", source.get("ref", ""))
            or source.get("workflow") != f"{REPOSITORY}/{WORKFLOW}"):
        raise ValueError("Invalid linker-input producer identity")
    fingerprint = input_fingerprint()
    if source.get("input_fingerprint") != fingerprint:
        raise ValueError("Linker-input producer inputs changed; publish and adopt a new content lock")
    cache = Path(os.environ.get("ROC_LINK_INPUT_CACHE", Path.home() / ".cache/roc-platform-template-rust/link-inputs"))
    cache.mkdir(parents=True, exist_ok=True)
    for target in targets:
        record = lock["targets"][target]
        if (not isinstance(record, dict) or set(record) != {"asset", "sha256", "size"}
                or not isinstance(record.get("size"), int) or isinstance(record.get("size"), bool)
                or record["size"] <= 0
                or not re.fullmatch(r"[0-9a-f]{64}", record.get("sha256", ""))
                or not re.fullmatch(r"[A-Za-z0-9._-]+\.tar", record.get("asset", ""))):
            raise ValueError(f"Invalid linker-input lock record: {target}")
        archive = cache / record["sha256"]
        valid = archive.is_file() and archive.stat().st_size == record["size"] and digest(archive.read_bytes()) == record["sha256"]
        if not valid:
            if archive.exists():
                archive.unlink()
            download(f"https://github.com/{REPOSITORY}/releases/download/{lock['release']}/{record['asset']}", archive)
        if archive.stat().st_size != record["size"] or digest(archive.read_bytes()) != record["sha256"]:
            archive.unlink(missing_ok=True)
            raise ValueError(f"Downloaded linker-input archive differs from lock: {target}")
        install_target_archive(archive, target)


def fetch(targets=None):
    targets = targets or list(TARGETS)
    if LOCK.exists():
        fetch_locked(targets)
    else:
        # Bootstrap only: remove this branch after the publisher adds the first
        # signed content lock. It consumes the existing release; it never builds.
        fetch_legacy()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("--output", type=Path, default=ROOT / "dist/runtime")
    fetch_parser = commands.add_parser("fetch")
    fetch_parser.add_argument("--target", action="append", choices=TARGETS)
    commands.add_parser("prepare-release")
    for name in ("inspect", "install-candidate"):
        p = commands.add_parser(name)
        p.add_argument("archive", type=Path)
    args = parser.parse_args()
    if args.command == "build":
        build(args.output)
    elif args.command == "fetch":
        fetch(args.target or list(TARGETS))
    elif args.command == "prepare-release":
        prepare_release(ROOT / "dist/runtime")
    elif args.command == "inspect":
        inspect(args.archive)
    else:
        install(args.archive)


if __name__ == "__main__":
    main()
