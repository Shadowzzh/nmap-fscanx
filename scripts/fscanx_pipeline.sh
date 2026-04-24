#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
COMMAND="${1:-}"

SCANNER="/tmp/fscanx-bin/fscanx"
TARGETS=""
PHASE1_PORTS="22,80,443,445,3389"
PHASE2_PORTS="1-65535"
THREADS="4000"
TIMEOUT_SECONDS="1"
SCAN_ROOT=""

display_command() {
  printf '%s\n' "${NMAP_FSCANX_DISPLAY_COMMAND:-$COMMAND}"
}

print_help() {
  cat <<'EOF'
用法：
  fscanx_pipeline.sh <phase1|phase2|all> [参数]
  fscanx_pipeline.sh -h

说明：
  这是一个两阶段的 fscanx 扫描脚本。
  第一阶段使用重点端口快速筛选存活主机。
  第二阶段读取第一阶段输出的存活 IP 文件，对这些 IP 扫描全部端口。
  最终输出标准 JSON 报告，以及每个阶段的审计文件。

子命令：
  phase1    只执行第一阶段，输出存活 IP
  phase2    只执行第二阶段，读取 phase1/alive_ips.txt 扫描全部端口
  all       依次执行第一阶段、第二阶段，并生成最终报告

参数：
  --scanner <path>         fscanx 二进制路径，默认 /tmp/fscanx-bin/fscanx
  --targets <cidr,...>     扫描目标，phase1 和 all 必填
  --phase1-ports <list>    第一阶段端口，默认 22,80,443,445,3389
  --phase2-ports <range>   第二阶段端口范围，默认 1-65535
  --threads <number>       fscanx 并发参数 -t，默认 4000
  --timeout <seconds>      fscanx 超时参数 -time，默认 1
  --scan-root <dir>        输出目录，默认 scans/YYYYMMDD-fscanx
  -h, --help               显示帮助

运行流程：
  1. 创建扫描根目录，并写入 input.json 保存本次参数。
  2. 进入 phase1 目录执行 fscanx，避免结果文件落到错误目录。
  3. 将 phase1/result.txt 归一化为标准 JSON 数组。
  4. 只提取 type=Port 的记录，从中去重得到 phase1/alive_ips.txt。
  5. 进入 phase2 目录，用 -hf ../phase1/alive_ips.txt 扫描全部端口。
  6. 将 phase2/result.txt 归一化为标准 JSON 数组。
  7. 只提取 type=Port 的记录，从中去重得到 phase2/open_ip_port.txt。
  8. 基于 Port、Product、OsInfo 生成 phase2/assets.csv。
  9. 汇总 phase1 和 phase2 的统计信息，生成最终 report.json。

输出文件：
  <scan-root>/input.json
  <scan-root>/phase1/console.log
  <scan-root>/phase1/result.txt
  <scan-root>/phase1/normalized.json
  <scan-root>/phase1/alive_ips.txt
  <scan-root>/phase1/phase1.summary.json
  <scan-root>/phase2/console.log
  <scan-root>/phase2/result.txt
  <scan-root>/phase2/normalized.json
  <scan-root>/phase2/open_ip_port.txt
  <scan-root>/phase2/assets.csv
  <scan-root>/phase2/phase2.summary.json
  <scan-root>/report.json

案例：
  1. 执行完整两阶段扫描
     bash scripts/fscanx_pipeline.sh all \
       --scanner /tmp/fscanx-bin/fscanx \
       --targets '192.168.1.0/24,192.168.20.0/24,192.168.4.0/24' \
       --phase1-ports '22,80,443,445,3389' \
       --phase2-ports '1-65535' \
       --threads 4000 \
       --timeout 1 \
       --scan-root scans/20260424-fscanx

  2. 只重跑第二阶段
     bash scripts/fscanx_pipeline.sh phase2 \
       --scanner /tmp/fscanx-bin/fscanx \
       --phase2-ports '1-65535' \
       --threads 4000 \
       --timeout 1 \
       --scan-root scans/20260424-fscanx

  3. 使用 tmux 后台执行完整流程
     tmux new -ds nmap-fscanx-20260424 \
       "bash scripts/fscanx_pipeline.sh all \
         --scanner /tmp/fscanx-bin/fscanx \
         --targets '192.168.1.0/24,192.168.20.0/24,192.168.4.0/24' \
         --phase1-ports '22,80,443,445,3389' \
         --phase2-ports '1-65535' \
         --threads 4000 \
         --timeout 1 \
         --scan-root scans/20260424-fscanx"
EOF
}

