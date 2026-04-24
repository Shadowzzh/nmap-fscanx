#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_ROOT="$(mktemp -d)"
HOME_DIR="$TMP_ROOT/home"
PACKAGE_ROOT="$TMP_ROOT/package-root"
mkdir -p "$HOME_DIR"

cp -R "$REPO_ROOT/prod-lite/." "$PACKAGE_ROOT/"
cp "$REPO_ROOT/scripts/fscanx_pipeline.sh" "$PACKAGE_ROOT/libexec/fscanx_pipeline.sh"

INSTALL_SCRIPT="$PACKAGE_ROOT/install.sh"

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

make_install_bin() {
  local dir="$1"
  mkdir -p "$dir"
  link_tool "$dir" bash
  link_tool "$dir" basename
  link_tool "$dir" chmod
  link_tool "$dir" cp
  link_tool "$dir" dirname
  link_tool "$dir" id
  link_tool "$dir" ln
  link_tool "$dir" mkdir
  link_tool "$dir" rm
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

MOCK_SCANNER="$TMP_ROOT/mock-fscanx"
cat > "$MOCK_SCANNER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$MOCK_SCANNER"

INVALID_SCANNER_OUTPUT="$TMP_ROOT/invalid-scanner.txt"
assert_fails "$INVALID_SCANNER_OUTPUT" \
  /bin/bash "$INSTALL_SCRIPT" \
    --prefix "$TMP_ROOT/prefix-invalid-scanner" \
    --scanner "$TMP_ROOT/does-not-exist"
assert_contains "scanner 不存在或不可执行" "$INVALID_SCANNER_OUTPUT"

EXISTING_PREFIX="$TMP_ROOT/prefix-existing"
mkdir -p "$EXISTING_PREFIX/nmap-fscanx"
EXISTING_OUTPUT="$TMP_ROOT/existing-prefix.txt"
assert_fails "$EXISTING_OUTPUT" \
  /bin/bash "$INSTALL_SCRIPT" \
    --prefix "$EXISTING_PREFIX" \
    --scanner "$MOCK_SCANNER"
assert_contains "安装目录已存在，请使用 --force 覆盖" "$EXISTING_OUTPUT"

INSTALL_DEPS_BIN="$TMP_ROOT/install-deps-bin"
make_install_bin "$INSTALL_DEPS_BIN"

INSTALL_DEPS_OUTPUT="$TMP_ROOT/install-deps.txt"
env HOME="$HOME_DIR" PATH="$INSTALL_DEPS_BIN" \
  /bin/bash "$INSTALL_SCRIPT" \
    --prefix "$TMP_ROOT/prefix-install-deps" \
    --install-deps \
    --scanner "$MOCK_SCANNER" \
    > "$INSTALL_DEPS_OUTPUT" 2>&1

assert_contains "未自动安装依赖：当前不是 root，请自行安装 jq tmux" "$INSTALL_DEPS_OUTPUT"
assert_contains "SCANNER_PATH=$MOCK_SCANNER" "$INSTALL_DEPS_OUTPUT"

if [[ ! -x "$TMP_ROOT/prefix-install-deps/bin/nmap-fscanx" ]]; then
  echo "install should still succeed for non-root --install-deps path" >&2
  exit 1
fi

UNSUPPORTED_BIN="$TMP_ROOT/unsupported-bin"
make_install_bin "$UNSUPPORTED_BIN"
cat > "$UNSUPPORTED_BIN/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  -s)
    echo "Linux"
    ;;
  -m)
    echo "mips64"
    ;;
  *)
    echo "Linux"
    ;;
esac
EOF
chmod +x "$UNSUPPORTED_BIN/uname"

UNSUPPORTED_OUTPUT="$TMP_ROOT/unsupported-arch.txt"
env HOME="$HOME_DIR" PATH="$UNSUPPORTED_BIN" \
  /bin/bash "$INSTALL_SCRIPT" \
    --prefix "$TMP_ROOT/prefix-unsupported-arch" \
    > "$UNSUPPORTED_OUTPUT"

assert_contains "SCANNER_PATH=not-configured" "$UNSUPPORTED_OUTPUT"

if [[ -e "$TMP_ROOT/prefix-unsupported-arch/nmap-fscanx/bin/fscanx" ]]; then
  echo "unsupported-arch install should not copy a bundled scanner" >&2
  exit 1
fi

RUNTIME_CONFIG="$TMP_ROOT/prefix-unsupported-arch/etc/nmap-fscanx/config.env"
if [[ ! -f "$RUNTIME_CONFIG" ]]; then
  echo "runtime config should still be written for unsupported arch install" >&2
  exit 1
fi

if grep -Eq '^NMAP_FSCANX_SCANNER=' "$RUNTIME_CONFIG"; then
  echo "runtime config should not pin a scanner for unsupported arch install" >&2
  cat "$RUNTIME_CONFIG" >&2
  exit 1
fi

echo "prod-lite install fallback regression test passed"
