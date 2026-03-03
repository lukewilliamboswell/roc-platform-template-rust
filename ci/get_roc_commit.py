#!/usr/bin/env python3
"""Read the roc commit hash from .roc-version."""

from pathlib import Path


def main() -> None:
    version_path = Path(__file__).resolve().parent.parent / ".roc-version"
    try:
        commit = version_path.read_text().strip()
    except FileNotFoundError:
        raise SystemExit(f"Missing .roc-version at {version_path}")

    if not commit:
        raise SystemExit(".roc-version is empty")

    print(commit)


if __name__ == "__main__":
    main()
