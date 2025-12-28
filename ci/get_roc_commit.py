#!/usr/bin/env python3
"""Extract the roc commit hash from Cargo.toml."""

import re
from pathlib import Path


def main() -> None:
    cargo_toml_path = Path(__file__).resolve().parent.parent / "Cargo.toml"
    try:
        contents = cargo_toml_path.read_text()
    except FileNotFoundError:
        raise SystemExit(f"Missing Cargo.toml at {cargo_toml_path}")

    # Match the rev = "..." in the roc_std_new dependency
    match = re.search(r'roc-lang/roc.*rev\s*=\s*"([0-9a-fA-F]{40})"', contents)
    if not match:
        raise SystemExit("Could not find roc commit in Cargo.toml")

    print(match.group(1))


if __name__ == "__main__":
    main()
