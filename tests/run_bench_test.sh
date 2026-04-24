#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="/Users/zhangziheng/Documents/code/nmap"
SCRIPT_PATH="$REPO_ROOT/scripts/run_bench.sh"
BENCH_DIR="/tmp/scan-bench"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALLS_DIR="$TMP_ROOT/calls"
BACKUP_DIR="$TMP_ROOT/original-scan-bench"

mkdir -p "$MOCK_BIN" "$CALLS_DIR"

cleanup() {
  rm -rf "$BENCH_DIR"

  if [[ -d "$BACKUP_DIR" ]]; then
    mv "$BACKUP_DIR" "$BENCH_DIR"
  fi

  rm -rf "$TMP_ROOT"
}

trap cleanup EXIT

if [[ -e "$BENCH_DIR" ]]; then
  mv "$BENCH_DIR" "$BACKUP_DIR"
fi

mkdir -p "$BENCH_DIR"
cat > "$BENCH_DIR/targets.txt" <<'EOF'
10.0.0.0/24
10.0.1.0/24
EOF

cat > "$BENCH_DIR/targets.cidrs" <<'EOF'
10.0.0.0/24
10.0.1.0/24
EOF

cat > "$MOCK_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-n" ]]; then
  shift
fi

exec "$@"
EOF

cat > "$MOCK_BIN/zmap" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$MOCK_CALLS_DIR/zmap_calls.log"

port=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  if [[ "${args[$i]}" == "-p" && $((i + 1)) -lt ${#args[@]} ]]; then
    port="${args[$((i + 1))]}"
  fi
done

if [[ -z "$port" || "$port" == *","* ]]; then
  echo "zmap mock requires a single target port" >&2
  exit 21
fi

if [[ " $* " == *" --no-header-row "* ]]; then
  echo "zmap mock rejects --no-header-row" >&2
  exit 22
fi

case "$port" in
  22)
    printf '10.0.0.1,22,synack,1,0\n'
    ;;
  80)
    printf '10.0.0.1,80,synack,1,0\n'
    printf '10.0.0.2,80,synack,1,0\n'
    ;;
  443)
    ;;
  445)
    printf '10.0.0.3,445,synack,1,0\n'
    ;;
  3389)
    printf '10.0.0.3,3389,synack,1,0\n'
    ;;
  *)
    echo "unexpected port: $port" >&2
    exit 23
    ;;
esac
EOF

cat > "$MOCK_BIN/masscan" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$MOCK_CALLS_DIR/masscan_calls.log"
printf 'Discovered open port 22/tcp on 10.0.0.10\n'
printf 'Discovered open port 80/tcp on 10.0.0.11\n'
EOF

cat > "$MOCK_BIN/fscanx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$MOCK_CALLS_DIR/fscanx_calls.log"
printf '[+] 10.0.0.20:22\n'
printf '[+] 10.0.0.21:80\n'
EOF

chmod +x "$MOCK_BIN/sudo" "$MOCK_BIN/zmap" "$MOCK_BIN/masscan" "$MOCK_BIN/fscanx"

export MOCK_CALLS_DIR="$CALLS_DIR"
export PATH="$MOCK_BIN:$PATH"
export ZMAP_EXTRA_ARGS="-G aa:bb:cc:dd:ee:ff -i test0"

bash "$SCRIPT_PATH" > "$TMP_ROOT/stdout.txt"

zmap_call_count="$(wc -l < "$CALLS_DIR/zmap_calls.log" | tr -d ' ')"
if [[ "$zmap_call_count" != "5" ]]; then
  echo "expected 5 zmap calls, got $zmap_call_count" >&2
  exit 1
fi

for port in 22 80 443 445 3389; do
  if ! grep -Eq -- "(^| )-p ${port}( |$)" "$CALLS_DIR/zmap_calls.log"; then
    echo "missing zmap single-port call for $port" >&2
    exit 1
  fi
done

if grep -Fq -- "--no-header-row" "$CALLS_DIR/zmap_calls.log"; then
  echo "zmap should not receive --no-header-row" >&2
  exit 1
fi

extra_args_count="$(grep -Fc -- "-G aa:bb:cc:dd:ee:ff -i test0" "$CALLS_DIR/zmap_calls.log")"
if [[ "$extra_args_count" != "5" ]]; then
  echo "expected ZMAP_EXTRA_ARGS on every zmap call, got $extra_args_count" >&2
  exit 1
fi

if ! grep -Eq '^zmap\|[0-9.]+\|0\|5\|3$' "$BENCH_DIR/summary.txt"; then
  echo "unexpected zmap summary" >&2
  cat "$BENCH_DIR/summary.txt" >&2
  exit 1
fi

echo "run_bench.sh regression test passed"
