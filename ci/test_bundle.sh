#!/usr/bin/env bash
set -euo pipefail

bundle=${1:?Usage: ci/test_bundle.sh <bundle-file>}
test -f "$bundle"
server_dir=$(mktemp -d)
server_pid=
cleanup() {
  if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi
  rm -rf "$server_dir"
}
trap cleanup EXIT
cp "$bundle" "$server_dir/"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$server_dir" > "$server_dir/http.log" 2>&1 < /dev/null &
server_pid=$!
url="http://127.0.0.1:$port/$(basename "$bundle")"
ready=0
for attempt in {1..20}; do
  if curl --noproxy '*' --max-time 2 -fsI "$url" > /dev/null; then ready=1; break; fi
  if ! kill -0 "$server_pid" 2>/dev/null; then break; fi
  sleep 1
done
if [ "$ready" != 1 ]; then cat "$server_dir/http.log" >&2; exit 1; fi
PACKAGE_URL="$url" RUN_LOCAL_TESTS=0 bash ci/all_tests.sh
