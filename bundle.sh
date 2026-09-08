#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$root_dir/platform"

# Refuse partial bundles; build.sh supplies verified runtime release contents.
for target in x64musl arm64musl; do
    for file in crt1.o libc.a libunwind.a libzigc.a libcompiler_rt.a libhost.a; do
        test -f "targets/$target/$file" || { echo "Missing targets/$target/$file; run ./build.sh --all" >&2; exit 1; }
    done
done
for target in x64mac arm64mac; do
    test -f "targets/$target/libhost.a" || { echo "Missing targets/$target/libhost.a" >&2; exit 1; }
done
test -f runtime/manifest.json || { echo "Missing runtime provenance metadata; run ./build.sh --all" >&2; exit 1; }
metadata=()
while IFS= read -r file; do metadata+=("$file"); done < <(find runtime -type f | sort)

# Collect all .roc files
roc_files=(*.roc)

# Collect all host libraries and runtime files from targets directories
lib_files=()
for lib in targets/*/*.a targets/*/*.o; do
    if [[ -f "$lib" ]]; then
        lib_files+=("$lib")
    fi
done

echo "Bundling ${#roc_files[@]} .roc files and ${#lib_files[@]} library files..."
echo ""
echo "Files to bundle:"
for f in "${roc_files[@]}"; do
    echo "  $f"
done
for f in "${lib_files[@]}"; do
    echo "  $f"
done
echo ""

roc bundle "${roc_files[@]}" "${lib_files[@]}" "${metadata[@]}" --output-dir "$root_dir" "$@"
