#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_PATH="$REPO_ROOT/scripts/fscanx_pipeline.sh"

TMP_ROOT="$(mktemp -d)"
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

MOCK_BIN="$TMP_ROOT/bin"
SCAN_ROOT="$TMP_ROOT/scans/fscanx-demo"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/fscanx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${MOCK_CALLS_LOG:?}"

mode=""
host_targets=""
host_file=""
ports=""

args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -h)
      host_targets="${args[$((i + 1))]}"
      mode="phase1"
      ;;
    -hf)
      host_file="${args[$((i + 1))]}"
      mode="phase2"
      ;;
    -p)
      ports="${args[$((i + 1))]}"
      ;;
  esac
done

if [[ "$mode" == "phase1" ]]; then
  if [[ "$host_targets" != "192.168.1.0/24,192.168.20.0/24" ]]; then
    echo "unexpected phase1 targets: $host_targets" >&2
    exit 21
  fi

  if [[ "$ports" != "22,80,443,445,3389" ]]; then
    echo "unexpected phase1 ports: $ports" >&2
    exit 22
  fi

  printf '%s\n' "[*] mock phase1 raw output"
  cat > result.txt <<'JSON'
{"type":"msg","text":"phase1"},
{"type":"Port","text":"open\t192.168.1.10:80\t\n"},
{"type":"Port","text":"open\t192.168.1.10:443\t\n"},
{"type":"Port","text":"open\t192.168.20.15:22\t\n"},
JSON
  exit 0
fi

if [[ "$mode" == "phase2" ]]; then
  if [[ "$ports" != "1-65535" ]]; then
    echo "unexpected phase2 ports: $ports" >&2
    exit 23
  fi

  if [[ ! -f "$host_file" ]]; then
    echo "missing alive host file: $host_file" >&2
    exit 24
  fi

  if ! diff -u <(printf '192.168.1.10\n192.168.20.15\n') "$host_file" >/dev/null; then
    echo "unexpected alive host file content" >&2
    exit 25
  fi

  printf '%s\n' "[*] mock phase2 raw output"
  cat > result.txt <<'JSON'
{"type":"msg","text":"phase2"},
{"type":"Port","text":"open\t192.168.1.10:80\t\n"},
{"type":"Port","text":"open\t192.168.1.10:443\t\n"},
{"type":"Port","text":"open\t192.168.20.15:22\t\n"},
{"type":"Port","text":"open\t192.168.20.15:445\t\n"},
JSON
  exit 0
fi

echo "unsupported mock call: $*" >&2
exit 26
EOF

chmod +x "$MOCK_BIN/fscanx"
export MOCK_CALLS_LOG="$TMP_ROOT/mock_calls.log"

help_output="$(bash "$SCRIPT_PATH" -h 2>&1 || true)"

if ! grep -Fq "用法" <<< "$help_output"; then
  echo "help output should include 用法" >&2
  exit 1
fi

if ! grep -Fq "运行流程" <<< "$help_output"; then
  echo "help output should include 运行流程" >&2
  exit 1
fi

if ! grep -Fq "案例" <<< "$help_output"; then
  echo "help output should include 案例" >&2
  exit 1
fi

bash "$SCRIPT_PATH" all \
  --scanner "$MOCK_BIN/fscanx" \
  --targets "192.168.1.0/24,192.168.20.0/24" \
  --phase1-ports "22,80,443,445,3389" \
  --phase2-ports "1-65535" \
  --threads 4000 \
  --timeout 1 \
  --scan-root "$SCAN_ROOT" \
  > "$TMP_ROOT/pipeline.stdout"

