#!/usr/bin/env bash
# Exercises db-access add/view/remove against a local PostgreSQL with a fake
# AWS CLI and a fake db-tunnel that forwards to it. Needs a local server where
# the current user can create roles (PGHOST/PGPORT/PGUSER as usual).
set -euo pipefail

TEST_DIR="$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1
  pwd
)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." >/dev/null 2>&1 && pwd)"
DB_ACCESS="$REPO_ROOT/packages/db-access/bin/db-access"

TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/db-access-test.XXXXXX")"
FAKE_BIN="$TEST_TEMP_DIR/bin"
FAKE_PKG="$TEST_TEMP_DIR/db-tunnel"
AWS_LOG="$TEST_TEMP_DIR/aws.log"
POLICY_DIR="$TEST_TEMP_DIR/policies"
ROLE="db_access_test_jane"
PG_ROLES="rds_iam cap_readonly cap_readwrite cap_admin"
ADMIN_ROLE="${PGUSER:-$(id -un)}"
mkdir -p "$FAKE_BIN" "$FAKE_PKG/bin" "$FAKE_PKG/share" "$POLICY_DIR"

psql_admin() {
  psql -X -q -A -t -v ON_ERROR_STOP=1 -d postgres "$@"
}

created_roles=""
cleanup_test() {
  local role
  psql_admin -c "drop role if exists $ROLE" >/dev/null 2>&1 || true
  for role in $created_roles; do
    psql_admin -c "drop role if exists $role" >/dev/null 2>&1 || true
  done
  rm -rf -- "$TEST_TEMP_DIR"
}
trap cleanup_test EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for role in $PG_ROLES; do
  if [[ -z "$(psql_admin -c "select 1 from pg_roles where rolname = '$role'")" ]]; then
    psql_admin -c "create role $role"
    created_roles="$created_roles $role"
  fi
done

cat > "$FAKE_PKG/share/db-tunnels.json" <<EOF
{
  "tunnels": {
    "dev": { "profile": "default", "region": "eu-west-1", "target": "i-0test",
             "host": "dev-proxy-read-only.endpoint.proxy-x.eu-west-1.rds.amazonaws.com",
             "database": "postgres", "remotePort": 5432, "localPort": 15432 },
    "dev-writer": { "profile": "default", "region": "eu-west-1", "target": "i-0test",
                    "host": "dev-proxy.proxy-x.eu-west-1.rds.amazonaws.com",
                    "database": "postgres", "remotePort": 5432, "localPort": 15432 }
  }
}
EOF

# Forwards --local-port to the local server, like an SSM port-forward would.
cat > "$FAKE_PKG/bin/db-tunnel" <<'EOF'
#!/usr/bin/env bash
port="$4"
exec python3 - "$port" "${PGPORT:-5432}" <<'PY'
import socket, sys, threading
listen, target = int(sys.argv[1]), int(sys.argv[2])
server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", listen))
server.listen()
def pipe(a, b):
    try:
        while data := a.recv(65536):
            b.sendall(data)
    except OSError:
        pass
    finally:
        b.close()
while True:
    client, _ = server.accept()
    upstream = socket.create_connection(("127.0.0.1", target))
    threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
    threading.Thread(target=pipe, args=(upstream, client), daemon=True).start()
PY
EOF

cat > "$FAKE_PKG/bin/db-auth-token" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${PGPASSWORD:-unused}"
EOF

