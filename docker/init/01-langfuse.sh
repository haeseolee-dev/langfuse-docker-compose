#!/bin/sh
set -eu

## 필수 ENV
# - (권장) CLICKHOUSE_DB / CLICKHOUSE_USER / CLICKHOUSE_PASSWORD
# (선택) CLICKHOUSE_ADMIN_USER / CLICKHOUSE_ADMIN_PASSWORD : DDL/유저 생성용 관리자 계정 (기본: default/empty)

DB="${CLICKHOUSE_DB:-langfuse}"
USER="${CLICKHOUSE_USER:-langfuse}"
PASS="${CLICKHOUSE_PASSWORD:-}"
ADMIN_USER="${CLICKHOUSE_ADMIN_USER:-default}"
ADMIN_PASS="${CLICKHOUSE_ADMIN_PASSWORD:-}"

if [ -z "$PASS" ]; then
  echo "ERROR: CLICKHOUSE_PASSWORD is empty" >&2
  exit 2
fi

# wait for server (entrypoint usually starts it in background)
until env -u CLICKHOUSE_USER -u CLICKHOUSE_PASSWORD clickhouse-client --user "$ADMIN_USER" ${ADMIN_PASS:+--password "$ADMIN_PASS"} -q "SELECT 1" >/dev/null 2>&1; do
  sleep 1
done

PASS_ESC=$(printf "%s" "$PASS" | sed "s/'/''/g")

echo "[clickhouse-initdb] ensuring db/user/grants (db=$DB user=$USER pass_len=$(printf "%s" "$PASS" | wc -c | tr -d ' '))"

# NOTE:
# - 컨테이너 환경변수로 CLICKHOUSE_USER/PASSWORD를 세팅하면 clickhouse-client가 그 값으로 로그인해 DDL이 실패할 수 있다.
# - 따라서 DDL(데이터베이스/유저/권한)은 항상 관리자 계정으로 수행한다.
env -u CLICKHOUSE_USER -u CLICKHOUSE_PASSWORD clickhouse-client --user "$ADMIN_USER" ${ADMIN_PASS:+--password "$ADMIN_PASS"} -q "CREATE DATABASE IF NOT EXISTS ${DB}"
# Langfuse(ClickHouse 클라이언트 라이브러리)가 sha256_password 핸드셰이크를 지원하지 않는 경우가 있어
# 가장 호환성이 높은 plaintext_password를 사용한다.
env -u CLICKHOUSE_USER -u CLICKHOUSE_PASSWORD clickhouse-client --user "$ADMIN_USER" ${ADMIN_PASS:+--password "$ADMIN_PASS"} -q "CREATE USER IF NOT EXISTS ${USER} IDENTIFIED WITH plaintext_password BY '${PASS_ESC}'"
env -u CLICKHOUSE_USER -u CLICKHOUSE_PASSWORD clickhouse-client --user "$ADMIN_USER" ${ADMIN_PASS:+--password "$ADMIN_PASS"} -q "ALTER USER ${USER} IDENTIFIED WITH plaintext_password BY '${PASS_ESC}'"

# user asked for GRANT ALL (broad). keep scoped to DB.
env -u CLICKHOUSE_USER -u CLICKHOUSE_PASSWORD clickhouse-client --user "$ADMIN_USER" ${ADMIN_PASS:+--password "$ADMIN_PASS"} -q "GRANT ALL ON ${DB}.* TO '${USER}'"

# sanity check
clickhouse-client --user "${USER}" --password "${PASS}" -q "SELECT 1" >/dev/null 2>&1

echo "[clickhouse-initdb] done"

