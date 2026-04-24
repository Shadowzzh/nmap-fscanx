#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
INSTALL_ROOT="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

# shellcheck disable=SC1091
. "$INSTALL_ROOT/libexec/common.sh"

NMAP_FSCANX_INSTALL_ROOT="$INSTALL_ROOT"
nmap_fscanx_load_config

print_help() {
  cat <<'EOF'
用法：
  nmap-fscanx <run|phase1|phase2|start|attach|check|print-config|version|help> [参数]

子命令：
  run           前台执行完整两阶段扫描
  phase1        前台只执行第一阶段
  phase2        前台只执行第二阶段
  start         使用 tmux 后台启动完整扫描
  attach        进入指定 tmux 会话
  check         检查运行依赖与扫描器配置
  print-config  打印当前生效配置
  version       输出版本
  help          显示帮助

通用参数：
  --scanner <path>         fscanx 二进制路径
  --targets <cidr,...>     目标网段，run 和 phase1 常用
  --phase1-ports <list>    第一阶段端口
  --phase2-ports <range>   第二阶段端口范围
  --threads <number>       并发参数
  --timeout <seconds>      超时秒数
  --scan-root <dir>        扫描输出目录
  --session <name>         tmux 会话名，仅 attach/start 使用

示例：
  nmap-fscanx run --targets '192.168.1.0/24,192.168.20.0/24'
  nmap-fscanx start --targets '192.168.1.0/24,192.168.20.0/24'
  nmap-fscanx attach --session nmap-fscanx-scan-20260424
EOF
}

parse_common_args() {
  CLI_SCANNER=""
  CLI_TARGETS=""
  CLI_PHASE1_PORTS=""
  CLI_PHASE2_PORTS=""
  CLI_THREADS=""
  CLI_TIMEOUT=""
  CLI_SCAN_ROOT=""
  CLI_SESSION=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --scanner)
        CLI_SCANNER="${2:-}"
        shift 2
        ;;
      --targets)
        CLI_TARGETS="${2:-}"
        shift 2
        ;;
      --phase1-ports)
        CLI_PHASE1_PORTS="${2:-}"
        shift 2
        ;;
      --phase2-ports)
        CLI_PHASE2_PORTS="${2:-}"
        shift 2
        ;;
      --threads)
        CLI_THREADS="${2:-}"
        shift 2
        ;;
      --timeout)
        CLI_TIMEOUT="${2:-}"
        shift 2
        ;;
      --scan-root)
        CLI_SCAN_ROOT="${2:-}"
        shift 2
        ;;
      --session)
        CLI_SESSION="${2:-}"
        shift 2
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      *)
        echo "未知参数：$1" >&2
        exit 1
        ;;
    esac
  done
}

build_pipeline_args() {
  local scanner_path="$1"
  local phase1_ports=""
  local phase2_ports=""
  local threads=""
  local timeout_seconds=""
  local scan_base=""
  local scan_root=""

  phase1_ports="$(nmap_fscanx_effective_value "$CLI_PHASE1_PORTS" "${NMAP_FSCANX_PHASE1_PORTS:-22,80,443,445,3389}")"
  phase2_ports="$(nmap_fscanx_effective_value "$CLI_PHASE2_PORTS" "${NMAP_FSCANX_PHASE2_PORTS:-1-65535}")"
  threads="$(nmap_fscanx_effective_value "$CLI_THREADS" "${NMAP_FSCANX_THREADS:-4000}")"
  timeout_seconds="$(nmap_fscanx_effective_value "$CLI_TIMEOUT" "${NMAP_FSCANX_TIMEOUT:-1}")"

  if [[ -n "$CLI_SCAN_ROOT" ]]; then
    scan_root="$CLI_SCAN_ROOT"
  else
    scan_base="$(nmap_fscanx_default_scan_base)"
    scan_root="$(nmap_fscanx_default_scan_root "$scan_base")"
  fi

  PIPELINE_ARGS=(
    --scanner "$scanner_path"
    --phase1-ports "$phase1_ports"
    --phase2-ports "$phase2_ports"
    --threads "$threads"
    --timeout "$timeout_seconds"
    --scan-root "$scan_root"
  )

  if [[ -n "$CLI_TARGETS" ]]; then
    PIPELINE_ARGS+=(--targets "$CLI_TARGETS")
  fi
}

run_pipeline_command() {
  local subcommand="$1"
  local scanner_path=""

  shift
  parse_common_args "$@"

  if ! scanner_path="$(nmap_fscanx_resolve_scanner "$CLI_SCANNER")"; then
    echo "未找到可执行的 fscanx，请用 --scanner 指定路径，或在 config.env 中设置 NMAP_FSCANX_SCANNER" >&2
    exit 1
  fi

  nmap_fscanx_require_command jq
  build_pipeline_args "$scanner_path"

  "$INSTALL_ROOT/libexec/fscanx_pipeline.sh" "$subcommand" "${PIPELINE_ARGS[@]}"
}

