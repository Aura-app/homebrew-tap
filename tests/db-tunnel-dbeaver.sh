#!/usr/bin/env bash
# The harness intentionally supplies globals and mock functions to sourced code.
# shellcheck disable=SC1091,SC2016,SC2034,SC2123,SC2329
set -euo pipefail

TEST_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." >/dev/null 2>&1 && pwd)"
DB_TUNNEL_SCRIPT="$REPO_ROOT/packages/db-tunnel/bin/db-tunnel"

# shellcheck source=../packages/db-tunnel/bin/db-tunnel
source "$DB_TUNNEL_SCRIPT"

TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/db-tunnel-test.XXXXXX")"
CAPTURE_DIR="$TEST_TEMP_DIR/capture"
FAKE_BIN="$TEST_TEMP_DIR/bin"
ORIGINAL_PATH="$PATH"
SLEEP_EXECUTABLE="$(command -v sleep)"
mkdir -p "$CAPTURE_DIR" "$FAKE_BIN" "$TEST_TEMP_DIR/tmp"

cleanup_test() {
  rm -rf -- "$TEST_TEMP_DIR"
}
trap cleanup_test EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [[ "$actual" != "$expected" ]]; then
    fail "$message (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$message (missing '$needle')"
  fi
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if ! grep -F -- "$needle" "$file" >/dev/null; then
    fail "$message (missing '$needle' in $file)"
  fi
}

assert_file_not_contains() {
  local file="$1"
  local needle="$2"
  local message="$3"

  if grep -F -- "$needle" "$file" >/dev/null; then
    fail "$message (unexpected '$needle' in $file)"
  fi
}

test_db_user_precedence() {
  DB_AUTH_TOKEN_DB_USER="auth-user"
  PGUSER="pg-user"
  DB_TUNNEL_DB_USER="fallback-user"

  resolve_db_user "explicit-user"
  assert_eq "explicit-user" "$RESOLVED_DB_USER" "explicit user should win"

  resolve_db_user ""
  assert_eq "auth-user" "$RESOLVED_DB_USER" "token-specific user should precede PGUSER"

  unset DB_AUTH_TOKEN_DB_USER
  resolve_db_user ""
  assert_eq "pg-user" "$RESOLVED_DB_USER" "PGUSER should precede the legacy fallback"

  unset PGUSER
  resolve_db_user ""
  assert_eq "fallback-user" "$RESOLVED_DB_USER" "legacy fallback should still work"

  unset DB_TUNNEL_DB_USER
}

test_linux_launcher_detection() {
  uname() {
    printf 'Linux\n'
  }

  cat > "$FAKE_BIN/dbeaver-ce" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$FAKE_BIN/dbeaver-ce"

  PATH="$FAKE_BIN"
  unset DB_TUNNEL_DBEAVER_EXECUTABLE
  DBEAVER_LAUNCH_MODE=""
  DBEAVER_LAUNCH_TARGET=""
  resolve_dbeaver_launcher

  assert_eq "executable" "$DBEAVER_LAUNCH_MODE" "Linux should use an executable launcher"
  assert_eq "$FAKE_BIN/dbeaver-ce" "$DBEAVER_LAUNCH_TARGET" "Linux should find dbeaver-ce on PATH"
  PATH="$ORIGINAL_PATH"
  unset -f uname
}

test_macos_launcher_detection() {
  uname() {
    printf 'Darwin\n'
  }

  open() {
    [[ "$1" == "-Ra" && "$2" == "DBeaverEE.app" ]]
  }

  unset DB_TUNNEL_DBEAVER_EXECUTABLE
  DBEAVER_LAUNCH_MODE=""
  DBEAVER_LAUNCH_TARGET=""
  resolve_dbeaver_launcher

  assert_eq "macos_app" "$DBEAVER_LAUNCH_MODE" "macOS should use open with an app bundle"
  assert_eq "DBeaverEE.app" "$DBEAVER_LAUNCH_TARGET" "macOS should detect supported paid editions"

  unset -f uname open
}

test_unsupported_platform() {
  local output

  if output="$({
    uname() {
      printf 'FreeBSD\n'
    }
    unset DB_TUNNEL_DBEAVER_EXECUTABLE
    resolve_dbeaver_launcher
  } 2>&1)"; then
    fail "unsupported platforms should be rejected"
  fi

  assert_contains "$output" "supported only on Linux and macOS" "unsupported-platform error should be actionable"
}

test_missing_dbeaver_guidance() {
  local output

  mkdir -p "$TEST_TEMP_DIR/empty-bin"

  if output="$({
    uname() {
      printf 'Linux\n'
    }
    PATH="$TEST_TEMP_DIR/empty-bin"
    unset DB_TUNNEL_DBEAVER_EXECUTABLE
    resolve_dbeaver_launcher
  } 2>&1)"; then
    fail "missing DBeaver should be rejected"
  fi

  assert_contains "$output" "Checked PATH for: dbeaver, dbeaver-ce" "missing-app error should list detected executable names"
  assert_contains "$output" "DB_TUNNEL_DBEAVER_EXECUTABLE" "missing-app error should explain the override"
}

