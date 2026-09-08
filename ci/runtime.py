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
RUNTIME_FILES = {f"targets/{target}/{name}" for target in TARGETS for name in LIBRARIES}
LICENSE_FILES = {"licenses/musl.txt", "licenses/libunwind.txt", "licenses/zig.txt"}
MEMBERS = RUNTIME_FILES | LICENSE_FILES | {"manifest.json"}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    Path(path).write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


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


def build(output):
    """Zig compiles its vendored C/assembly sources into a fresh cache per target."""
    source = read_json(ROOT / "runtime/source.json")
    output = output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="runtime-build-") as temporary:
        work = Path(temporary)
        archive = work / "zig.tar.xz"
        download(source["url"], archive)
        check_sha(archive, source["sha256"])
        # Only extract the digest-verified official toolchain, using data filtering.
        with tarfile.open(archive) as tar:
            tar.extractall(work, filter="data")
        zig_root = work / f"zig-x86_64-linux-{source['zig_version']}"
        zig = zig_root / "zig"
        actual = subprocess.check_output([zig, "version"], text=True).strip()
        if actual != source["zig_version"]:
            raise ValueError("Downloaded Zig version differs from source pin")
        stage = work / "stage"
        stage.mkdir()
        for target, triple in TARGETS.items():
            cache = work / f"cache-{target}"
            env = os.environ.copy()
            # Do not let developer or runner cache/lib overrides supply runtime files.
            for key in list(env):
                if key.startswith("ZIG_"):
                    del env[key]
            env.update(ZIG_GLOBAL_CACHE_DIR=str(cache), ZIG_LOCAL_CACHE_DIR=str(cache / "local"))
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
            # Link the smoke test with exactly the selected runtime, without Zig's
            # implicit libc, crt or unwind libraries. Run it on each native CI host.
            obj = work / f"smoke-{target}.o"
            command([zig, "cc", "-target", triple, "-mcpu=baseline", "-O2", "-funwind-tables",
                     "-c", ROOT / "runtime/smoke.c", "-o", obj], env=env)
            libs = stage / "targets" / target
            command([zig, "cc", "-target", triple, "-static", "-nostdlib", libs / "crt1.o",
                     obj, libs / "libunwind.a", libs / "libc.a", libs / "libzigc.a",
                     libs / "libcompiler_rt.a", "-o", output / f"smoke-{target}"], env=env)
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
        sbom(output, manifest)
        sha = digest((output / ARTIFACT).read_bytes())
        (output / "SHA256SUMS").write_text(f"{sha}  {ARTIFACT}\n")
        write_json(output / "runtime-lock.proposed.json", {
            "repository": REPOSITORY, "tag": os.environ.get("RUNTIME_TAG"), "sha256": sha,
            "source_commit": os.environ.get("GITHUB_SHA")})
        print(f"Built {output / ARTIFACT}: {sha}")


def sbom(output, manifest):
    """An explicit SPDX inventory; no guessed upstream versions from stripped archives."""
    source = manifest["source"]
    archive_sha = digest((output / ARTIFACT).read_bytes())
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
    write_json(output / "runtime.spdx.json", {
        "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT",
        "name": "Roc Linux runtime", "documentNamespace": f"https://github.com/{REPOSITORY}/runtime/{archive_sha}",
        "creationInfo": {"creators": ["Tool: roc-runtime-builder"], "created": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
        "packages": packages, "files": files, "relationships": relationships})


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
        if any(p.is_symlink() for p in [dest, *dest.parents]):
            raise ValueError(f"Symlink in runtime destination: {dest}")
        destinations[dest] = data
    for dest, data in destinations.items():
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)


def fetch():
    lock = read_json(ROOT / "runtime/lock.json")
    if not isinstance(lock.get("tag"), str) or not re.fullmatch(r"runtime-v[0-9]+\.[0-9]+\.[0-9]+", lock["tag"]):
        raise ValueError("Runtime release is not bootstrapped. Publish runtime-release.yml, review its proposed lock, then commit runtime/lock.json. See runtime/README.md.")
    if lock.get("repository") != REPOSITORY or not re.fullmatch(r"[0-9a-f]{40}", lock.get("source_commit") or ""):
        raise ValueError("Runtime lock must pin the trusted repository and source commit")
    with tempfile.TemporaryDirectory(prefix="runtime-download-") as temp:
        archive = Path(temp) / ARTIFACT
        download(f"https://github.com/{REPOSITORY}/releases/download/{lock['tag']}/{ARTIFACT}", archive)
        check_sha(archive, lock["sha256"])
        for predicate in ("https://slsa.dev/provenance/v1", "https://spdx.dev/Document"):
            command(["gh", "attestation", "verify", archive, "--repo", REPOSITORY,
                     "--signer-workflow", f"{REPOSITORY}/{WORKFLOW}", "--source-ref", "refs/heads/main",
                     "--source-digest", lock["source_commit"], "--deny-self-hosted-runners",
                     "--predicate-type", predicate])
        install(archive)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build_parser = commands.add_parser("build")
    build_parser.add_argument("--output", type=Path, default=ROOT / "dist/runtime")
    commands.add_parser("fetch")
    for name in ("inspect", "install-candidate"):
        p = commands.add_parser(name)
        p.add_argument("archive", type=Path)
    args = parser.parse_args()
    if args.command == "build":
        build(args.output)
    elif args.command == "fetch":
        fetch()
    elif args.command == "inspect":
        inspect(args.archive)
    else:
        install(args.archive)


if __name__ == "__main__":
    main()
