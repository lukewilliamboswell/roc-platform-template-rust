#!/usr/bin/env bash
set -euo pipefail

# Get the roc commit pinned in Cargo.toml
ROC_COMMIT=$(python3 ci/get_roc_commit.py)
ROC_COMMIT_SHORT="${ROC_COMMIT:0:8}"
NEED_BUILD=false

echo "=== Roc Platform Template (Rust) CI ==="
echo ""

# Check if roc exists and matches pinned commit
if [ -d "roc-src" ] && [ -f "roc-src/zig-out/bin/roc" ]; then
  CACHED_VERSION=$(./roc-src/zig-out/bin/roc version 2>/dev/null || echo "unknown")
  if echo "$CACHED_VERSION" | grep -q "$ROC_COMMIT_SHORT"; then
    echo "roc already at correct version: $CACHED_VERSION"
  else
    echo "Cached roc ($CACHED_VERSION) doesn't match pinned commit ($ROC_COMMIT_SHORT)"
    echo "Removing stale roc-src..."
    rm -rf roc-src
    NEED_BUILD=true
  fi
else
  NEED_BUILD=true
fi

if [ "$NEED_BUILD" = true ]; then
  echo "Building roc from pinned commit $ROC_COMMIT..."

  rm -rf roc-src
  git init roc-src
  cd roc-src
  git remote add origin https://github.com/roc-lang/roc
  git fetch --depth 1 origin "$ROC_COMMIT"
  git checkout --detach "$ROC_COMMIT"

  zig build roc

  # Add to GITHUB_PATH if running in CI, otherwise add to local PATH
  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$(pwd)/zig-out/bin" >> "$GITHUB_PATH"
  fi

  cd ..
fi

# Ensure roc is in PATH
export PATH="$(pwd)/roc-src/zig-out/bin:$PATH"

echo ""
echo "Using roc version: $(roc version)"

# Build the platform (skip if SKIP_BUILD is set, used when testing bundled platform)
if [ "${SKIP_BUILD:-}" != "1" ]; then
    echo ""
    echo "=== Building platform ==="
    ./build.sh
else
    echo ""
    echo "=== Skipping platform build (SKIP_BUILD=1) ==="
fi

# Run all examples
echo ""
echo "=== Running examples ==="

EXAMPLES_DIR="./examples"
FAILED=0

for ROC_FILE in "$EXAMPLES_DIR"/*.roc; do
    BASENAME=$(basename "$ROC_FILE" .roc)
    echo ""
    echo "--- Testing: $BASENAME ---"

    # Skip interactive examples that require stdin
    if [[ "$BASENAME" == "echo" || "$BASENAME" == "echo_multiline" ]]; then
        echo "Skipping interactive example: $BASENAME"
        continue
    fi

    # Run with --no-cache to ensure fresh builds
    set +e
    case "$BASENAME" in
        "exit")
            # exit.roc should exit with code 23
            roc --no-cache "$ROC_FILE"
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 23 ]; then
                echo "PASS: exit.roc returned expected exit code 23"
            else
                echo "FAIL: exit.roc returned $EXIT_CODE, expected 23"
                FAILED=1
            fi
            ;;
        "dbg_test")
            # dbg_test.roc should exit with code 1 (because dbg was called)
            roc --no-cache "$ROC_FILE"
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 1 ]; then
                echo "PASS: dbg_test.roc returned expected exit code 1"
            else
                echo "FAIL: dbg_test.roc returned $EXIT_CODE, expected 1"
                FAILED=1
            fi
            ;;
        "cli_args")
            # cli_args.roc - just check it runs successfully (args are passed by runtime)
            OUTPUT=$(roc --no-cache "$ROC_FILE" 2>&1)
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                echo "PASS: cli_args.roc"
                echo "$OUTPUT"
            else
                echo "FAIL: cli_args.roc (exit code: $EXIT_CODE)"
                echo "$OUTPUT"
                FAILED=1
            fi
            ;;
        *)
            # Regular examples should exit with 0
            OUTPUT=$(roc --no-cache "$ROC_FILE" 2>&1)
            EXIT_CODE=$?
            if [ $EXIT_CODE -eq 0 ]; then
                echo "PASS: $BASENAME.roc"
                echo "$OUTPUT"
            else
                echo "FAIL: $BASENAME.roc (exit code: $EXIT_CODE)"
                echo "$OUTPUT"
                FAILED=1
            fi
            ;;
    esac
    set -e
done

# Run roc test on files with expects
echo ""
echo "=== Running roc test ==="
find . -type d -name "roc-src" -prune -o -type f -name "*.roc" -print | while read file; do
    if grep -qE '^\s*expect(\s+|$)' "$file"; then
        echo "Testing: $file"
        set +e
        roc test "$file"
        test_exit_code=$?
        set -e

        # Exit codes: 0 = all pass, 2 = some tests skipped, other = failure
        if [[ $test_exit_code -ne 0 && $test_exit_code -ne 2 ]]; then
            echo "FAIL: roc test $file (exit code: $test_exit_code)"
            FAILED=1
        fi
    fi
done

# TODO: Enable when roc docs supports new platform header format
# echo ""
# echo "=== Building docs ==="
# roc docs platform/main.roc

echo ""
if [ $FAILED -eq 0 ]; then
    echo "=== All tests passed! ==="
else
    echo "=== Some tests failed ==="
    exit 1
fi
