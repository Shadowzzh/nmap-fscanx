#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_ROOT="$(mktemp -d)"
HOME_DIR="$TMP_ROOT/home"
INSTALL_ROOT="$TMP_ROOT/install-root"
mkdir -p "$HOME_DIR"

cp -R "$REPO_ROOT/prod-lite/." "$INSTALL_ROOT/"
cp "$REPO_ROOT/scripts/fscanx_pipeline.sh" "$INSTALL_ROOT/libexec/fscanx_pipeline.sh"
chmod +x \
  "$INSTALL_ROOT/bin/nmap-fscanx" \
  "$INSTALL_ROOT/libexec/nmap-fscanx-entry.sh" \
  "$INSTALL_ROOT/libexec/fscanx_pipeline.sh"

ENTRY_SCRIPT="$INSTALL_ROOT/bin/nmap-fscanx"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

link_tool() {
  local dir="$1"
  local name="$2"
  local source_path=""

  source_path="$(command -v "$name")"
  ln -sf "$source_path" "$dir/$name"
}

assert_contains() {
  local needle="$1"
  local file="$2"

  if ! grep -Fq "$needle" "$file"; then
    echo "missing expected text: $needle" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_fails() {
  local output_file="$1"
  shift

  if "$@" >"$output_file" 2>&1; then
    echo "command should fail: $*" >&2
    cat "$output_file" >&2
    exit 1
  fi
}

make_base_bin() {
  local dir="$1"
  mkdir -p "$dir"
  link_tool "$dir" bash
  link_tool "$dir" basename
  link_tool "$dir" dirname
  link_tool "$dir" date
}

UNKNOWN_OUTPUT="$TMP_ROOT/unknown.txt"
assert_fails "$UNKNOWN_OUTPUT" /bin/bash "$ENTRY_SCRIPT" unknown-command
assert_contains "未知子命令：unknown-command" "$UNKNOWN_OUTPUT"

ATTACH_BIN="$TMP_ROOT/attach-bin"
make_base_bin "$ATTACH_BIN"
cat > "$ATTACH_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$ATTACH_BIN/tmux"

ATTACH_OUTPUT="$TMP_ROOT/attach.txt"
assert_fails "$ATTACH_OUTPUT" \
  env HOME="$HOME_DIR" PATH="$ATTACH_BIN" /bin/bash "$ENTRY_SCRIPT" attach
assert_contains "attach 需要 --session <name>" "$ATTACH_OUTPUT"

CHECK_MISSING_JQ_BIN="$TMP_ROOT/check-missing-jq-bin"
make_base_bin "$CHECK_MISSING_JQ_BIN"
cat > "$CHECK_MISSING_JQ_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
cat > "$CHECK_MISSING_JQ_BIN/fscanx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$CHECK_MISSING_JQ_BIN/tmux" "$CHECK_MISSING_JQ_BIN/fscanx"

CHECK_MISSING_JQ_OUTPUT="$TMP_ROOT/check-missing-jq.txt"
assert_fails "$CHECK_MISSING_JQ_OUTPUT" \
  env HOME="$HOME_DIR" PATH="$CHECK_MISSING_JQ_BIN" \
    /bin/bash "$ENTRY_SCRIPT" check --scanner "$CHECK_MISSING_JQ_BIN/fscanx"
assert_contains "JQ_STATUS=missing" "$CHECK_MISSING_JQ_OUTPUT"
assert_contains "TMUX_STATUS=ok" "$CHECK_MISSING_JQ_OUTPUT"
assert_contains "SCANNER_STATUS=ok" "$CHECK_MISSING_JQ_OUTPUT"

CHECK_MISSING_TMUX_BIN="$TMP_ROOT/check-missing-tmux-bin"
make_base_bin "$CHECK_MISSING_TMUX_BIN"
link_tool "$CHECK_MISSING_TMUX_BIN" jq
cat > "$CHECK_MISSING_TMUX_BIN/fscanx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$CHECK_MISSING_TMUX_BIN/fscanx"

CHECK_MISSING_TMUX_OUTPUT="$TMP_ROOT/check-missing-tmux.txt"
assert_fails "$CHECK_MISSING_TMUX_OUTPUT" \
  env HOME="$HOME_DIR" PATH="$CHECK_MISSING_TMUX_BIN" \
    /bin/bash "$ENTRY_SCRIPT" check --scanner "$CHECK_MISSING_TMUX_BIN/fscanx"
assert_contains "JQ_STATUS=ok" "$CHECK_MISSING_TMUX_OUTPUT"
assert_contains "TMUX_STATUS=missing" "$CHECK_MISSING_TMUX_OUTPUT"
assert_contains "SCANNER_STATUS=ok" "$CHECK_MISSING_TMUX_OUTPUT"

CHECK_MISSING_SCANNER_BIN="$TMP_ROOT/check-missing-scanner-bin"
make_base_bin "$CHECK_MISSING_SCANNER_BIN"
link_tool "$CHECK_MISSING_SCANNER_BIN" jq
cat > "$CHECK_MISSING_SCANNER_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$CHECK_MISSING_SCANNER_BIN/tmux"

CHECK_MISSING_SCANNER_OUTPUT="$TMP_ROOT/check-missing-scanner.txt"
assert_fails "$CHECK_MISSING_SCANNER_OUTPUT" \
  env HOME="$HOME_DIR" PATH="$CHECK_MISSING_SCANNER_BIN" \
    /bin/bash "$ENTRY_SCRIPT" check --scanner "$CHECK_MISSING_SCANNER_BIN/missing-fscanx"
assert_contains "JQ_STATUS=ok" "$CHECK_MISSING_SCANNER_OUTPUT"
assert_contains "TMUX_STATUS=ok" "$CHECK_MISSING_SCANNER_OUTPUT"
assert_contains "SCANNER_STATUS=missing" "$CHECK_MISSING_SCANNER_OUTPUT"

START_BIN="$TMP_ROOT/start-bin"
START_TMUX_LOG="$TMP_ROOT/start-tmux.log"
make_base_bin "$START_BIN"
link_tool "$START_BIN" jq
cat > "$START_BIN/tmux" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "$START_TMUX_LOG"

if [[ "\${1:-}" == "has-session" ]]; then
  exit 0
fi

exit 0
EOF
cat > "$START_BIN/fscanx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$START_BIN/tmux" "$START_BIN/fscanx"

START_OUTPUT="$TMP_ROOT/start.txt"
env HOME="$HOME_DIR" PATH="$START_BIN" \
  /bin/bash "$ENTRY_SCRIPT" start \
    --scanner "$START_BIN/fscanx" \
    --targets "192.168.1.0/24" \
    --scan-root "$TMP_ROOT/scans/start" \
    > "$START_OUTPUT"

if ! grep -Eq '^SESSION_NAME=nmap-fscanx-scan-[0-9]{8}-[0-9]{6}$' "$START_OUTPUT"; then
  echo "start should add a time suffix when the default session already exists" >&2
  cat "$START_OUTPUT" >&2
  exit 1
fi

assert_contains "ATTACH_COMMAND=tmux attach -t" "$START_OUTPUT"
assert_contains "has-session -t nmap-fscanx-scan-" "$START_TMUX_LOG"
assert_contains "new -ds nmap-fscanx-scan-" "$START_TMUX_LOG"

echo "prod-lite entry failure-path regression test passed"
