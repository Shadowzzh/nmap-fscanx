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

MOCK_BIN="$TMP_ROOT/bin"
SCAN_ROOT="$TMP_ROOT/scans/large-phase1"
mkdir -p "$MOCK_BIN"

ENTRY_COUNT=90000

cat > "$MOCK_BIN/fscanx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

entry_count="${ENTRY_COUNT:?}"

for ((i = 0; i < entry_count; i++)); do
  octet_2=$(((i / 65536) % 256))
  octet_3=$(((i / 256) % 256))
  octet_4=$((i % 256))
  printf '{"type":"Port","text":"open\\t10.%d.%d.%d:80\\t\\n"},\n' "$octet_2" "$octet_3" "$octet_4"
done > result.txt
EOF

chmod +x "$MOCK_BIN/fscanx"

ENTRY_COUNT="$ENTRY_COUNT" \
  bash "$SCRIPT_PATH" phase1 \
    --scanner "$MOCK_BIN/fscanx" \
    --targets "10.0.0.0/8" \
    --scan-root "$SCAN_ROOT" \
    > "$TMP_ROOT/large-phase1.stdout"

if [[ ! -f "$SCAN_ROOT/phase1/phase1.summary.json" ]]; then
  echo "phase1.summary.json should exist for large phase1 output" >&2
  exit 1
fi

alive_count="$(jq -r '.alive_ip_count' "$SCAN_ROOT/phase1/phase1.summary.json")"
if [[ "$alive_count" != "$ENTRY_COUNT" ]]; then
  echo "unexpected alive_ip_count for large phase1 output: $alive_count" >&2
  exit 1
fi

if jq -e '.alive_ips' "$SCAN_ROOT/phase1/phase1.summary.json" >/dev/null 2>&1; then
  echo "phase1.summary.json should not embed alive_ips for large phase1 output" >&2
  cat "$SCAN_ROOT/phase1/phase1.summary.json" >&2
  exit 1
fi

summary_size="$(wc -c < "$SCAN_ROOT/phase1/phase1.summary.json")"
if [[ "$summary_size" -ge 4096 ]]; then
  echo "phase1.summary.json should stay small for large phase1 output: $summary_size" >&2
  ls -lh "$SCAN_ROOT/phase1/phase1.summary.json" >&2
  exit 1
fi

echo "large phase1 summary regression test passed"
