#!/usr/bin/env python3
"""Release orchestration; workflow YAML owns scheduling, jobs and permissions."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import runtime

VERSION = r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'


def release_tag(version):
    if not re.fullmatch(VERSION, version):
        raise ValueError('Expected an unprefixed runtime SemVer')
    return 'runtime-v' + version


def publication_context():
    if (os.environ.get('GITHUB_EVENT_NAME') != 'workflow_dispatch'
            or os.environ.get('GITHUB_REF') != 'refs/heads/main'
            or os.environ.get('GITHUB_REPOSITORY') != runtime.REPOSITORY):
        raise ValueError('Runtime publication requires a manual main-branch run in the trusted repository')
    sha = os.environ['GITHUB_SHA']
    if subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() != sha:
        raise ValueError('Release helper checkout differs from the event commit')
    tag = os.environ['RUNTIME_TAG']
    if not tag.startswith('runtime-v') or release_tag(tag[len('runtime-v'):]) != tag:
        raise ValueError('Invalid runtime tag')
    return tag, sha


def request():
    version = os.environ.get('VERSION') or '0.0.0'
    tag = release_tag(version)
    if os.environ.get('PUBLISH') == 'true':
        # Validate the same context before spending time building a release.
        os.environ['RUNTIME_TAG'] = tag
        publication_context()
    with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
        out.write(f'tag={tag}\n')


def check_candidate(directory):
    lock = runtime.read_json(directory / 'runtime-lock.proposed.json')
    runtime.check_sha(directory / runtime.ARTIFACT, lock['sha256'])
    runtime.inspect(directory / runtime.ARTIFACT)
    return lock


def test_candidate(directory, target):
    check_candidate(directory)
    smoke = directory / f'smoke-{target}'
    smoke.chmod(0o755)
    runtime.command([smoke.resolve()])


def preflight(directory):
    tag, sha = publication_context()
    lock = check_candidate(directory)
    if (lock['tag'], lock['source_commit'], lock['repository']) != (tag, sha, runtime.REPOSITORY):
        raise ValueError('Candidate identity differs from the release request')
    refs = json.loads(subprocess.check_output([
        'gh', 'api', f'repos/{runtime.REPOSITORY}/git/matching-refs/tags/{tag}'], text=True))
    if any(ref['ref'] == f'refs/tags/{tag}' for ref in refs):
        raise ValueError('Runtime tag already exists; inspect partial publication before recovery')
    return tag, sha


def publish(directory):
    tag, sha = preflight(directory)
    for variable, name in [('PROVENANCE_BUNDLE', 'provenance.sigstore.json'),
                           ('SBOM_BUNDLE', 'sbom.sigstore.json')]:
        shutil.copyfile(os.environ[variable], directory / name)
    notes = directory / 'release-notes.md'
    notes.write_text(
        f'Independent Linux runtime built from pinned Zig sources.\n\nSource commit: `{sha}`\n\n'
        'Includes musl startup/libc, LLVM libunwind, Zig support libraries, licenses, an SPDX SBOM, '
        'and Sigstore attestation bundles.\n\n'
        'Review runtime-lock.proposed.json before adopting this release in platform builds.\n')
    assets = [runtime.ARTIFACT, 'SHA256SUMS', 'runtime.spdx.json',
              'runtime-lock.proposed.json', 'provenance.sigstore.json', 'sbom.sigstore.json']
    runtime.command(['gh', 'release', 'create', tag, '--repo', runtime.REPOSITORY,
                     '--target', sha, '--title', f'Linux runtime {tag}', '--latest=false',
                     '--notes-file', notes, *[directory / name for name in assets]])


def verify_published(directory):
    tag, sha = publication_context()
    lock = check_candidate(directory)
    with tempfile.TemporaryDirectory(prefix='runtime-published-') as temp:
        runtime.command(['gh', 'release', 'download', tag, '--repo', runtime.REPOSITORY,
                         '--pattern', runtime.ARTIFACT, '--dir', temp])
        archive = Path(temp) / runtime.ARTIFACT
        runtime.check_sha(archive, lock['sha256'])
        runtime.verify_attestations(archive, sha)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['request', 'test', 'preflight', 'publish', 'verify'])
    parser.add_argument('--directory', type=Path, default=Path('dist/runtime'))
    parser.add_argument('--target', choices=runtime.TARGETS)
    args = parser.parse_args()
    if args.command == 'request':
        request()
    elif args.command == 'test':
        if not args.target:
            parser.error('test requires --target')
        test_candidate(args.directory, args.target)
    else:
        {'preflight': preflight, 'publish': publish, 'verify': verify_published}[args.command](args.directory)


if __name__ == '__main__':
    main()
