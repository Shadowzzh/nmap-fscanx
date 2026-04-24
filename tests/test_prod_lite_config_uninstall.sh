#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_ROOT="$(mktemp -d)"
INSTALL_ROOT="$TMP_ROOT/install-root"
RUNTIME_HOME="$TMP_ROOT/home"
mkdir -p "$RUNTIME_HOME"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cp -R "$REPO_ROOT/prod-lite/." "$INSTALL_ROOT/"
cp "$REPO_ROOT/scripts/fscanx_pipeline.sh" "$INSTALL_ROOT/libexec/fscanx_pipeline.sh"
chmod +x \
  "$INSTALL_ROOT/bin/nmap-fscanx" \
  "$INSTALL_ROOT/libexec/nmap-fscanx-entry.sh" \
  "$INSTALL_ROOT/libexec/fscanx_pipeline.sh" \
  "$INSTALL_ROOT/uninstall.sh"

ENTRY_SCRIPT="$INSTALL_ROOT/bin/nmap-fscanx"
UNINSTALL_SCRIPT="$INSTALL_ROOT/uninstall.sh"
RUNTIME_CONFIG="$TMP_ROOT/runtime-config.env"
RUNTIME_LINK="$TMP_ROOT/bin/nmap-fscanx"
INSTALL_ROOT_REAL="$(cd -P "$INSTALL_ROOT" && pwd)"
SCANNER_RUNTIME="$TMP_ROOT/scanner-runtime"
SCANNER_CLI="$TMP_ROOT/scanner-cli"
mkdir -p "$TMP_ROOT/bin"

cat > "$SCANNER_RUNTIME" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
cat > "$SCANNER_CLI" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$SCANNER_RUNTIME" "$SCANNER_CLI"

cat > "$INSTALL_ROOT/conf/default.env" <<EOF
NMAP_FSCANX_PHASE1_PORTS=11,12
NMAP_FSCANX_PHASE2_PORTS=2000-3000
NMAP_FSCANX_THREADS=111
NMAP_FSCANX_TIMEOUT=5
NMAP_FSCANX_TMUX_PREFIX=from-default
NMAP_FSCANX_SCAN_BASE=$TMP_ROOT/default-scan-base
EOF

cat > "$INSTALL_ROOT/conf/install.env" <<EOF
NMAP_FSCANX_INSTALL_ROOT=$INSTALL_ROOT
NMAP_FSCANX_BIN_LINK=$RUNTIME_LINK
NMAP_FSCANX_RUNTIME_CONFIG=$RUNTIME_CONFIG
EOF

cat > "$RUNTIME_CONFIG" <<EOF
NMAP_FSCANX_PHASE1_PORTS=21,22
NMAP_FSCANX_PHASE2_PORTS=4000-5000
NMAP_FSCANX_THREADS=222
NMAP_FSCANX_TIMEOUT=6
NMAP_FSCANX_TMUX_PREFIX=from-runtime
NMAP_FSCANX_SCAN_BASE=$TMP_ROOT/runtime-scan-base
NMAP_FSCANX_SCANNER=$SCANNER_RUNTIME
EOF

ln -s "$ENTRY_SCRIPT" "$RUNTIME_LINK"

CONFIG_OUTPUT="$TMP_ROOT/print-config.txt"
HOME="$RUNTIME_HOME" /bin/bash "$ENTRY_SCRIPT" print-config > "$CONFIG_OUTPUT"

grep -Fqx "NMAP_FSCANX_PHASE1_PORTS=21,22" "$CONFIG_OUTPUT" || {
  echo "runtime config should override default phase1 ports" >&2
  cat "$CONFIG_OUTPUT" >&2
  exit 1
}
grep -Fqx "NMAP_FSCANX_PHASE2_PORTS=4000-5000" "$CONFIG_OUTPUT" || {
  echo "runtime config should override default phase2 ports" >&2
  cat "$CONFIG_OUTPUT" >&2
  exit 1
}
grep -Fqx "NMAP_FSCANX_THREADS=222" "$CONFIG_OUTPUT" || {
  echo "runtime config should override default threads" >&2
  cat "$CONFIG_OUTPUT" >&2
  exit 1
}
grep -Fqx "NMAP_FSCANX_TIMEOUT=6" "$CONFIG_OUTPUT" || {
  echo "runtime config should override default timeout" >&2
  cat "$CONFIG_OUTPUT" >&2
  exit 1
}
grep -Fqx "NMAP_FSCANX_TMUX_PREFIX=from-runtime" "$CONFIG_OUTPUT" || {
  echo "runtime config should override default tmux prefix" >&2
  cat "$CONFIG_OUTPUT" >&2
  exit 1
}
grep -Fqx "NMAP_FSCANX_SCAN_BASE=$TMP_ROOT/runtime-scan-base" "$CONFIG_OUTPUT" || {
  echo "runtime config should override default scan base" >&2
  cat "$CONFIG_OUTPUT" >&2
  exit 1
}
grep -Fqx "NMAP_FSCANX_SCANNER=$SCANNER_RUNTIME" "$CONFIG_OUTPUT" || {
  echo "runtime config should resolve scanner path" >&2
  cat "$CONFIG_OUTPUT" >&2
  exit 1
}

