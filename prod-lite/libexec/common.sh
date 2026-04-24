#!/usr/bin/env bash

nmap_fscanx_resolve_path() {
  local target="$1"
  local dir=""

  while [[ -L "$target" ]]; do
    dir="$(cd -P "$(dirname "$target")" && pwd)"
    target="$(readlink "$target")"
    if [[ "$target" != /* ]]; then
      target="$dir/$target"
    fi
  done

  dir="$(cd -P "$(dirname "$target")" && pwd)"
  printf '%s/%s\n' "$dir" "$(basename "$target")"
}

nmap_fscanx_source_if_exists() {
  local file="$1"

  if [[ -f "$file" ]]; then
    # shellcheck disable=SC1090
    . "$file"
  fi
}

nmap_fscanx_is_system_install() {
  if [[ "${NMAP_FSCANX_INSTALL_ROOT:-}" == "/opt/nmap-fscanx" ]]; then
    return 0
  fi

  return 1
}

nmap_fscanx_runtime_config_path() {
  if [[ -n "${NMAP_FSCANX_RUNTIME_CONFIG:-}" ]]; then
    printf '%s\n' "$NMAP_FSCANX_RUNTIME_CONFIG"
    return 0
  fi

  if nmap_fscanx_is_system_install; then
    printf '/etc/nmap-fscanx/config.env\n'
    return 0
  fi

  printf '%s/.config/nmap-fscanx/config.env\n' "$HOME"
}

nmap_fscanx_load_config() {
  local install_env="$NMAP_FSCANX_INSTALL_ROOT/conf/install.env"
  local default_env="$NMAP_FSCANX_INSTALL_ROOT/conf/default.env"

  nmap_fscanx_source_if_exists "$install_env"
  nmap_fscanx_source_if_exists "$default_env"

  NMAP_FSCANX_RUNTIME_CONFIG="$(nmap_fscanx_runtime_config_path)"
  nmap_fscanx_source_if_exists "$NMAP_FSCANX_RUNTIME_CONFIG"
}

nmap_fscanx_default_scan_base() {
  local current_dir=""

  if [[ -n "${NMAP_FSCANX_SCAN_BASE:-}" ]]; then
    printf '%s\n' "$NMAP_FSCANX_SCAN_BASE"
    return 0
  fi

  current_dir="$(pwd -P)"
  printf '%s/scans\n' "$current_dir"
}

nmap_fscanx_default_scan_root() {
  local base_dir="$1"
  local date_part=""

  date_part="$(date '+%Y%m%d')"
  printf '%s/%s-fscanx\n' "$base_dir" "$date_part"
}

nmap_fscanx_resolve_scanner() {
  local override="${1:-}"

  if [[ -n "$override" ]]; then
    if [[ -x "$override" ]]; then
      printf '%s\n' "$override"
      return 0
    fi

    return 1
  fi

  if [[ -n "${NMAP_FSCANX_SCANNER:-}" && -x "${NMAP_FSCANX_SCANNER:-}" ]]; then
    printf '%s\n' "$NMAP_FSCANX_SCANNER"
    return 0
  fi

  if [[ -x /tmp/fscanx-bin/fscanx ]]; then
    printf '/tmp/fscanx-bin/fscanx\n'
    return 0
  fi

  if command -v fscanx >/dev/null 2>&1; then
    command -v fscanx
    return 0
  fi

  return 1
}

nmap_fscanx_effective_value() {
  local override="${1:-}"
  local fallback="${2:-}"

  if [[ -n "$override" ]]; then
    printf '%s\n' "$override"
    return 0
  fi

  printf '%s\n' "$fallback"
}

nmap_fscanx_require_command() {
  local name="$1"

  if ! command -v "$name" >/dev/null 2>&1; then
    echo "缺少依赖命令：$name" >&2
    return 1
  fi

  return 0
}

nmap_fscanx_shell_quote() {
  local out=""
  local item=""

  for item in "$@"; do
    printf -v out '%s%q ' "$out" "$item"
  done

  printf '%s\n' "${out% }"
}
