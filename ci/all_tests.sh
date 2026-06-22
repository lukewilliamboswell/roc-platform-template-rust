#!/usr/bin/env bash
set -euo pipefail

HTTP_SERVER_PID=""
TEMP_DIRS=()
GENERATED_BUNDLE_PATH=""
STARTED_PACKAGE_URL=""

cleanup() {
  if [ -n "$HTTP_SERVER_PID" ]; then
    kill "$HTTP_SERVER_PID" 2>/dev/null || true
  fi
  if [ -n "$GENERATED_BUNDLE_PATH" ]; then
    rm -f "$GENERATED_BUNDLE_PATH"
  fi
  for dir in "${TEMP_DIRS[@]}"; do
    rm -rf "$dir"
  done
}

trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# Get the roc commit pinned in .roc-version
ROC_COMMIT=$(python3 ci/get_roc_commit.py)
ROC_COMMIT_SHORT="${ROC_COMMIT:0:8}"

echo "=== Roc Platform Template (Rust) CI ==="
echo ""

# Check if roc is already on PATH and matches pinned commit
NEED_BUILD=true
if command -v roc &>/dev/null; then
  SYSTEM_VERSION=$(roc version 2>/dev/null || echo "unknown")
  if echo "$SYSTEM_VERSION" | grep -q "$ROC_COMMIT_SHORT"; then
    echo "roc on PATH matches pinned commit: $SYSTEM_VERSION"
    NEED_BUILD=false
  else
    echo "roc on PATH ($SYSTEM_VERSION) doesn't match pinned commit ($ROC_COMMIT_SHORT)"
  fi
fi

# Check cached build in roc-src/
if [ "$NEED_BUILD" = true ] && [ -d "roc-src" ] && [ -f "roc-src/zig-out/bin/roc" ]; then
  CACHED_VERSION=$(./roc-src/zig-out/bin/roc version 2>/dev/null || echo "unknown")
  if echo "$CACHED_VERSION" | grep -q "$ROC_COMMIT_SHORT"; then
    echo "roc in roc-src/ matches pinned commit: $CACHED_VERSION"
    NEED_BUILD=false
  else
    echo "Cached roc ($CACHED_VERSION) doesn't match pinned commit ($ROC_COMMIT_SHORT)"
    echo "Removing stale roc-src..."
    rm -rf roc-src
  fi
fi

# Build from source if no matching roc found
if [ "$NEED_BUILD" = true ]; then
  echo "Building roc from pinned commit $ROC_COMMIT..."

  rm -rf roc-src
  git init roc-src
  cd roc-src
  git remote add origin https://github.com/roc-lang/roc
  git fetch --depth 1 origin "$ROC_COMMIT"
  git checkout --detach "$ROC_COMMIT"

  # Retry zig build up to 3 times (Zig package fetches can be flaky in CI)
  for attempt in 1 2 3; do
    echo "zig build roc (attempt $attempt)..."
    if zig build roc; then
      break
    fi
    if [ $attempt -eq 3 ]; then
      echo "zig build roc failed after 3 attempts"
      exit 1
    fi
    echo "Retrying in 10 seconds..."
    sleep 10
  done

  # Add to GITHUB_PATH if running in CI
  if [ -n "${GITHUB_PATH:-}" ]; then
    echo "$(pwd)/zig-out/bin" >> "$GITHUB_PATH"
  fi

  cd ..
fi

# Ensure roc-src build is in PATH (harmless if dir doesn't exist)
export PATH="$(pwd)/roc-src/zig-out/bin:$PATH"

echo ""
echo "Using roc version: $(roc version)"

FAILED=0