create_full_flow_fakes() {
  cat > "$FAKE_BIN/db-auth-token" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$CAPTURE_DIR/token.args"
printf 'temporary-iam-token\n'
EOF

  cat > "$FAKE_BIN/dbeaver" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$CAPTURE_DIR/dbeaver.args"

variables_file=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-vars" ]]; then
    variables_file="$2"
    break
  fi
  shift
done

[[ -n "$variables_file" ]]
cp "$variables_file" "$CAPTURE_DIR/variables.properties"
if mode="$(stat -c '%a' "$variables_file" 2>/dev/null)"; then
  printf '%s\n' "$mode" > "$CAPTURE_DIR/variables.mode"
else
  stat -f '%Lp' "$variables_file" > "$CAPTURE_DIR/variables.mode"
fi
EOF

  chmod +x "$FAKE_BIN/db-auth-token" "$FAKE_BIN/dbeaver"
}

test_full_dbeaver_flow() {
  local output
  local output_file="$CAPTURE_DIR/full-flow.output"
  local secret_dir

  create_full_flow_fakes
  export CAPTURE_DIR
  TMPDIR="$TEST_TEMP_DIR/tmp"
  DB_TUNNEL_DBEAVER_EXECUTABLE="$FAKE_BIN/dbeaver"
  DB_AUTH_TOKEN_COMMAND="$FAKE_BIN/db-auth-token"
  CONFIG_FILE="$REPO_ROOT/packages/db-tunnel/share/db-tunnels.json"
  PORT_CHECKS=0

  ensure_session_manager_plugin() {
    :
  }

  ensure_aws_login() {
    :
  }

  port_is_open() {
    PORT_CHECKS=$((PORT_CHECKS + 1))
    [[ "$PORT_CHECKS" -gt 1 ]]
  }

  start_tunnel_session() {
    "$SLEEP_EXECUTABLE" 2
  }

  open_tunnel staging --local-port 16444 --dbeaver --db-user explicit-user > "$output_file"
  output="$(<"$output_file")"
  secret_dir="$DBEAVER_TEMP_DIR"

  assert_contains "$output" "DBeaver launched with a temporary 'Aura staging' connection." "full flow should report launch"
  assert_file_contains "$CAPTURE_DIR/token.args" "staging --db-user explicit-user" "token helper should receive the tunnel and role"
  assert_file_contains "$CAPTURE_DIR/dbeaver.args" 'driver=postgres-jdbc|name=Aura staging|host=127.0.0.1|port=16444|database=staging|user=explicit-user|password=${password}|prop.sslmode=require|connect=true|create=true|save=false' "DBeaver should receive the temporary connection specification"
  assert_file_not_contains "$CAPTURE_DIR/dbeaver.args" "temporary-iam-token" "token must not appear in process arguments"
  assert_file_not_contains "$CAPTURE_DIR/dbeaver.args" "openConsole" "connect-only mode must not open a SQL console"
  assert_file_contains "$CAPTURE_DIR/variables.properties" "password=temporary-iam-token" "variables file should carry the token"
  assert_eq "600" "$(<"$CAPTURE_DIR/variables.mode")" "variables file should be private"

  cleanup_dbeaver_session
  trap cleanup_test EXIT

  if [[ -e "$secret_dir" ]]; then
    fail "temporary DBeaver directory should be removed during cleanup"
  fi

  unset -f ensure_session_manager_plugin ensure_aws_login port_is_open start_tunnel_session
  unset DB_TUNNEL_DBEAVER_EXECUTABLE DB_AUTH_TOKEN_COMMAND TMPDIR
}

test_macos_launch_arguments() {
  local secret_dir

  DBEAVER_LAUNCH_MODE="macos_app"
  DBEAVER_LAUNCH_TARGET="DBeaverUltimate.app"
  TMPDIR="$TEST_TEMP_DIR/tmp"

  open() {
    printf '%s\n' "$@" > "$CAPTURE_DIR/macos-open.args"
  }

  launch_dbeaver "production" "15434" "production" "mac-user" "mac-token" >/dev/null
  secret_dir="$DBEAVER_TEMP_DIR"

  assert_file_contains "$CAPTURE_DIR/macos-open.args" "-a" "macOS should use open -a"
  assert_file_contains "$CAPTURE_DIR/macos-open.args" "DBeaverUltimate.app" "macOS should launch the detected edition"
  assert_file_contains "$CAPTURE_DIR/macos-open.args" "--args" "macOS should pass DBeaver CLI arguments after --args"
  assert_file_contains "$CAPTURE_DIR/macos-open.args" "connect=true" "macOS connection should connect immediately"
  assert_file_not_contains "$CAPTURE_DIR/macos-open.args" "mac-token" "macOS argv must not expose the token"

  cleanup_dbeaver_session
  trap cleanup_test EXIT
  [[ ! -e "$secret_dir" ]] || fail "macOS launch secrets should be cleaned up"

  unset -f open
  unset TMPDIR
}

