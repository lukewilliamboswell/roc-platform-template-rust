#!/usr/bin/env python3
"""Validate and natively exercise an unprivileged linker-input candidate."""
import argparse
import datetime
import json
import platform
from pathlib import Path
import tempfile

import runtime

def check_candidate(directory):
    lock = runtime.read_json(directory / 'runtime-lock.proposed.json')
    runtime.check_sha(directory / runtime.ARTIFACT, lock['sha256'])
    contents = runtime.inspect(directory / runtime.ARTIFACT)
    manifest = json.loads(contents['manifest.json'])
    if manifest.get('source') != runtime.read_json(runtime.ROOT / 'runtime/source.json'):
        raise ValueError('Archive source metadata differs from the reviewed source pin')
    sbom = runtime.read_json(directory / 'runtime.spdx.json')
    created = sbom.get('creationInfo', {}).get('created')
    if not isinstance(created, str):
        raise ValueError('SBOM creation time is missing')
    datetime.datetime.strptime(created, '%Y-%m-%dT%H:%M:%SZ')
    expected = runtime.sbom_document(manifest, lock['sha256'], created=created)
    if sbom != expected:
        raise ValueError('SBOM differs from the verified archive inventory or reviewed source metadata')
    if (directory / 'SHA256SUMS').read_text() != f"{lock['sha256']}  {runtime.ARTIFACT}\n":
        raise ValueError('Published checksum file differs from the verified archive')
    return lock


def test_candidate(directory, target):
    check_candidate(directory)
    native = {'x86_64': 'x64musl', 'aarch64': 'arm64musl'}.get(platform.machine())
    if platform.system() != 'Linux' or target != native:
        raise ValueError('The archive smoke test must run on its native Linux architecture')
    source = runtime.read_json(runtime.ROOT / 'runtime/source.json')
    toolchain = runtime.read_json(runtime.ROOT / 'runtime/test-toolchains.json')[target]
    with tempfile.TemporaryDirectory(prefix='runtime-native-test-') as temporary:
        work = Path(temporary)
        contents = runtime.inspect(directory / runtime.ARTIFACT)
        libraries = work / 'libraries'
        libraries.mkdir()
        for name in runtime.LIBRARIES:
            (libraries / name).write_bytes(contents[f'targets/{target}/{name}'])
        zig = runtime.install_zig(work, toolchain, source['zig_version'])
        smoke = work / 'smoke'
        runtime.link_smoke(zig, libraries, target, smoke, runtime.zig_env(work / 'cache'))
        runtime.command([smoke])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['test'])
    parser.add_argument('--directory', type=Path, default=Path('dist/runtime'))
    parser.add_argument('--target', choices=runtime.TARGETS)
    args = parser.parse_args()
    if not args.target:
        parser.error('test requires --target')
    test_candidate(args.directory, args.target)


if __name__ == '__main__':
    main()
