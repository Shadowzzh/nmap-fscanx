#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_PATH="$REPO_ROOT/scripts/fscanx_pipeline.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
mkdir -p "$MOCK_BIN"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

assert_contains() {
  local needle="$1"
  local file="$2"

  if ! grep -Fq "$needle" "$file"; then
    echo "missing expected text: $needle" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_fails() {
  local output_file="$1"
  shift

  if "$@" >"$output_file" 2>&1; then
    echo "command should fail: $*" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

cat > "$MOCK_BIN/fscanx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${MOCK_CALLS_LOG:?}"

scenario="${MOCK_SCENARIO:-default}"
mode=""

args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -h)
      mode="phase1"
      ;;
    -hf)
      mode="phase2"
      ;;
  esac
done

if [[ "$mode" == "phase1" ]]; then
  printf '%s\n' "[*] mock phase1 raw output (${scenario})"
fi

if [[ "$mode" == "phase2" ]]; then
  printf '%s\n' "[*] mock phase2 raw output (${scenario})"
fi

case "$scenario:$mode" in
  empty_phase1:phase1)
    cat > result.txt <<'JSON'
{"type":"msg","text":"phase1-empty"},
JSON
    ;;
  empty_phase1:phase2)
    echo "phase2 should not run for empty phase1" >&2
    exit 41
    ;;
  missing_result:phase1|missing_result:phase2)
    exit 0
    ;;
  invalid_json:phase1)
    cat > result.txt <<'JSON'
{"type":"Port","text":"open\t192.168.1.10:80\t\n"},
not-json
JSON
    ;;
  duplicates:phase1)
    cat > result.txt <<'JSON'
{"type":"Port","text":"open\t192.168.1.10:80\t\n"},
{"type":"Port","text":"open\t192.168.1.10:443\t\n"},
{"type":"Port","text":"open\t192.168.1.10:80\t\n"},
{"type":"Port","text":"open\t192.168.20.15:22\t\n"},
JSON
    ;;
  duplicates:phase2)
    cat > result.txt <<'JSON'
{"type":"Port","text":"open\t192.168.1.10:80\t\n"},
{"type":"Port","text":"open\t192.168.1.10:80\t\n"},
{"type":"Port","text":"open\t192.168.20.15:22\t\n"},
{"type":"Port","text":"open\t192.168.20.15:445\t\n"},
JSON
    ;;
  *)
    cat > result.txt <<'JSON'
{"type":"Port","text":"open\t192.168.1.10:80\t\n"},
{"type":"Port","text":"open\t192.168.20.15:22\t\n"},
JSON
    ;;
esac
EOF

chmod +x "$MOCK_BIN/fscanx"
export MOCK_CALLS_LOG="$TMP_ROOT/mock_calls.log"

PHASE1_NO_TARGETS="$TMP_ROOT/phase1-no-targets.txt"
assert_fails "$PHASE1_NO_TARGETS" \
  bash "$SCRIPT_PATH" phase1 \
    --scanner "$MOCK_BIN/fscanx" \
    --scan-root "$TMP_ROOT/scan-phase1-no-targets"
assert_contains "phase1 和 all 必须提供 --targets" "$PHASE1_NO_TARGETS"

ALL_NO_TARGETS="$TMP_ROOT/all-no-targets.txt"
assert_fails "$ALL_NO_TARGETS" \
  bash "$SCRIPT_PATH" all \
    --scanner "$MOCK_BIN/fscanx" \
    --scan-root "$TMP_ROOT/scan-all-no-targets"
assert_contains "phase1 和 all 必须提供 --targets" "$ALL_NO_TARGETS"

PHASE2_MISSING="$TMP_ROOT/phase2-missing.txt"
assert_fails "$PHASE2_MISSING" \
  bash "$SCRIPT_PATH" phase2 \
    --scanner "$MOCK_BIN/fscanx" \
    --scan-root "$TMP_ROOT/scan-phase2-missing"
assert_contains "phase2 需要先存在" "$PHASE2_MISSING"

: > "$MOCK_CALLS_LOG"
EMPTY_SCAN_ROOT="$TMP_ROOT/scan-empty-phase1"
MOCK_SCENARIO="empty_phase1" \
  bash "$SCRIPT_PATH" all \
    --scanner "$MOCK_BIN/fscanx" \
    --targets "192.168.1.0/24,192.168.20.0/24" \
    --scan-root "$EMPTY_SCAN_ROOT" \
    > "$TMP_ROOT/empty-phase1.stdout"