fail() {
  echo "$*" >&2
  exit 1
}

timestamp_now() {
  date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'
}

default_scan_root() {
  date '+scans/%Y%m%d-fscanx'
}

ensure_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    fail "缺少依赖命令：$name"
  fi
}

ensure_scanner() {
  if [[ ! -x "$SCANNER" ]]; then
    fail "fscanx 二进制不存在或不可执行：$SCANNER"
  fi
}

ensure_scan_root() {
  if [[ -z "$SCAN_ROOT" ]]; then
    SCAN_ROOT="$(default_scan_root)"
  fi
  mkdir -p "$SCAN_ROOT"
}

targets_json() {
  printf '%s' "$TARGETS" | jq -Rsc 'if . == "" then [] else split(",") | map(select(length > 0)) end'
}

count_lines() {
  local file="$1"

  awk 'END { print NR }' "$file"
}

preview_lines() {
  local file="$1"
  local limit="${2:-20}"

  head -n "$limit" "$file" | paste -sd ',' -
}

print_command_header() {
  echo "COMMAND=$(display_command)"
  echo "SCAN_ROOT=$SCAN_ROOT"
  echo "SCANNER=$SCANNER"

  if [[ -n "$TARGETS" ]]; then
    echo "TARGETS=$TARGETS"
  fi
}

print_phase_start() {
  local phase_name="$1"
  local console_log="$2"
  local result_file="$3"
  local input_file="${4:-}"

  echo "PHASE_START=$phase_name"
  echo "CONSOLE_LOG=$console_log"
  echo "RESULT_FILE=$result_file"

  if [[ -n "$input_file" ]]; then
    echo "PHASE_INPUT_FILE=$input_file"
  fi
}

print_phase_done() {
  local phase_name="$1"

  echo "PHASE_DONE=$phase_name"
}

normalize_result_file() {
  local raw_file="$1"
  local normalized_file="$2"

  if [[ ! -f "$raw_file" ]]; then
    fail "扫描结果文件不存在：$raw_file"
  fi

  awk '
    NF {
      line = $0
      sub(/,[[:space:]]*$/, "", line)
      lines[++count] = line
    }
    END {
      print "["
      for (i = 1; i <= count; i++) {
        suffix = ""
        if (i < count) {
          suffix = ","
        }
        print lines[i] suffix
      }
      print "]"
    }
  ' "$raw_file" > "$normalized_file"

  jq empty "$normalized_file" >/dev/null
}

write_input_json() {
  local input_file="$1"
  local targets_arg="$2"

  jq -n \
    --arg generated_at "$(timestamp_now)" \
    --arg command "$COMMAND" \
    --arg scanner "$SCANNER" \
    --arg targets "$targets_arg" \
    --arg phase1_ports "$PHASE1_PORTS" \
    --arg phase2_ports "$PHASE2_PORTS" \
    --arg threads "$THREADS" \
    --arg timeout_seconds "$TIMEOUT_SECONDS" \
    '{
      generated_at: $generated_at,
      command: $command,
      scanner: $scanner,
      targets: ($targets | if . == "" then [] else split(",") | map(select(length > 0)) end),
      phase1_ports: ($phase1_ports | split(",") | map(tonumber)),
      phase2_ports: $phase2_ports,
      threads: ($threads | tonumber),
      timeout_seconds: ($timeout_seconds | tonumber)
    }' > "$input_file"
}

resolve_targets_from_input() {
  local input_file="$1"

  if [[ -n "$TARGETS" ]]; then
    return 0
  fi

  if [[ -f "$input_file" ]]; then
    TARGETS="$(jq -r '.targets | join(",")' "$input_file")"
  fi
}

extract_alive_ips() {
  local normalized_file="$1"
  local output_file="$2"

  jq -r '
    .[]
    | select(.type == "Port")
    | try (.text | capture("open\\t(?<ip>[0-9.]+):(?<port>[0-9]+)").ip) catch empty
  ' "$normalized_file" | awk 'NF && !seen[$0]++' > "$output_file"
}

