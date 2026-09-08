#!/usr/bin/env python3
"""Read and verify the selected header pins for compiler installation."""
import json
from pathlib import Path
from compiler_pins import discover, local_sources, version

root = Path(__file__).resolve().parent.parent
config = json.loads((root / ".github/roc-nightly.json").read_text())
if (root / ".roc-version").exists():
    raise SystemExit("Remove the competing .roc-version pin")
print(version(discover(local_sources(root, config["compiler_roots"]))))