assert_contains "COMMAND=all" "$TMP_ROOT/empty-phase1.stdout"
assert_contains "PHASE_START=phase1" "$TMP_ROOT/empty-phase1.stdout"
assert_contains "[*] mock phase1 raw output (empty_phase1)" "$TMP_ROOT/empty-phase1.stdout"
assert_contains "PHASE_DONE=phase1" "$TMP_ROOT/empty-phase1.stdout"
assert_contains "PHASE_START=phase2" "$TMP_ROOT/empty-phase1.stdout"
assert_contains "PHASE_INPUT_FILE=$EMPTY_SCAN_ROOT/phase1/alive_ips.txt" "$TMP_ROOT/empty-phase1.stdout"
assert_contains "phase1 没有存活 IP，跳过 phase2 扫描" "$TMP_ROOT/empty-phase1.stdout"
assert_contains "PHASE_DONE=phase2" "$TMP_ROOT/empty-phase1.stdout"
assert_contains "FINAL_REPORT=$EMPTY_SCAN_ROOT/report.json" "$TMP_ROOT/empty-phase1.stdout"

if [[ ! -f "$EMPTY_SCAN_ROOT/report.json" ]]; then
  echo "empty phase1 should still produce report.json" >&2
  exit 1
fi

if [[ -s "$EMPTY_SCAN_ROOT/phase1/alive_ips.txt" ]]; then
  echo "alive_ips.txt should be empty for empty phase1 scenario" >&2
  exit 1
fi

if [[ -s "$EMPTY_SCAN_ROOT/phase2/open_ip_port.txt" ]]; then
  echo "open_ip_port.txt should be empty when phase2 is skipped" >&2
  exit 1
fi

assert_contains "phase1 没有存活 IP，跳过 phase2 扫描" "$EMPTY_SCAN_ROOT/phase2/console.log"

empty_alive_count="$(jq -r '.phase1.alive_ip_count' "$EMPTY_SCAN_ROOT/report.json")"
if [[ "$empty_alive_count" != "0" ]]; then
  echo "unexpected alive_ip_count for empty phase1: $empty_alive_count" >&2
  exit 1
fi

empty_asset_count="$(jq -r '.phase2.open_ip_port_count' "$EMPTY_SCAN_ROOT/report.json")"
if [[ "$empty_asset_count" != "0" ]]; then
  echo "unexpected open_ip_port_count for empty phase1: $empty_asset_count" >&2
  exit 1
fi

if grep -Fq -- "-hf ../phase1/alive_ips.txt" "$MOCK_CALLS_LOG"; then
  echo "phase2 scanner should not run when phase1 has no alive IPs" >&2
  cat "$MOCK_CALLS_LOG" >&2
  exit 1
fi

MISSING_RESULT_OUTPUT="$TMP_ROOT/missing-result.txt"
assert_fails "$MISSING_RESULT_OUTPUT" \
  env MOCK_SCENARIO="missing_result" \
    bash "$SCRIPT_PATH" phase1 \
      --scanner "$MOCK_BIN/fscanx" \
      --targets "192.168.1.0/24" \
      --scan-root "$TMP_ROOT/scan-missing-result"
assert_contains "fscanx 执行后未生成 result.txt" "$MISSING_RESULT_OUTPUT"

INVALID_JSON_OUTPUT="$TMP_ROOT/invalid-json.txt"
assert_fails "$INVALID_JSON_OUTPUT" \
  env MOCK_SCENARIO="invalid_json" \
    bash "$SCRIPT_PATH" phase1 \
      --scanner "$MOCK_BIN/fscanx" \
      --targets "192.168.1.0/24" \
      --scan-root "$TMP_ROOT/scan-invalid-json"

INVALID_NORMALIZED="$TMP_ROOT/scan-invalid-json/phase1/normalized.json"
if [[ ! -f "$INVALID_NORMALIZED" ]]; then
  echo "normalized.json should exist for invalid JSON scenario" >&2
  exit 1
fi

