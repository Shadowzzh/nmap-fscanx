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

INSTALL_ROOT="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
INSTALL_ENV="$INSTALL_ROOT/conf/install.env"
COMMAND_LINK=""
RUNTIME_CONFIG=""

if [[ -f "$INSTALL_ENV" ]]; then
  # shellcheck disable=SC1090
  . "$INSTALL_ENV"
  COMMAND_LINK="${NMAP_FSCANX_BIN_LINK:-}"
  RUNTIME_CONFIG="${NMAP_FSCANX_RUNTIME_CONFIG:-}"
fi

if [[ -n "$COMMAND_LINK" && -L "$COMMAND_LINK" ]]; then
  rm -f "$COMMAND_LINK"
fi

if [[ -n "$RUNTIME_CONFIG" && -f "$RUNTIME_CONFIG" ]]; then
  rm -f "$RUNTIME_CONFIG"
fi

rm -rf "$INSTALL_ROOT"

echo "UNINSTALLED=$INSTALL_ROOT"