CLI_OUTPUT="$TMP_ROOT/print-config-cli.txt"
HOME="$RUNTIME_HOME" /bin/bash "$ENTRY_SCRIPT" print-config \
  --phase1-ports "31,32" \
  --phase2-ports "6000-7000" \
  --threads 333 \
  --timeout 7 \
  --scanner "$SCANNER_CLI" \
  > "$CLI_OUTPUT"

grep -Fqx "NMAP_FSCANX_PHASE1_PORTS=31,32" "$CLI_OUTPUT" || {
  echo "CLI phase1 ports should override runtime config" >&2
  cat "$CLI_OUTPUT" >&2
  exit 1
}
grep -Fqx "NMAP_FSCANX_PHASE2_PORTS=6000-7000" "$CLI_OUTPUT" || {
  echo "CLI phase2 ports should override runtime config" >&2
  cat "$CLI_OUTPUT" >&2
  exit 1
}
grep -Fqx "NMAP_FSCANX_THREADS=333" "$CLI_OUTPUT" || {
  echo "CLI threads should override runtime config" >&2
  cat "$CLI_OUTPUT" >&2
  exit 1
}
grep -Fqx "NMAP_FSCANX_TIMEOUT=7" "$CLI_OUTPUT" || {
  echo "CLI timeout should override runtime config" >&2
  cat "$CLI_OUTPUT" >&2
  exit 1
}
grep -Fqx "NMAP_FSCANX_SCANNER=$SCANNER_CLI" "$CLI_OUTPUT" || {
  echo "CLI scanner should override runtime config" >&2
  cat "$CLI_OUTPUT" >&2
  exit 1
}

cat > "$INSTALL_ROOT/conf/default.env" <<EOF
NMAP_FSCANX_PHASE1_PORTS=11,12
NMAP_FSCANX_PHASE2_PORTS=2000-3000
NMAP_FSCANX_THREADS=111
NMAP_FSCANX_TIMEOUT=5
NMAP_FSCANX_TMUX_PREFIX=from-default
EOF

cat > "$RUNTIME_CONFIG" <<EOF
NMAP_FSCANX_PHASE1_PORTS=21,22
NMAP_FSCANX_PHASE2_PORTS=4000-5000
NMAP_FSCANX_THREADS=222
NMAP_FSCANX_TIMEOUT=6
NMAP_FSCANX_TMUX_PREFIX=from-runtime
NMAP_FSCANX_SCANNER=$SCANNER_RUNTIME
EOF

DEFAULT_WORKDIR="$TMP_ROOT/default-workdir"
mkdir -p "$DEFAULT_WORKDIR"
DEFAULT_WORKDIR_REAL="$(cd "$DEFAULT_WORKDIR" && pwd -P)"
DEFAULT_SCAN_OUTPUT="$TMP_ROOT/print-config-default-scan-base.txt"
(
  cd "$DEFAULT_WORKDIR"
  HOME="$RUNTIME_HOME" /bin/bash "$ENTRY_SCRIPT" print-config > "$DEFAULT_SCAN_OUTPUT"
)

grep -Fqx "NMAP_FSCANX_SCAN_BASE=$DEFAULT_WORKDIR_REAL/scans" "$DEFAULT_SCAN_OUTPUT" || {
  echo "default scan base should follow current working directory" >&2
  cat "$DEFAULT_SCAN_OUTPUT" >&2
  exit 1
}

UNINSTALL_OUTPUT="$TMP_ROOT/uninstall.txt"
/bin/bash "$UNINSTALL_SCRIPT" > "$UNINSTALL_OUTPUT"

grep -Fqx "UNINSTALLED=$INSTALL_ROOT_REAL" "$UNINSTALL_OUTPUT" || {
  echo "uninstall should print removed install root" >&2
  cat "$UNINSTALL_OUTPUT" >&2
  exit 1
}

if [[ -e "$INSTALL_ROOT" ]]; then
  echo "uninstall should remove install root" >&2
  exit 1
fi

if [[ -e "$RUNTIME_LINK" ]]; then
  echo "uninstall should remove command symlink" >&2
  exit 1
fi

if [[ -e "$RUNTIME_CONFIG" ]]; then
  echo "uninstall should remove runtime config" >&2
  exit 1
fi

echo "prod-lite config and uninstall regression test passed"