extract_open_ip_ports() {
  local normalized_file="$1"
  local output_file="$2"

  jq -r '
    .[]
    | select(.type == "Port")
    | try (.text | capture("open\\t(?<ip>[0-9.]+):(?<port>[0-9]+)") | "\(.ip):\(.port)") catch empty
  ' "$normalized_file" | awk 'NF && !seen[$0]++' > "$output_file"
}

write_phase2_assets_csv() {
  local normalized_file="$1"
  local csv_file="$2"

  jq -r '
    def trim_space:
      sub("^[[:space:]]+"; "")
      | sub("[[:space:]]+$"; "");

    def clean_text:
      gsub("\r"; "")
      | gsub("\n"; "");

    def unique_strings:
      map(select(type == "string" and length > 0))
      | unique;

    def parse_port_record:
      try (.text | capture("open\\t(?<ip>[0-9.]+):(?<port>[0-9]+)")) catch empty;

    def parse_os_record:
      try (
        .text
        | clean_text
        | capture("^(?<ip>[0-9.]+)\\t(?<hint>.*)$")
        | .hint |= trim_space
      ) catch empty;

    def parse_product_record:
      try (
        (.text | clean_text | split("\t")) as $fields
        | ($fields[0] // "") as $url
        | ($fields[2] // "") as $title
        | ($fields[3] // "") as $evidence
        | ($url | capture("^(?<scheme>https?)://(?<ip>[0-9.]+)(?::(?<port>[0-9]+))?(?<path>/.*)?$")) as $parsed_url
        | ($evidence | [match("\\[[^\\]]+\\]"; "g").string | .[1:-1] | trim_space]) as $items
        | {
            ip: $parsed_url.ip,
            port: ($parsed_url.port // (if $parsed_url.scheme == "https" then "443" else "80" end)),
            url: $url,
            title: (
              if $title == "" or $title == "(None)" then ""
              else $title
              end
            ),
            fingerprints: (
              $items
              | map(select(startswith("Cert:") | not))
              | map(select(startswith("From:") | not))
              | unique_strings
            ),
            cert_info: (
              $items
              | map(select(startswith("Cert:")))
              | unique_strings
            )
          }
      ) catch empty;

    ([
      .[]
      | select(.type == "Port")
      | parse_port_record
    ] | unique_by(.ip + ":" + .port) | sort_by(.ip, (.port | tonumber))) as $rows
    |
    (reduce (
      [
        .[]
        | select(.type == "OsInfo")
        | parse_os_record
      ][]
    ) as $entry ({}; .[$entry.ip] = ((.[$entry.ip] // []) + [$entry.hint]))) as $os_map
    |
    ([
      .[]
      | select(.type == "Product")
      | parse_product_record
    ]) as $products
    |
    ([
      ["ip", "port", "os_hint", "urls", "titles", "fingerprints", "cert_info"]
    ] + [
      $rows[] as $row
      | ($products | map(select(.ip == $row.ip and .port == $row.port))) as $product_matches
      | [
          $row.ip,
          $row.port,
          (($os_map[$row.ip] // []) | unique_strings | join(" | ")),
          ($product_matches | map(.url) | unique_strings | tojson),
          ($product_matches | map(.title) | unique_strings | tojson),
          ([ $product_matches[]?.fingerprints[]? ] | unique_strings | tojson),
          ([ $product_matches[]?.cert_info[]? ] | unique_strings | tojson)
        ]
    ])
    | .[]
    | @csv
  ' "$normalized_file" > "$csv_file"
}

run_scanner_in_dir() {
  local workdir="$1"
  shift

  mkdir -p "$workdir"
  rm -f "$workdir/result.txt"

  (
    cd "$workdir"
    "$SCANNER" "$@" 2>&1 | tee console.log
  )

  if [[ ! -f "$workdir/result.txt" ]]; then
    fail "fscanx 执行后未生成 result.txt：$workdir"
  fi
}

write_phase1_summary() {
  local summary_file="$1"
  local alive_file="$2"
  local alive_count=""

  alive_count="$(count_lines "$alive_file")"

  jq -n \
    --arg generated_at "$(timestamp_now)" \
    --arg scanner "$SCANNER" \
    --argjson targets "$(targets_json)" \
    --argjson alive_ip_count "$alive_count" \
    --arg phase1_ports "$PHASE1_PORTS" \
    '{
      generated_at: $generated_at,
      phase: "phase1",
      scanner: $scanner,
      targets: $targets,
      ports: ($phase1_ports | split(",") | map(tonumber)),
      alive_ip_count: $alive_ip_count,
      alive_ips_file: "phase1/alive_ips.txt"
    }' > "$summary_file"
}

write_phase2_summary() {
  local summary_file="$1"
  local assets_file="$2"
  local assets_csv_file="$3"
  local asset_count=""

  asset_count="$(count_lines "$assets_file")"

  jq -n \
    --arg generated_at "$(timestamp_now)" \
    --arg scanner "$SCANNER" \
    --argjson open_ip_port_count "$asset_count" \
    --arg phase2_ports "$PHASE2_PORTS" \
    --arg assets_csv_file "$assets_csv_file" \
    '{
      generated_at: $generated_at,
      phase: "phase2",
      scanner: $scanner,
      port_range: $phase2_ports,
      open_ip_port_count: $open_ip_port_count,
      open_ip_port_file: "phase2/open_ip_port.txt",
      assets_csv_file: $assets_csv_file
    }' > "$summary_file"
}

write_report() {
  local phase1_summary="$1"
  local phase2_summary="$2"
  local report_file="$3"

  jq -n \
    --arg generated_at "$(timestamp_now)" \
    --slurpfile phase1 "$phase1_summary" \
    --slurpfile phase2 "$phase2_summary" \
    '{
      generated_at: $generated_at,
      scanner: $phase1[0].scanner,
      targets: $phase1[0].targets,
      phase1: {
        ports: $phase1[0].ports,
        alive_ip_count: $phase1[0].alive_ip_count,
        alive_ips_file: $phase1[0].alive_ips_file
      },
      phase2: {
        port_range: $phase2[0].port_range,
        open_ip_port_count: $phase2[0].open_ip_port_count,
        open_ip_port_file: $phase2[0].open_ip_port_file,
        assets_csv_file: $phase2[0].assets_csv_file
      }
    }' > "$report_file"
}

clear_phase2_outputs() {
  rm -rf "$SCAN_ROOT/phase2"
  rm -f "$SCAN_ROOT/report.json"
}

print_phase1_output() {
  local summary_file="$1"
  local alive_file="$2"
  local alive_count=""
  local alive_preview=""

  alive_count="$(count_lines "$alive_file")"
  alive_preview="$(preview_lines "$alive_file")"

  echo "PHASE1_SUMMARY=$summary_file"
  echo "ALIVE_IP_COUNT=$alive_count"
  echo "ALIVE_IP_FILE=$alive_file"

  if [[ -n "$alive_preview" ]]; then
    echo "ALIVE_IP_PREVIEW=$alive_preview"
  fi
}

print_phase2_output() {
  local summary_file="$1"
  local assets_file="$2"
  local assets_csv_file="$3"
  local asset_count=""

  asset_count="$(count_lines "$assets_file")"

  echo "PHASE2_SUMMARY=$summary_file"
  echo "OPEN_IP_PORT_COUNT=$asset_count"
  echo "OPEN_IP_PORT_FILE=$assets_file"
  echo "ASSETS_CSV_FILE=$assets_csv_file"
}

run_phase1() {
  local phase1_dir="$SCAN_ROOT/phase1"
  local normalized_file="$phase1_dir/normalized.json"
  local alive_file="$phase1_dir/alive_ips.txt"
  local summary_file="$phase1_dir/phase1.summary.json"

  if [[ -z "$TARGETS" ]]; then
    fail "phase1 和 all 必须提供 --targets"
  fi

  clear_phase2_outputs
  print_phase_start "phase1" "$phase1_dir/console.log" "$phase1_dir/result.txt"
  run_scanner_in_dir "$phase1_dir" \
    -h "$TARGETS" \
    -p "$PHASE1_PORTS" \
    -np \
    -t "$THREADS" \
    -time "$TIMEOUT_SECONDS" \
    -nocolor \
    -json

  normalize_result_file "$phase1_dir/result.txt" "$normalized_file"
  extract_alive_ips "$normalized_file" "$alive_file"
  write_phase1_summary "$summary_file" "$alive_file"
  print_phase_done "phase1"
  print_phase1_output "$summary_file" "$alive_file"
}

run_phase2() {
  local phase1_dir="$SCAN_ROOT/phase1"
  local phase2_dir="$SCAN_ROOT/phase2"
  local alive_file="$phase1_dir/alive_ips.txt"
  local normalized_file="$phase2_dir/normalized.json"
  local assets_file="$phase2_dir/open_ip_port.txt"
  local assets_csv_file="$phase2_dir/assets.csv"
  local summary_file="$phase2_dir/phase2.summary.json"

  if [[ ! -f "$alive_file" ]]; then
    fail "phase2 需要先存在 $alive_file"
  fi

  mkdir -p "$phase2_dir"
  print_phase_start "phase2" "$phase2_dir/console.log" "$phase2_dir/result.txt" "$alive_file"

  if [[ ! -s "$alive_file" ]]; then
    : > "$assets_file"
    printf '[]\n' > "$normalized_file"
    write_phase2_assets_csv "$normalized_file" "$assets_csv_file"
    printf 'phase1 没有存活 IP，跳过 phase2 扫描\n' | tee "$phase2_dir/console.log"
    write_phase2_summary "$summary_file" "$assets_file" "phase2/assets.csv"
    write_report "$phase1_dir/phase1.summary.json" "$summary_file" "$SCAN_ROOT/report.json"
    print_phase_done "phase2"
    print_phase2_output "$summary_file" "$assets_file" "$assets_csv_file"
    return 0
  fi

  run_scanner_in_dir "$phase2_dir" \
    -hf "../phase1/alive_ips.txt" \
    -p "$PHASE2_PORTS" \
    -np \
    -t "$THREADS" \
    -time "$TIMEOUT_SECONDS" \
    -nocolor \
    -json

  normalize_result_file "$phase2_dir/result.txt" "$normalized_file"
  extract_open_ip_ports "$normalized_file" "$assets_file"
  write_phase2_assets_csv "$normalized_file" "$assets_csv_file"
  write_phase2_summary "$summary_file" "$assets_file" "phase2/assets.csv"
  write_report "$phase1_dir/phase1.summary.json" "$summary_file" "$SCAN_ROOT/report.json"
  print_phase_done "phase2"
  print_phase2_output "$summary_file" "$assets_file" "$assets_csv_file"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scanner)
        SCANNER="$2"
        shift 2
        ;;
      --targets)
        TARGETS="$2"
        shift 2
        ;;
      --phase1-ports)
        PHASE1_PORTS="$2"
        shift 2
        ;;
      --phase2-ports)
        PHASE2_PORTS="$2"
        shift 2
        ;;
      --threads)
        THREADS="$2"
        shift 2
        ;;
      --timeout)
        TIMEOUT_SECONDS="$2"
        shift 2
        ;;
      --scan-root)
        SCAN_ROOT="$2"
        shift 2
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      *)
        fail "未知参数：$1"
        ;;
    esac
  done
}

main() {
  ensure_command jq

  if [[ -z "$COMMAND" || "$COMMAND" == "-h" || "$COMMAND" == "--help" ]]; then
    print_help
    exit 0
  fi

  shift
  parse_args "$@"
  ensure_scanner
  ensure_scan_root

  resolve_targets_from_input "$SCAN_ROOT/input.json"
  write_input_json "$SCAN_ROOT/input.json" "$TARGETS"
  print_command_header

  case "$COMMAND" in
    phase1)
      run_phase1
      ;;
    phase2)
      run_phase2
      ;;
    all)
      run_phase1
      run_phase2
      ;;
    *)
      fail "未知子命令：$COMMAND"
      ;;
  esac

  case "$COMMAND" in
    phase2|all)
      if [[ -f "$SCAN_ROOT/report.json" ]]; then
        echo "FINAL_REPORT=$SCAN_ROOT/report.json"
      fi
      ;;
  esac
}

main "$@"
