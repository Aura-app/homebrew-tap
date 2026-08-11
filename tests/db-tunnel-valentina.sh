#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." >/dev/null 2>&1 && pwd)"
HOOK_SCRIPT="$REPO_ROOT/packages/db-tunnel/share/valentina-pre-connect.py"

TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/db-tunnel-valentina-test.XXXXXX")"
FAKE_BIN="$TEST_TEMP_DIR/bin"
CAPTURE_FILE="$TEST_TEMP_DIR/token.args"
mkdir -p "$FAKE_BIN"

cleanup_test() {
  rm -rf -- "$TEST_TEMP_DIR"
}
trap cleanup_test EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cat > "$FAKE_BIN/db-auth-token" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$CAPTURE_FILE"
printf 'synthetic-iam-token\n\n'
EOF
chmod +x "$FAKE_BIN/db-auth-token"

export CAPTURE_FILE
export DB_AUTH_TOKEN_COMMAND="$FAKE_BIN/db-auth-token"
export DB_TUNNEL_NAME="staging"
HOOK_OUTPUT="$(
  PATH="$FAKE_BIN:$PATH" python3 - "$HOOK_SCRIPT" <<'PY'
import runpy
import sys


class ConnectionParameters:
    url = "127.0.0.1"
    port = 15433
    database = "staging"
    user = "developer_role"
    password = "stale-token"


params = ConnectionParameters()
runpy.run_path(sys.argv[1], init_globals={"app": object(), "params": params})

assert params.url == "127.0.0.1"
assert params.port == 15433
assert params.database == "staging"
assert params.user == "developer_role"
assert params.password == "synthetic-iam-token"
PY
)"

argument_1="$(sed -n '1p' "$CAPTURE_FILE")"
argument_2="$(sed -n '2p' "$CAPTURE_FILE")"
argument_3="$(sed -n '3p' "$CAPTURE_FILE")"
argument_count="$(wc -l < "$CAPTURE_FILE" | tr -d ' ')"
[[ "$argument_1" == "staging" ]] || fail "hook should request the selected tunnel"
[[ "$argument_2" == "--db-user" ]] || fail "hook should pass the bookmark database role"
[[ "$argument_3" == "developer_role" ]] || fail "hook should preserve the bookmark database role"
[[ "$argument_count" -eq 3 ]] || fail "hook should pass only the expected token arguments"
[[ -z "$HOOK_OUTPUT" ]] || fail "hook should communicate by mutating params, not stdout"

echo "db-tunnel Valentina pre-connect tests passed"