test_busy_port_rejected_before_session() {
  local output
  local session_marker="$CAPTURE_DIR/session-started"

  DB_TUNNEL_DBEAVER_EXECUTABLE="$FAKE_BIN/dbeaver"
  DB_AUTH_TOKEN_COMMAND="$FAKE_BIN/db-auth-token"
  CONFIG_FILE="$REPO_ROOT/packages/db-tunnel/share/db-tunnels.json"

  port_is_open() {
    return 0
  }

  start_tunnel_session() {
    touch "$session_marker"
  }

  if output="$(open_tunnel dev --dbeaver --db-user test-user 2>&1)"; then
    fail "busy local ports should be rejected"
  fi

  assert_contains "$output" "already in use" "busy-port error should explain the refusal"
  [[ ! -e "$session_marker" ]] || fail "SSM session should not start when the local port is busy"

  unset -f port_is_open start_tunnel_session
  unset DB_TUNNEL_DBEAVER_EXECUTABLE DB_AUTH_TOKEN_COMMAND
}

test_db_user_requires_dbeaver() {
  local output

  if output="$(open_tunnel dev --db-user test-user 2>&1)"; then
    fail "--db-user without --dbeaver should fail"
  fi

  assert_contains "$output" "supported only with --dbeaver" "invalid option combination should be explained"
}

test_readiness_failures() {
  local output

  port_is_open() {
    return 1
  }

  sleep() {
    :
  }

  "$SLEEP_EXECUTABLE" 5 &
  TUNNEL_PID=$!
  if output="$(wait_for_tunnel 15432 2>&1)"; then
    fail "readiness timeout should fail"
  fi
  assert_contains "$output" "Timed out waiting 30 seconds" "timeout should be explicit"
  kill "$TUNNEL_PID" >/dev/null 2>&1 || true
  wait "$TUNNEL_PID" >/dev/null 2>&1 || true
  TUNNEL_PID=""

  (exit 7) &
  TUNNEL_PID=$!
  "$SLEEP_EXECUTABLE" 0.05
  if output="$(wait_for_tunnel 15432 2>&1)"; then
    fail "an early SSM exit should fail readiness"
  fi
  assert_contains "$output" "exited before local port" "early exit should be distinguished from timeout"
  TUNNEL_PID=""

  unset -f port_is_open sleep
}

test_cleanup_leaves_dbeaver_running() {
  local child_pid
  local child_pid_file="$CAPTURE_DIR/tunnel-child.pid"
  local dbeaver_pid
  local tunnel_pid

  DBEAVER_TEMP_DIR="$(mktemp -d "$TEST_TEMP_DIR/tmp/cleanup.XXXXXX")"
  touch "$DBEAVER_TEMP_DIR/variables.properties" "$DBEAVER_TEMP_DIR/dbeaver.log"

  mock_tunnel_with_child() {
    "$SLEEP_EXECUTABLE" 5 &
    printf '%s\n' "$!" > "$child_pid_file"
    wait
  }

  set -m
  mock_tunnel_with_child &
  TUNNEL_PID=$!
  tunnel_pid="$TUNNEL_PID"
  set +m

  for _ in {1..20}; do
    [[ -f "$child_pid_file" ]] && break
    "$SLEEP_EXECUTABLE" 0.01
  done
  [[ -f "$child_pid_file" ]] || fail "mock tunnel child did not start"
  child_pid="$(<"$child_pid_file")"

  set -m
  "$SLEEP_EXECUTABLE" 5 &
  dbeaver_pid=$!
  set +m
  "$SLEEP_EXECUTABLE" 0.05

  kill -0 "$tunnel_pid" >/dev/null 2>&1 || fail "mock tunnel should be running before cleanup"
  kill -0 "$child_pid" >/dev/null 2>&1 || fail "mock Session Manager child should be running before cleanup"
  kill -0 "$dbeaver_pid" >/dev/null 2>&1 || fail "mock DBeaver should be running before cleanup"

  cleanup_dbeaver_session
  trap cleanup_test EXIT

  if kill -0 "$tunnel_pid" >/dev/null 2>&1; then
    fail "cleanup should stop the SSM tunnel"
  fi
  if kill -0 "$child_pid" >/dev/null 2>&1; then
    fail "cleanup should stop the Session Manager child process"
  fi
  if ! kill -0 "$dbeaver_pid" >/dev/null 2>&1; then
    fail "cleanup should leave DBeaver running"
  fi

  kill "$dbeaver_pid" >/dev/null 2>&1 || true
  wait "$dbeaver_pid" >/dev/null 2>&1 || true
  TUNNEL_PID=""
  unset -f mock_tunnel_with_child
}

test_db_user_precedence
test_linux_launcher_detection
test_macos_launcher_detection
test_unsupported_platform
test_missing_dbeaver_guidance
test_full_dbeaver_flow
test_macos_launch_arguments
test_busy_port_rejected_before_session
test_db_user_requires_dbeaver
test_readiness_failures
test_cleanup_leaves_dbeaver_running

echo "db-tunnel DBeaver tests passed"