# Stores inline policies as files and answers only the calls db-access makes.
cat > "$FAKE_BIN/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$AWS_LOG"
args=" $* "
arg_after() {
  local want="$1" previous=""
  for arg in "${ARGS[@]}"; do
    [[ "$previous" == "$want" ]] && { printf '%s\n' "$arg"; return; }
    previous="$arg"
  done
}
ARGS=("$@")
case "$args" in
  *" sts get-caller-identity "*" Account "*) echo 123456789012 ;;
  *" sts get-caller-identity "*) echo "arn:aws:iam::123456789012:user/Admin" ;;
  *" iam list-users "*)
    if [[ -f "$POLICY_DIR/.user" ]]; then echo '["Admin", "Jane"]'; else echo '["Admin"]'; fi ;;
  *" iam create-user "*) touch "$POLICY_DIR/.user" ;;
  *" rds describe-db-proxies "*) echo "arn:aws:rds:eu-west-1:123456789012:db-proxy:prx-0test" ;;
  *" iam put-user-policy "*)
    printf '%s' "$(arg_after --policy-document)" > "$POLICY_DIR/$(arg_after --policy-name)" ;;
  *" iam get-user-policy "*)
    file="$POLICY_DIR/$(arg_after --policy-name)"
    [[ -f "$file" ]] || { echo "NoSuchEntity" >&2; exit 254; }
    cat "$file" ;;
  *" iam delete-user-policy "*)
    file="$POLICY_DIR/$(arg_after --policy-name)"
    [[ -f "$file" ]] || exit 254
    rm "$file" ;;
  *" iam simulate-principal-policy "*)
    if [[ -f "$POLICY_DIR/db-tunnel-dev" ]]; then echo allowed; else echo implicitDeny; fi ;;
  *" iam list-access-keys "*) echo '[["AKIATEST", "2026-01-01"]]' ;;
  *" iam get-access-key-last-used "*) echo None ;;
  *" iam create-access-key "*) echo '{"AccessKeyId": "AKIANEW", "SecretAccessKey": "secret"}' ;;
  *" iam list-user-policies "*) ls "$POLICY_DIR" | jq -R . | jq -s . ;;
  *" iam list-attached-user-policies "*) echo '[]' ;;
  *" ssm describe-instance-information "*) echo Online ;;
  *) echo "fake aws: unexpected call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$FAKE_BIN/aws" "$FAKE_PKG/bin/db-tunnel" "$FAKE_PKG/bin/db-auth-token"

# A copy beside the fake package, which db-access finds as its checkout sibling.
TEST_DB_ACCESS="$TEST_TEMP_DIR/db-access/bin/db-access"
mkdir -p "$(dirname "$TEST_DB_ACCESS")"
cp "$DB_ACCESS" "$TEST_DB_ACCESS"

export AWS_LOG POLICY_DIR
export PATH="$FAKE_BIN:/usr/bin:/bin:$(dirname "$(command -v psql)"):$(dirname "$(command -v jq)"):$(dirname "$(command -v python3)")"
export PGSSLMODE=disable
export DB_ACCESS_ADMIN_USER="$ADMIN_ROLE"

run() {
  "$TEST_DB_ACCESS" "$@" --db-role "$ROLE" 2>&1
}

role_state() {
  psql_admin -F'|' -c "
    select r.rolcanlogin,
           coalesce(string_agg(g.rolname, ',' order by g.rolname), '')
    from pg_roles r
    left join pg_auth_members m on m.member = r.oid
    left join pg_roles g on g.oid = m.roleid
    where r.rolname = '$ROLE'
    group by r.rolcanlogin"
}

output="$(run add jane --env dev --yes)" && fail "add should refuse an unknown IAM user without --create-iam-user"
[[ "$output" == *"--create-iam-user"* ]] || fail "add should suggest --create-iam-user, got: $output"

output="$(run add jane --env dev --create-iam-user --new-access-key --yes)" || fail "add failed: $output"
[[ "$(role_state)" == "t|cap_readonly,rds_iam" ]] || fail "add should create a readonly IAM-auth role, got: $(role_state)"
jq -e --arg r "arn:aws:rds-db:eu-west-1:123456789012:dbuser:prx-0test/$ROLE" \
  '.Statement[] | select(.Sid == "ConnectAsOwnDatabaseRole") | .Resource == $r' \
  "$POLICY_DIR/db-tunnel-dev" >/dev/null || fail "policy should allow rds-db:connect as the role on the proxy"
jq -e '.Statement[] | select(.Sid == "PortForwardThroughTunnelHost")
       | .Condition.BoolIfExists["ssm:SessionDocumentAccessCheck"] == "true"' \
  "$POLICY_DIR/db-tunnel-dev" >/dev/null || fail "StartSession should be limited to the port-forward document"
[[ "$output" == *"AKIANEW"* && "$output" == *"secret"* ]] || fail "add --new-access-key should print the key once"

output="$(run add jane --env dev --access readwrite --yes)" || fail "re-add failed: $output"
[[ "$(role_state)" == "t|cap_readwrite,rds_iam" ]] || fail "re-add should switch access level, got: $(role_state)"

output="$(run view jane --env dev)" || fail "view should report no problems after add: $output"
[[ "$output" == *"db-tunnel-dev is current"* ]] || fail "view should recognise the current policy: $output"

output="$(run remove jane --env dev --yes)" || fail "remove failed: $output"
[[ "$(role_state)" == "f|" ]] || fail "remove should disable the role and drop memberships, got: $(role_state)"
[[ ! -f "$POLICY_DIR/db-tunnel-dev" ]] || fail "remove should delete the IAM policy"

output="$(run view jane --env dev)" && fail "view should report problems after remove"
[[ "$output" == *"NOLOGIN"* ]] || fail "view should flag the disabled role: $output"

echo "db-access tests passed"
