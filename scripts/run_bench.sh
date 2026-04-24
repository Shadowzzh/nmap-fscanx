#!/usr/bin/env bash

set -u

DIR=/tmp/scan-bench
TARGETS_TXT="$DIR/targets.txt"
TARGETS_CIDRS="$DIR/targets.cidrs"
EMPTY_BLOCKLIST="$DIR/empty.blocklist"
PORTS="22,80,443,445,3389"
ZMAP_EXTRA_ARGS="${ZMAP_EXTRA_ARGS:-}"

IFS=, read -r -a PORT_LIST <<< "$PORTS"
read -r -a ZMAP_EXTRA_ARGS_LIST <<< "$ZMAP_EXTRA_ARGS"

mkdir -p "$DIR"
: > "$EMPTY_BLOCKLIST"

run_tool() {
  local name="$1"
  local outfile="$2"
  shift 2

  {
    echo "# tool: $name"
    echo "# started_at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# command: $*"
    /usr/bin/time -p "$@"
    local exit_code=$?
    echo "# exit_code: $exit_code"
    echo "# ended_at: $(date '+%Y-%m-%d %H:%M:%S')"
  } > "$outfile" 2>&1
}

extract_real() {
  local file="$1"
  awk '$1 == "real" { value = $2 } END { print value + 0 }' "$file"
}

extract_exit() {
  local file="$1"
  awk -F': ' '/^# exit_code:/ { value = $2 } END { print value + 0 }' "$file"
}

sum_real() {
  awk '$1 == "real" { total += $2 } END { print total + 0 }' "$@"
}

aggregate_exit() {
  awk -F': ' '
    /^# exit_code:/ && $2 != 0 { bad = 1 }
    END { print bad + 0 }
  ' "$@"
}

count_zmap_rows() {
  local file="$1"
  grep -Ec '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+,[0-9]+,' "$file" || true
}

count_zmap_hosts() {
  local file="$1"
  awk -F, '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+,[0-9]+,/ { print $1 }' "$file" | sort -u | wc -l | tr -d ' '
}

count_masscan_rows() {
  local file="$1"
  grep -Ec '^Discovered open port ' "$file" || true
}

count_masscan_hosts() {
  local file="$1"
  awk '/^Discovered open port / { print $NF }' "$file" | sort -u | wc -l | tr -d ' '
}

count_fscanx_rows() {
  local file="$1"
  grep -Ec '^\[\+\] ' "$file" || true
}

count_fscanx_hosts() {
  local file="$1"
  grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' "$file" | sort -u | wc -l | tr -d ' '
}

: > "$DIR/zmap.txt"

for port in "${PORT_LIST[@]}"; do
  local_zmap_file="$DIR/zmap-port-${port}.txt"

  run_tool "zmap:$port" "$local_zmap_file" \
    sudo -n zmap \
    -M tcp_synscan \
    -p "$port" \
    -w "$TARGETS_CIDRS" \
    -b "$EMPTY_BLOCKLIST" \
    -r 100000 \
    -c 1 \
    -q \
    -O csv \
    -f saddr,sport,classification,success,repeat \
    --output-filter='success = 1 && repeat = 0' \
    "${ZMAP_EXTRA_ARGS_LIST[@]}"

  {
    echo "# zmap_port: $port"
    cat "$local_zmap_file"
    echo
  } >> "$DIR/zmap.txt"
done

run_tool "masscan" \
  "$DIR/masscan.txt" \
  sudo -n masscan \
  -iL "$TARGETS_TXT" \
  -p"$PORTS" \
  --rate 100000 \
  --wait 1

run_tool "fscanx" \
  "$DIR/fscanx.txt" \
  /tmp/fscanx-bin/fscanx \
  -hf "$TARGETS_TXT" \
  -p "$PORTS" \
  -np \
  -t 4000 \
  -time 1 \
  -nocolor \
  -no

{
  echo "tool|real_seconds|exit_code|result_rows|unique_hosts"
  echo "zmap|$(sum_real "$DIR"/zmap-port-*.txt)|$(aggregate_exit "$DIR"/zmap-port-*.txt)|$(count_zmap_rows "$DIR/zmap.txt")|$(count_zmap_hosts "$DIR/zmap.txt")"
  echo "masscan|$(extract_real "$DIR/masscan.txt")|$(extract_exit "$DIR/masscan.txt")|$(count_masscan_rows "$DIR/masscan.txt")|$(count_masscan_hosts "$DIR/masscan.txt")"
  echo "fscanx|$(extract_real "$DIR/fscanx.txt")|$(extract_exit "$DIR/fscanx.txt")|$(count_fscanx_rows "$DIR/fscanx.txt")|$(count_fscanx_hosts "$DIR/fscanx.txt")"
} > "$DIR/summary.txt"

cat "$DIR/summary.txt"
