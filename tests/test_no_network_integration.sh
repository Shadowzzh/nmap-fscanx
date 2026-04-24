#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "skipped: Linux only integration test"
  exit 0
fi

for required in sudo unshare ip timeout jq; do
  if ! command -v "$required" >/dev/null 2>&1; then
    echo "skipped: missing required command $required"
    exit 0
  fi
done

if ! sudo -n true >/dev/null 2>&1; then
  echo "skipped: requires passwordless sudo"
  exit 0
fi

if ! sudo -n unshare -n true >/dev/null 2>&1; then
  echo "skipped: sudo unshare -n unavailable"
  exit 0
fi

TMP_ROOT="$(mktemp -d)"
PACKAGE_ROOT="$TMP_ROOT/package-root"
PREFIX_ROOT="$TMP_ROOT/prefix-root"
RUNTIME_HOME="$TMP_ROOT/runtime-home"
SCAN_ROOT="$TMP_ROOT/no-network-scan"
MOCK_CALLS_LOG="$TMP_ROOT/mock_calls.log"
NETWORK_PROBE_LOG="$TMP_ROOT/network_probe.log"
ROUTE_LOG="$TMP_ROOT/routes.txt"
MOCK_SCANNER="$TMP_ROOT/mock-fscanx"

cleanup() {
  sudo -n rm -rf "$TMP_ROOT" 2>/dev/null || rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cp -R "$REPO_ROOT/prod-lite/." "$PACKAGE_ROOT/"
cp "$REPO_ROOT/scripts/fscanx_pipeline.sh" "$PACKAGE_ROOT/libexec/fscanx_pipeline.sh"

cat > "$MOCK_SCANNER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${MOCK_CALLS_LOG:?}"

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

if [[ "$mode" == "phase2" ]]; then
  echo "phase2 should not run in no-network integration test" >&2
  exit 41
fi

probe_status=0
timeout 2 bash -lc 'echo >/dev/tcp/198.51.100.1/80' >/dev/null 2>&1 || probe_status=$?
printf '%s\n' "$probe_status" >> "${NETWORK_PROBE_LOG:?}"

cat > result.txt <<'JSON'
{"type":"msg","text":"no-network-phase1"},
JSON
EOF

chmod +x "$MOCK_SCANNER"
mkdir -p "$RUNTIME_HOME"

bash "$PACKAGE_ROOT/install.sh" \
  --prefix "$PREFIX_ROOT" \
  --scanner "$MOCK_SCANNER" \
  > "$TMP_ROOT/install.log" 2>&1

sudo -n env \
  HOME="$RUNTIME_HOME" \
  PATH="/usr/sbin:/usr/bin:/bin" \
  ROUTE_LOG="$ROUTE_LOG" \
  SCAN_ROOT="$SCAN_ROOT" \
  CMD_BIN="$PREFIX_ROOT/bin/nmap-fscanx" \
  MOCK_CALLS_LOG="$MOCK_CALLS_LOG" \
  NETWORK_PROBE_LOG="$NETWORK_PROBE_LOG" \
  unshare -n bash -lc '
    set -euo pipefail
    ip link set lo up
    ip route > "$ROUTE_LOG"
    "$CMD_BIN" run --targets "198.51.100.1/32" --scan-root "$SCAN_ROOT"
  ' > "$TMP_ROOT/run.stdout" 2> "$TMP_ROOT/run.stderr"

if [[ ! -f "$SCAN_ROOT/report.json" ]]; then
  echo "report.json should exist in no-network integration test" >&2
  exit 1
fi

alive_count="$(jq -r '.phase1.alive_ip_count' "$SCAN_ROOT/report.json")"
if [[ "$alive_count" != "0" ]]; then
  echo "unexpected alive_ip_count in no-network integration test: $alive_count" >&2
  exit 1
fi

asset_count="$(jq -r '.phase2.open_ip_port_count' "$SCAN_ROOT/report.json")"
if [[ "$asset_count" != "0" ]]; then
  echo "unexpected open_ip_port_count in no-network integration test: $asset_count" >&2
  exit 1
fi

if [[ ! -f "$SCAN_ROOT/phase2/console.log" ]]; then
  echo "phase2 console log should exist when phase2 is skipped" >&2
  exit 1
fi

if ! grep -Fq "phase1 没有存活 IP，跳过 phase2 扫描" "$SCAN_ROOT/phase2/console.log"; then
  echo "phase2 skip message missing in no-network integration test" >&2
  cat "$SCAN_ROOT/phase2/console.log" >&2
  exit 1
fi

if [[ ! -s "$NETWORK_PROBE_LOG" ]]; then
  echo "network probe log should record at least one failed probe" >&2
  exit 1
fi

if ! awk '$1 != 0 { found = 1 } END { exit(found ? 0 : 1) }' "$NETWORK_PROBE_LOG"; then
  echo "expected at least one non-zero network probe status in no-network integration test" >&2
  cat "$NETWORK_PROBE_LOG" >&2
  exit 1
fi

if grep -Eq '^default ' "$ROUTE_LOG"; then
  echo "network namespace should not have a default route" >&2
  cat "$ROUTE_LOG" >&2
  exit 1
fi

if grep -Fq -- "-hf ../phase1/alive_ips.txt" "$MOCK_CALLS_LOG"; then
  echo "phase2 scanner should not run in no-network integration test" >&2
  cat "$MOCK_CALLS_LOG" >&2
  exit 1
fi

echo "no-network integration test passed"
