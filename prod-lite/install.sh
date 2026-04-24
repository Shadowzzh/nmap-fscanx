#!/usr/bin/env bash

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
  SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  if [[ "$SCRIPT_PATH" != /* ]]; then
    SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
  fi
done

PACKAGE_ROOT="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
INSTALL_DEPS=0
SYSTEM_INSTALL=0
FORCE_INSTALL=0
CUSTOM_PREFIX=""
SCANNER_PATH=""

print_help() {
  cat <<'EOF'
用法：
  bash install.sh [--install-deps] [--system] [--scanner <path>] [--prefix <dir>] [--force]

说明：
  1. 如果传了 --scanner，优先使用该路径。
  2. 如果系统里已有 fscanx，优先复用现有命令。
  3. 如果安装包同级目录存在 fscanx-bundle，会自动按 Linux 架构选择内置二进制。
EOF
}

fail() {
  echo "$*" >&2
  exit 1
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt-get"
    return 0
  fi

  if command -v dnf >/dev/null 2>&1; then
    echo "dnf"
    return 0
  fi

  if command -v yum >/dev/null 2>&1; then
    echo "yum"
    return 0
  fi

  return 1
}

check_dependency() {
  local name="$1"

  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

detect_bundle_binary_name() {
  local system_name=""
  local machine_name=""

  system_name="$(uname -s)"
  machine_name="$(uname -m)"

  if [[ "$system_name" != "Linux" ]]; then
    return 1
  fi

  case "$machine_name" in
    x86_64|amd64)
      printf 'fscanx-linux-amd64\n'
      ;;
    aarch64|arm64)
      printf 'fscanx-linux-arm64\n'
      ;;
    armv7l|armhf)
      printf 'fscanx-linux-armv7\n'
      ;;
    *)
      return 1
      ;;
  esac
}

find_bundle_dir() {
  local candidate=""

  for candidate in \
    "$PACKAGE_ROOT/fscanx-bundle" \
    "$PACKAGE_ROOT/../fscanx-bundle"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

resolve_bundle_scanner() {
  local bundle_dir=""
  local bundle_binary=""
  local candidate=""

  if ! bundle_dir="$(find_bundle_dir)"; then
    return 1
  fi

  if ! bundle_binary="$(detect_bundle_binary_name)"; then
    return 1
  fi

  candidate="$bundle_dir/$bundle_binary"
  if [[ ! -x "$candidate" ]]; then
    return 1
  fi

  printf '%s\n' "$candidate"
}

resolve_scanner_path() {
  if [[ -n "$SCANNER_PATH" ]]; then
    if [[ -x "$SCANNER_PATH" ]]; then
      printf '%s\n' "$SCANNER_PATH"
      return 0
    fi

    return 1
  fi

  if command -v fscanx >/dev/null 2>&1; then
    command -v fscanx
    return 0
  fi

  if resolve_bundle_scanner >/dev/null 2>&1; then
    resolve_bundle_scanner
    return 0
  fi

  return 1
}

install_bundle_scanner_if_needed() {
  local install_root="$1"
  local resolved_scanner="$2"
  local bundle_dir=""
  local installed_scanner=""

  if ! bundle_dir="$(find_bundle_dir)"; then
    return 0
  fi

  case "$resolved_scanner" in
    "$bundle_dir"/*)
      installed_scanner="$install_root/bin/fscanx"
      cp "$resolved_scanner" "$installed_scanner"
      chmod +x "$installed_scanner"
      SCANNER_PATH="$installed_scanner"
      ;;
  esac
}

try_install_dependencies() {
  local manager=""
  local missing=()

  if ! check_dependency jq; then
    missing+=(jq)
  fi

  if ! check_dependency tmux; then
    missing+=(tmux)
  fi

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  if [[ "$INSTALL_DEPS" -ne 1 ]]; then
    return 0
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    echo "未自动安装依赖：当前不是 root，请自行安装 ${missing[*]}" >&2
    return 0
  fi

  if ! manager="$(detect_package_manager)"; then
    echo "未自动安装依赖：无法识别包管理器，请自行安装 ${missing[*]}" >&2
    return 0
  fi

  case "$manager" in
    apt-get)
      apt-get update
      apt-get install -y "${missing[@]}"
      ;;
    dnf)
      dnf install -y "${missing[@]}"
      ;;
    yum)
      yum install -y "${missing[@]}"
      ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install-deps)
        INSTALL_DEPS=1
        shift
        ;;
      --system)
        SYSTEM_INSTALL=1
        shift
        ;;
      --scanner)
        SCANNER_PATH="${2:-}"
        shift 2
        ;;
      --prefix)
        CUSTOM_PREFIX="${2:-}"
        shift 2
        ;;
      --force)
        FORCE_INSTALL=1
        shift
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

write_runtime_config() {
  local config_file="$1"
  local config_dir=""

  config_dir="$(dirname "$config_file")"
  mkdir -p "$config_dir"

  if [[ -f "$config_file" ]]; then
    return 0
  fi

  {
    echo "# Runtime config for nmap-fscanx"
    if [[ -n "$SCANNER_PATH" ]]; then
      printf 'NMAP_FSCANX_SCANNER=%q\n' "$SCANNER_PATH"
    else
      echo "# NMAP_FSCANX_SCANNER=/path/to/fscanx"
    fi
    echo "# NMAP_FSCANX_SCAN_BASE=/path/to/scans"
  } > "$config_file"
}

main() {
  local install_root=""
  local command_link=""
  local runtime_config=""
  local command_dir=""
  local source_path=""
  local source_name=""
  local resolved_scanner=""

  parse_args "$@"
  try_install_dependencies

  if [[ -n "$SCANNER_PATH" && ! -x "$SCANNER_PATH" ]]; then
    fail "scanner 不存在或不可执行：$SCANNER_PATH"
  fi

  if [[ -n "$CUSTOM_PREFIX" ]]; then
    install_root="$CUSTOM_PREFIX/nmap-fscanx"
    command_link="$CUSTOM_PREFIX/bin/nmap-fscanx"
    runtime_config="$CUSTOM_PREFIX/etc/nmap-fscanx/config.env"
  else
    if [[ "$SYSTEM_INSTALL" -eq 1 || "$(id -u)" -eq 0 ]]; then
      install_root="/opt/nmap-fscanx"
      command_link="/usr/local/bin/nmap-fscanx"
      runtime_config="/etc/nmap-fscanx/config.env"
    else
      install_root="$HOME/.local/nmap-fscanx"
      command_link="$HOME/.local/bin/nmap-fscanx"
      runtime_config="$HOME/.config/nmap-fscanx/config.env"
    fi
  fi

  if [[ -e "$install_root" && "$FORCE_INSTALL" -ne 1 ]]; then
    fail "安装目录已存在，请使用 --force 覆盖：$install_root"
  fi

  if [[ -e "$install_root" ]]; then
    rm -rf "$install_root"
  fi

  mkdir -p "$install_root"

  for source_name in README.md Makefile bin libexec conf examples docs VERSION MANIFEST.txt RELEASE_NOTES.md uninstall.sh; do
    source_path="$PACKAGE_ROOT/$source_name"
    if [[ -e "$source_path" ]]; then
      cp -R "$source_path" "$install_root/"
    fi
  done

  cp "$PACKAGE_ROOT/install.sh" "$install_root/install.sh"

  chmod +x \
    "$install_root/bin/nmap-fscanx" \
    "$install_root/libexec/fscanx_pipeline.sh" \
    "$install_root/libexec/nmap-fscanx-entry.sh" \
    "$install_root/install.sh" \
    "$install_root/uninstall.sh" \
    "$install_root/examples/run-all.example.sh" \
    "$install_root/examples/run-phase1.example.sh" \
    "$install_root/examples/run-phase2.example.sh"

  command_dir="$(dirname "$command_link")"
  mkdir -p "$command_dir"
  rm -f "$command_link"
  ln -s "$install_root/bin/nmap-fscanx" "$command_link"

  if resolved_scanner="$(resolve_scanner_path)"; then
    SCANNER_PATH="$resolved_scanner"
    install_bundle_scanner_if_needed "$install_root" "$resolved_scanner"
  else
    SCANNER_PATH=""
  fi

  write_runtime_config "$runtime_config"

  {
    printf 'NMAP_FSCANX_INSTALL_ROOT=%q\n' "$install_root"
    printf 'NMAP_FSCANX_BIN_LINK=%q\n' "$command_link"
    printf 'NMAP_FSCANX_RUNTIME_CONFIG=%q\n' "$runtime_config"
  } > "$install_root/conf/install.env"

  echo "INSTALL_ROOT=$install_root"
  echo "COMMAND_LINK=$command_link"
  echo "RUNTIME_CONFIG=$runtime_config"
  if [[ -n "$SCANNER_PATH" ]]; then
    echo "SCANNER_PATH=$SCANNER_PATH"
  else
    echo "SCANNER_PATH=not-configured"
  fi
  echo "NEXT=nmap-fscanx check"
}

main "$@"
