"""Independent SPDX test oracle retained across the Roc producer migration."""
import datetime

ARTIFACT = "linux-runtime.tar.gz"
REPOSITORY = "lukewilliamboswell/roc-platform-template-rust"
RUNTIME_FILES = {f"targets/{target}/{name}" for target in ("x64musl", "arm64musl")
                 for name in ("crt1.o", "libc.a", "libunwind.a", "libzigc.a", "libcompiler_rt.a")}

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