if jq empty "$INVALID_NORMALIZED" >/dev/null 2>&1; then
  echo "normalized.json should remain invalid in invalid JSON scenario" >&2
  exit 1
fi

DUPLICATE_SCAN_ROOT="$TMP_ROOT/scan-duplicates"
MOCK_SCENARIO="duplicates" \
  bash "$SCRIPT_PATH" all \
    --scanner "$MOCK_BIN/fscanx" \
    --targets "192.168.1.0/24,192.168.20.0/24" \
    --scan-root "$DUPLICATE_SCAN_ROOT" \
    > "$TMP_ROOT/duplicates.stdout"

if ! diff -u <(printf '192.168.1.10\n192.168.20.15\n') "$DUPLICATE_SCAN_ROOT/phase1/alive_ips.txt" >/dev/null; then
  echo "alive_ips.txt should deduplicate repeated IPs" >&2
  exit 1
fi

if ! diff -u <(printf '192.168.1.10:80\n192.168.20.15:22\n192.168.20.15:445\n') "$DUPLICATE_SCAN_ROOT/phase2/open_ip_port.txt" >/dev/null; then
  echo "open_ip_port.txt should deduplicate repeated IP:PORT entries" >&2
  exit 1
fi

RERUN_SCAN_ROOT="$TMP_ROOT/scan-rerun-phase2"
mkdir -p "$RERUN_SCAN_ROOT/phase1"
cat > "$RERUN_SCAN_ROOT/input.json" <<'EOF'
{
  "generated_at": "2026-04-24T00:00:00+08:00",
  "command": "all",
  "scanner": "/tmp/mock-fscanx",
  "targets": ["192.168.30.0/24", "192.168.40.0/24"],
  "phase1_ports": [22, 80, 443, 445, 3389],
  "phase2_ports": "1-65535",
  "threads": 4000,
  "timeout_seconds": 1
}
EOF
cat > "$RERUN_SCAN_ROOT/phase1/alive_ips.txt" <<'EOF'
192.168.30.10
192.168.40.15
EOF
cat > "$RERUN_SCAN_ROOT/phase1/phase1.summary.json" <<'EOF'
{
  "generated_at": "2026-04-24T00:00:00+08:00",
  "phase": "phase1",
  "scanner": "/tmp/mock-fscanx",
  "targets": ["192.168.30.0/24", "192.168.40.0/24"],
  "ports": [22, 80, 443, 445, 3389],
  "alive_ip_count": 2,
  "alive_ips": ["192.168.30.10", "192.168.40.15"],
  "alive_ips_file": "phase1/alive_ips.txt"
}
EOF

: > "$MOCK_CALLS_LOG"
bash "$SCRIPT_PATH" phase2 \
  --scanner "$MOCK_BIN/fscanx" \
  --scan-root "$RERUN_SCAN_ROOT" \
  > "$TMP_ROOT/rerun-phase2.stdout"

assert_contains "COMMAND=phase2" "$TMP_ROOT/rerun-phase2.stdout"
assert_contains "TARGETS=192.168.30.0/24,192.168.40.0/24" "$TMP_ROOT/rerun-phase2.stdout"
assert_contains "PHASE_START=phase2" "$TMP_ROOT/rerun-phase2.stdout"
assert_contains "PHASE_INPUT_FILE=$RERUN_SCAN_ROOT/phase1/alive_ips.txt" "$TMP_ROOT/rerun-phase2.stdout"
assert_contains "[*] mock phase2 raw output (default)" "$TMP_ROOT/rerun-phase2.stdout"
assert_contains "PHASE_DONE=phase2" "$TMP_ROOT/rerun-phase2.stdout"
assert_contains "PHASE2_SUMMARY=$RERUN_SCAN_ROOT/phase2/phase2.summary.json" "$TMP_ROOT/rerun-phase2.stdout"
assert_contains "FINAL_REPORT=$RERUN_SCAN_ROOT/report.json" "$TMP_ROOT/rerun-phase2.stdout"

resolved_targets="$(jq -cr '.targets' "$RERUN_SCAN_ROOT/report.json")"
if [[ "$resolved_targets" != '["192.168.30.0/24","192.168.40.0/24"]' ]]; then
  echo "phase2 rerun should preserve targets from input.json" >&2
  cat "$RERUN_SCAN_ROOT/report.json" >&2
  exit 1