print_check_status() {
  local scanner_path=""
  local status_code=0

  echo "INSTALL_ROOT=$INSTALL_ROOT"
  echo "DEFAULT_CONFIG=$INSTALL_ROOT/conf/default.env"
  echo "RUNTIME_CONFIG=$(nmap_fscanx_runtime_config_path)"

  if command -v bash >/dev/null 2>&1; then
    echo "BASH_STATUS=ok"
  else
    echo "BASH_STATUS=missing"
    status_code=1
  fi

  if command -v jq >/dev/null 2>&1; then
    echo "JQ_STATUS=ok"
  else
    echo "JQ_STATUS=missing"
    status_code=1
  fi

  if command -v tmux >/dev/null 2>&1; then
    echo "TMUX_STATUS=ok"
  else
    echo "TMUX_STATUS=missing"
    status_code=1
  fi

  if scanner_path="$(nmap_fscanx_resolve_scanner "${CLI_SCANNER:-}")"; then
    echo "SCANNER_STATUS=ok"
    echo "SCANNER_PATH=$scanner_path"
  else
    echo "SCANNER_STATUS=missing"
    status_code=1
  fi

  return "$status_code"
}

print_effective_config() {
  local scanner_path=""
  local scan_base=""

  parse_common_args "$@"

  scan_base="$(nmap_fscanx_default_scan_base)"

  echo "INSTALL_ROOT=$INSTALL_ROOT"
  echo "RUNTIME_CONFIG=$(nmap_fscanx_runtime_config_path)"
  echo "NMAP_FSCANX_PHASE1_PORTS=$(nmap_fscanx_effective_value "$CLI_PHASE1_PORTS" "${NMAP_FSCANX_PHASE1_PORTS:-22,80,443,445,3389}")"
  echo "NMAP_FSCANX_PHASE2_PORTS=$(nmap_fscanx_effective_value "$CLI_PHASE2_PORTS" "${NMAP_FSCANX_PHASE2_PORTS:-1-65535}")"
  echo "NMAP_FSCANX_THREADS=$(nmap_fscanx_effective_value "$CLI_THREADS" "${NMAP_FSCANX_THREADS:-4000}")"
  echo "NMAP_FSCANX_TIMEOUT=$(nmap_fscanx_effective_value "$CLI_TIMEOUT" "${NMAP_FSCANX_TIMEOUT:-1}")"
  echo "NMAP_FSCANX_SCAN_BASE=$scan_base"
  echo "NMAP_FSCANX_TMUX_PREFIX=${NMAP_FSCANX_TMUX_PREFIX:-nmap-fscanx}"

  if scanner_path="$(nmap_fscanx_resolve_scanner "${CLI_SCANNER:-}")"; then
    echo "NMAP_FSCANX_SCANNER=$scanner_path"
  else
    echo "NMAP_FSCANX_SCANNER="
  fi
}

run_start() {
  local scanner_path=""
  local session_name=""
  local command_string=""
  local prefix=""
  local date_part=""
  local time_part=""
  local scan_root=""

  parse_common_args "$@"
  nmap_fscanx_require_command tmux

  if ! scanner_path="$(nmap_fscanx_resolve_scanner "$CLI_SCANNER")"; then
    echo "未找到可执行的 fscanx，请先配置扫描器路径" >&2
    exit 1
  fi

  nmap_fscanx_require_command jq
  build_pipeline_args "$scanner_path"

  prefix="${NMAP_FSCANX_TMUX_PREFIX:-nmap-fscanx}"
  date_part="$(date '+%Y%m%d')"
  time_part="$(date '+%H%M%S')"
  session_name="$prefix-scan-$date_part"

  if [[ -n "$CLI_SESSION" ]]; then
    session_name="$CLI_SESSION"
  else
    if tmux has-session -t "$session_name" >/dev/null 2>&1; then
      session_name="$prefix-scan-$date_part-$time_part"
    fi
  fi

  scan_root=""
  if [[ -n "$CLI_SCAN_ROOT" ]]; then
    scan_root="$CLI_SCAN_ROOT"
  else
    scan_root="$(nmap_fscanx_default_scan_root "$(nmap_fscanx_default_scan_base)")"
  fi

  command_string="$(nmap_fscanx_shell_quote "$INSTALL_ROOT/libexec/fscanx_pipeline.sh" all "${PIPELINE_ARGS[@]}")"
  tmux new -ds "$session_name" "$command_string"

  echo "SESSION_NAME=$session_name"
  echo "ATTACH_COMMAND=tmux attach -t $session_name"
  echo "SCAN_ROOT=$scan_root"
  echo "FINAL_REPORT=$scan_root/report.json"
}

run_attach() {
  parse_common_args "$@"
  nmap_fscanx_require_command tmux

  if [[ -z "$CLI_SESSION" ]]; then
    echo "attach 需要 --session <name>" >&2
    exit 1
  fi

  tmux attach -t "$CLI_SESSION"
}

run_version() {
  if [[ -f "$INSTALL_ROOT/VERSION" ]]; then
    cat "$INSTALL_ROOT/VERSION"
    return 0
  fi

  echo "dev"
}

COMMAND="${1:-help}"

if [[ $# -gt 0 ]]; then
  shift
fi

case "$COMMAND" in
  run)
    run_pipeline_command all "$@"
    ;;
  phase1)
    run_pipeline_command phase1 "$@"
    ;;
  phase2)
    run_pipeline_command phase2 "$@"
    ;;
  start)
    run_start "$@"
    ;;
  attach)
    run_attach "$@"
    ;;
  check)
    parse_common_args "$@"
    print_check_status
    ;;
  print-config)
    print_effective_config "$@"
    ;;
  version)
    run_version
    ;;
  help|-h|--help)
    print_help
    ;;
  *)
    echo "未知子命令：$COMMAND" >&2
    print_help >&2
    exit 1
    ;;
esac