assert_contains "COMMAND=all" "$TMP_ROOT/pipeline.stdout"
assert_contains "SCAN_ROOT=$SCAN_ROOT" "$TMP_ROOT/pipeline.stdout"
assert_contains "SCANNER=$MOCK_BIN/fscanx" "$TMP_ROOT/pipeline.stdout"
assert_contains "TARGETS=192.168.1.0/24,192.168.20.0/24" "$TMP_ROOT/pipeline.stdout"
assert_contains "PHASE_START=phase1" "$TMP_ROOT/pipeline.stdout"
assert_contains "CONSOLE_LOG=$SCAN_ROOT/phase1/console.log" "$TMP_ROOT/pipeline.stdout"
assert_contains "RESULT_FILE=$SCAN_ROOT/phase1/result.txt" "$TMP_ROOT/pipeline.stdout"
assert_contains "[*] mock phase1 raw output" "$TMP_ROOT/pipeline.stdout"
assert_contains "PHASE_DONE=phase1" "$TMP_ROOT/pipeline.stdout"
assert_contains "PHASE1_SUMMARY=$SCAN_ROOT/phase1/phase1.summary.json" "$TMP_ROOT/pipeline.stdout"
assert_contains "ALIVE_IP_COUNT=2" "$TMP_ROOT/pipeline.stdout"
assert_contains "ALIVE_IP_FILE=$SCAN_ROOT/phase1/alive_ips.txt" "$TMP_ROOT/pipeline.stdout"
assert_contains "ALIVE_IP_PREVIEW=192.168.1.10,192.168.20.15" "$TMP_ROOT/pipeline.stdout"
assert_contains "PHASE_START=phase2" "$TMP_ROOT/pipeline.stdout"
assert_contains "PHASE_INPUT_FILE=$SCAN_ROOT/phase1/alive_ips.txt" "$TMP_ROOT/pipeline.stdout"
assert_contains "CONSOLE_LOG=$SCAN_ROOT/phase2/console.log" "$TMP_ROOT/pipeline.stdout"
assert_contains "RESULT_FILE=$SCAN_ROOT/phase2/result.txt" "$TMP_ROOT/pipeline.stdout"
assert_contains "[*] mock phase2 raw output" "$TMP_ROOT/pipeline.stdout"
assert_contains "PHASE_DONE=phase2" "$TMP_ROOT/pipeline.stdout"
assert_contains "PHASE2_SUMMARY=$SCAN_ROOT/phase2/phase2.summary.json" "$TMP_ROOT/pipeline.stdout"
assert_contains "OPEN_IP_PORT_COUNT=4" "$TMP_ROOT/pipeline.stdout"
assert_contains "OPEN_IP_PORT_FILE=$SCAN_ROOT/phase2/open_ip_port.txt" "$TMP_ROOT/pipeline.stdout"
assert_contains "FINAL_REPORT=$SCAN_ROOT/report.json" "$TMP_ROOT/pipeline.stdout"

if [[ ! -f "$SCAN_ROOT/phase1/alive_ips.txt" ]]; then
  echo "alive_ips.txt was not created" >&2
  exit 1
fi

if [[ ! -f "$SCAN_ROOT/phase2/open_ip_port.txt" ]]; then
  echo "open_ip_port.txt was not created" >&2
  exit 1
fi

if ! diff -u <(printf '192.168.1.10\n192.168.20.15\n') "$SCAN_ROOT/phase1/alive_ips.txt" >/dev/null; then
  echo "unexpected alive_ips.txt content" >&2
  exit 1
fi

if ! diff -u <(printf '192.168.1.10:80\n192.168.1.10:443\n192.168.20.15:22\n192.168.20.15:445\n') "$SCAN_ROOT/phase2/open_ip_port.txt" >/dev/null; then
  echo "unexpected open_ip_port.txt content" >&2
  exit 1
fi

if ! grep -Fq -- "-hf ../phase1/alive_ips.txt" "$MOCK_CALLS_LOG"; then
  echo "phase2 should read phase1 alive_ips.txt via -hf" >&2
  exit 1
fi

assert_contains "[*] mock phase1 raw output" "$SCAN_ROOT/phase1/console.log"
assert_contains "[*] mock phase2 raw output" "$SCAN_ROOT/phase2/console.log"

if [[ ! -f "$SCAN_ROOT/report.json" ]]; then
  echo "report.json was not created" >&2
  exit 1
fi

alive_count="$(jq -r '.phase1.alive_ip_count' "$SCAN_ROOT/report.json")"
if [[ "$alive_count" != "2" ]]; then
  echo "unexpected alive_ip_count: $alive_count" >&2
  exit 1
fi

asset_count="$(jq -r '.phase2.open_ip_port_count' "$SCAN_ROOT/report.json")"
if [[ "$asset_count" != "4" ]]; then
  echo "unexpected open_ip_port_count: $asset_count" >&2
  exit 1
fi

assets_json="$(jq -c '.assets' "$SCAN_ROOT/report.json")"
if [[ "$assets_json" != '["192.168.1.10:80","192.168.1.10:443","192.168.20.15:22","192.168.20.15:445"]' ]]; then
  echo "unexpected assets list: $assets_json" >&2
  exit 1
fi

echo "fscanx pipeline regression test passed"