fi

if ! grep -Fq -- "-hf ../phase1/alive_ips.txt" "$MOCK_CALLS_LOG"; then
  echo "phase2 rerun should still use existing alive_ips.txt" >&2
  cat "$MOCK_CALLS_LOG" >&2
  exit 1
fi

STALE_REPORT_SCAN_ROOT="$TMP_ROOT/scan-stale-report"
bash "$SCRIPT_PATH" all \
  --scanner "$MOCK_BIN/fscanx" \
  --targets "192.168.1.0/24,192.168.20.0/24" \
  --scan-root "$STALE_REPORT_SCAN_ROOT" \
  > "$TMP_ROOT/stale-report-all.stdout"

if [[ ! -f "$STALE_REPORT_SCAN_ROOT/report.json" ]]; then
  echo "setup for stale report test should create report.json" >&2
  exit 1
fi

bash "$SCRIPT_PATH" phase1 \
  --scanner "$MOCK_BIN/fscanx" \
  --targets "192.168.9.0/24,192.168.4.0/24" \
  --scan-root "$STALE_REPORT_SCAN_ROOT" \
  > "$TMP_ROOT/stale-report-phase1.stdout"

assert_contains "COMMAND=phase1" "$TMP_ROOT/stale-report-phase1.stdout"
assert_contains "TARGETS=192.168.9.0/24,192.168.4.0/24" "$TMP_ROOT/stale-report-phase1.stdout"
assert_contains "PHASE_START=phase1" "$TMP_ROOT/stale-report-phase1.stdout"
assert_contains "[*] mock phase1 raw output (default)" "$TMP_ROOT/stale-report-phase1.stdout"
assert_contains "PHASE_DONE=phase1" "$TMP_ROOT/stale-report-phase1.stdout"

phase1_targets_after_rerun="$(jq -cr '.targets' "$STALE_REPORT_SCAN_ROOT/phase1/phase1.summary.json")"
if [[ "$phase1_targets_after_rerun" != '["192.168.9.0/24","192.168.4.0/24"]' ]]; then
  echo "phase1 rerun should update phase1.summary.json targets" >&2
  cat "$STALE_REPORT_SCAN_ROOT/phase1/phase1.summary.json" >&2
  exit 1
fi

if [[ -f "$STALE_REPORT_SCAN_ROOT/report.json" ]]; then
  echo "phase1 rerun should remove stale report.json" >&2
  ls -lah "$STALE_REPORT_SCAN_ROOT/report.json" >&2
  exit 1
fi

if [[ -e "$STALE_REPORT_SCAN_ROOT/phase2/open_ip_port.txt" ]]; then
  echo "phase1 rerun should remove stale phase2 outputs" >&2
  find "$STALE_REPORT_SCAN_ROOT/phase2" -maxdepth 2 -type f >&2 || true
  exit 1
fi

if ! grep -Fq "PHASE1_SUMMARY=$STALE_REPORT_SCAN_ROOT/phase1/phase1.summary.json" "$TMP_ROOT/stale-report-phase1.stdout"; then
  echo "phase1 rerun should print phase1 summary path" >&2
  cat "$TMP_ROOT/stale-report-phase1.stdout" >&2
  exit 1
fi

if ! grep -Fq "ALIVE_IP_COUNT=2" "$TMP_ROOT/stale-report-phase1.stdout"; then
  echo "phase1 rerun should print alive IP count" >&2
  cat "$TMP_ROOT/stale-report-phase1.stdout" >&2
  exit 1
fi

if ! grep -Fq "ALIVE_IP_FILE=$STALE_REPORT_SCAN_ROOT/phase1/alive_ips.txt" "$TMP_ROOT/stale-report-phase1.stdout"; then
  echo "phase1 rerun should print alive IP file path" >&2
  cat "$TMP_ROOT/stale-report-phase1.stdout" >&2
  exit 1
fi

if ! grep -Fq "ALIVE_IP_PREVIEW=192.168.1.10,192.168.20.15" "$TMP_ROOT/stale-report-phase1.stdout"; then
  echo "phase1 rerun should print alive IP preview" >&2
  cat "$TMP_ROOT/stale-report-phase1.stdout" >&2
  exit 1
fi

echo "fscanx pipeline failure-path regression test passed"