run_examples() {
  local examples_dir=$1
  local label=$2

  echo ""
  echo "=== Running examples ($label) ==="

  for ROC_FILE in "$examples_dir"/*.roc; do
    local BASENAME
    BASENAME=$(basename "$ROC_FILE" .roc)
    echo ""
    echo "--- Testing: $BASENAME ---"

    # Run with --no-cache to ensure fresh builds
    set +e
    case "$BASENAME" in
      "echo")
        OUTPUT=$(printf 'bundled input\n' | roc --no-cache "$ROC_FILE" 2>&1)
        EXIT_CODE=$?
        if [[ $EXIT_CODE -eq 0 && "$OUTPUT" == *"You entered: bundled input"* ]]; then
          echo "PASS: echo.roc"
          echo "$OUTPUT"
        else
          echo "FAIL: echo.roc (exit code: $EXIT_CODE)"
          echo "$OUTPUT"
          FAILED=1
        fi
        ;;
      "echo_multiline")
        OUTPUT=$(printf 'first line\nsecond line\n' | roc --no-cache "$ROC_FILE" 2>&1)
        EXIT_CODE=$?
        if [[ $EXIT_CODE -eq 0 && "$OUTPUT" == *"first line"* && "$OUTPUT" == *"second line"* ]]; then
          echo "PASS: echo_multiline.roc"
          echo "$OUTPUT"
        else
          echo "FAIL: echo_multiline.roc (exit code: $EXIT_CODE)"
          echo "$OUTPUT"
          FAILED=1
        fi
        ;;
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
}

run_roc_tests() {
  local test_root=$1
  local label=$2

  echo ""
  echo "=== Running roc test ($label) ==="

  while IFS= read -r file; do
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
  done < <(find "$test_root" -type d -name "roc-src" -prune -o -type f -name "*.roc" -print)
}

run_suite() {
  local examples_dir=$1
  local test_root=$2
  local label=$3

  run_examples "$examples_dir" "$label"
  run_roc_tests "$test_root" "$label"
}

detect_native_target() {
  local arch
  local os
  arch=$(uname -m)
  os=$(uname -s)

  if [ "$os" = "Darwin" ]; then
    if [ "$arch" = "arm64" ]; then
      echo "arm64mac"
    else
      echo "x64mac"
    fi
  elif [ "$os" = "Linux" ]; then
    if [ "$arch" = "aarch64" ]; then
      echo "arm64musl"
    else
      echo "x64musl"
    fi
  else
    echo "Unsupported OS: $os" >&2
    return 1
  fi
}

target_inputs_for_roc() {
  case "$1" in
    x64mac|arm64mac)
      echo '"libhost.a", app'
      ;;
    x64musl|arm64musl)
      echo '"crt1.o", "libhost.a", "libunwind.a", app, "libc.a"'
      ;;
    *)
      echo "Unknown target: $1" >&2
      return 1
      ;;
  esac
}

copy_native_target_files() {
  local native_target=$1
  local platform_dir=$2
  local target_dir="$platform_dir/targets/$native_target"

  mkdir -p "$target_dir"

  case "$native_target" in
    x64mac|arm64mac)
      cp "platform/targets/$native_target/libhost.a" "$target_dir/"
      ;;
    x64musl|arm64musl)
      cp "platform/targets/$native_target/crt1.o" "$target_dir/"
      cp "platform/targets/$native_target/libhost.a" "$target_dir/"
      cp "platform/targets/$native_target/libunwind.a" "$target_dir/"
      cp "platform/targets/$native_target/libc.a" "$target_dir/"
      ;;
    *)
      echo "Unknown target: $native_target" >&2
      return 1
      ;;
  esac
}

write_native_target_platform_main() {
  local native_target=$1
  local output_path=$2
  local target_inputs
  target_inputs=$(target_inputs_for_roc "$native_target")

  awk -v target="$native_target" -v inputs="$target_inputs" '
    /^    targets: \{/ {
      print "    targets: {"
      print "        inputs_dir: \"targets/\","
      print "        " target ": { inputs: [" inputs "] },"
      print "    }"
      skip = 1
      next
    }
    skip && /^    }$/ {
      skip = 0
      next
    }
    !skip { print }
  ' platform/main.roc > "$output_path"
}

create_native_bundle() {
  local temp_root=$1
  local native_target
  native_target=$(detect_native_target)

  if [ ! -f "platform/targets/$native_target/libhost.a" ]; then
    echo "Native host archive missing for $native_target; building it first..."
    ./build.sh
  fi

  local platform_dir="$temp_root/platform"
  mkdir -p "$platform_dir"

  cp platform/Stderr.roc "$platform_dir/"
  cp platform/Stdin.roc "$platform_dir/"
  cp platform/Stdout.roc "$platform_dir/"
  write_native_target_platform_main "$native_target" "$platform_dir/main.roc"
  copy_native_target_files "$native_target" "$platform_dir"

  echo "Bundling native target package for $native_target..."
  (
    cd "$platform_dir"
    roc_files=(*.roc)
    lib_files=()
    for lib in targets/*/*.a targets/*/*.o; do
      if [[ -f "$lib" ]]; then
        lib_files+=("$lib")
      fi
    done
    roc bundle "${roc_files[@]}" "${lib_files[@]}" --output-dir "$temp_root"
  )
}

copy_examples_for_package_url() {
  local package_url=$1
  local dest_dir=$2

  mkdir -p "$dest_dir"
  for example in ./examples/*.roc; do
    sed "s|platform \"../platform/main.roc\"|platform \"$package_url\"|g" "$example" > "$dest_dir/$(basename "$example")"
  done
}

start_bundle_server() {
  local bundle_path=$1
  local server_dir=$2
  local bundle_filename
  bundle_filename=$(basename "$bundle_path")

  mkdir -p "$server_dir"
  cp "$bundle_path" "$server_dir/$bundle_filename"

  local http_port
  http_port=${PACKAGE_HTTP_PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')}

  python3 -m http.server "$http_port" --bind 127.0.0.1 --directory "$server_dir" > "$server_dir/http.log" 2>&1 &
  HTTP_SERVER_PID=$!

  local package_url="http://127.0.0.1:$http_port/$bundle_filename"
  for _ in {1..20}; do
    if curl -f -I "$package_url" > /dev/null 2>&1; then
      STARTED_PACKAGE_URL="$package_url"
      return 0
    fi
    sleep 1
  done

  echo "HTTP server did not serve $package_url" >&2
  cat "$server_dir/http.log" >&2 || true
  return 1
}

run_bundle_suite() {
  echo ""
  echo "=== Testing bundled package via URL ==="

  local package_url="${PACKAGE_URL:-}"
  local temp_root
  local temp_parent="${TMPDIR:-/tmp}"
  temp_parent="${temp_parent%/}"
  temp_root=$(mktemp -d "$temp_parent/platform-template-tests.XXXXXX")
  TEMP_DIRS+=("$temp_root")

  if [ -z "$package_url" ]; then
    local bundle_output
    local bundle_status
    set +e
    bundle_output=$(create_native_bundle "$temp_root" 2>&1)
    bundle_status=$?
    set -e
    echo "$bundle_output"

    if [ $bundle_status -ne 0 ]; then
      echo "Error: bundle creation failed"
      FAILED=1
      return
    fi

    local bundle_path
    bundle_path=$(echo "$bundle_output" | grep "^Created:" | awk '{print $2}')

    if [ -z "$bundle_path" ] || [ ! -f "$bundle_path" ]; then
      echo "Error: could not extract bundle path from bundle output"
      FAILED=1
      return
    fi

    GENERATED_BUNDLE_PATH="$bundle_path"
    start_bundle_server "$bundle_path" "$temp_root/http"
    package_url="$STARTED_PACKAGE_URL"
  fi

  echo "Package URL: $package_url"

  local package_examples_dir="$temp_root/examples"
  copy_examples_for_package_url "$package_url" "$package_examples_dir"
  run_suite "$package_examples_dir" "$package_examples_dir" "bundled package"
}

if [ "${RUN_LOCAL_TESTS:-1}" = "1" ]; then
  # Build the platform (skip if SKIP_BUILD is set, used when testing bundled platform)
  if [ "${SKIP_BUILD:-}" != "1" ]; then
    echo ""
    echo "=== Building platform ==="
    ./build.sh
  else
    echo ""
    echo "=== Skipping platform build (SKIP_BUILD=1) ==="
  fi

  run_suite "./examples" "." "local platform"
else
  echo ""
  echo "=== Skipping local platform tests (RUN_LOCAL_TESTS=0) ==="
fi

if [ "${RUN_BUNDLE_TEST:-1}" = "1" ]; then
  run_bundle_suite
else
  echo ""
  echo "=== Skipping bundled package tests (RUN_BUNDLE_TEST=0) ==="
fi

# TODO: Enable when roc docs supports new platform header format
# echo ""
# echo "=== Building docs ==="
# roc docs platform/main.roc

echo ""
if [ $FAILED -eq 0 ]; then
    cleanup
    echo "=== All tests passed! ==="
else
    cleanup
    echo "=== Some tests failed ==="
    exit 1
fi
