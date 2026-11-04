#!/usr/bin/env bash
#
# windmill-recover-admin.sh
#
# Recovers superadmin access to a self-hosted Windmill instance by talking to
# psql inside the postgres-windmill container.
#
# Usage:
#   ./windmill-recover-admin.sh inspect
#   ./windmill-recover-admin.sh settings
#   ./windmill-recover-admin.sh unset-setting <key>
#   ./windmill-recover-admin.sh reset-password <email>
#   ./windmill-recover-admin.sh create-admin <email>
#   ./windmill-recover-admin.sh psql            # interactive shell
#
# reset-password and create-admin set the password to "changeme".
# Change it in the UI immediately after logging in.

set -euo pipefail

CONTAINER="${WM_PG_CONTAINER:-postgres-windmill}"
DB_USER="${WM_PG_USER:-windmill}"
DB_NAME="${WM_PG_DB:-windmill}"

# argon2id hash of "changeme" — the value published by the Windmill maintainers
# for exactly this recovery path.
CHANGEME_HASH='$argon2id$v=19$m=4096,t=3,p=1$z0Kg3qyaS14e+YHeihkJLQ$N69flI6yQ/U98pjAHtbNxbdz2f4PrJEi9Tx1VoYk1as'

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_container() {
  docker inspect "$CONTAINER" >/dev/null 2>&1 \
    || die "container '$CONTAINER' not found (override with WM_PG_CONTAINER=...)"
  [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER")" = "true" ] \
    || die "container '$CONTAINER' is not running"
}

# Run SQL non-interactively. SQL arrives on stdin so no quoting games.
psql_run() {
  docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d "$DB_NAME" "$@"
}

cmd_psql() {
  docker exec -it "$CONTAINER" psql -U "$DB_USER" -d "$DB_NAME"
}

cmd_inspect() {
  psql_run <<'SQL'
\echo '=== accounts ==='
SELECT email,
       super_admin,
       login_type,
       verified,
       (password_hash IS NOT NULL AND password_hash <> '') AS has_password
FROM password
ORDER BY super_admin DESC, email;

\echo ''
\echo '=== superadmin count ==='
SELECT count(*) AS superadmins FROM password WHERE super_admin;
SQL
}

cmd_settings() {
  psql_run <<'SQL'
\echo '=== global_settings ==='
SELECT name, value FROM global_settings ORDER BY name;
SQL
}

cmd_unset_setting() {
  local key="${1:-}"
  [ -n "$key" ] || die "usage: $0 unset-setting <key>"

  printf 'Removing global_settings row: %s\n' "$key"
  KEY="$key" psql_run <<'SQL'
DELETE FROM global_settings WHERE name = :'key';
SQL
}

cmd_reset_password() {
  local email="${1:-admin@windmill.dev}"

  psql_run -v email="$email" -v hash="$CHANGEME_HASH" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM password WHERE email = current_setting('wm.email')) THEN
    RAISE EXCEPTION 'no account with email %, use create-admin instead',
      current_setting('wm.email');
  END IF;
END $$;

UPDATE password
SET password_hash = :'hash',
    super_admin   = true,
    login_type    = 'password',
    verified      = true
WHERE email = :'email';

SELECT email, super_admin, login_type, verified
FROM password WHERE email = :'email';
SQL
}

cmd_create_admin() {
  local email="${1:-}"
  [ -n "$email" ] || die "usage: $0 create-admin <email>"

  psql_run -v email="$email" -v hash="$CHANGEME_HASH" <<'SQL'
INSERT INTO password (email, password_hash, super_admin, login_type, verified, name)
VALUES (:'email', :'hash', true, 'password', true, 'recovery admin')
ON CONFLICT (email) DO UPDATE
SET password_hash = EXCLUDED.password_hash,
    super_admin   = true,
    login_type    = 'password',
    verified      = true;

SELECT email, super_admin, login_type, verified
FROM password WHERE email = :'email';
SQL
}

main() {
  require_container

  case "${1:-}" in
    inspect)        cmd_inspect ;;
    settings)       cmd_settings ;;
    unset-setting)  shift; cmd_unset_setting "$@" ;;
    reset-password) shift; cmd_reset_password "$@" ;;
    create-admin)   shift; cmd_create_admin "$@" ;;
    psql)           cmd_psql ;;
    *)
      sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 1
      ;;
  esac

  case "${1:-}" in
    reset-password|create-admin|unset-setting)
      printf '\nNow restart the server so cached settings are re-read:\n'
      printf '  docker compose restart windmill-server\n'
      ;;
  esac
}

main "$@"