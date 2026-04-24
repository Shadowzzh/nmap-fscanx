#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="/Users/zhangziheng/Documents/code/nmap"
BUILD_SCRIPT="$REPO_ROOT/scripts/build_prod_lite.sh"
VERSION="0.1.0-test"
ARCHIVE="$REPO_ROOT/dist/nmap-fscanx-$VERSION.tar.gz"
CHECKSUM="$REPO_ROOT/dist/nmap-fscanx-$VERSION.sha256"

TMP_ROOT="$(mktemp -d)"
HOME_DIR="$TMP_ROOT/home"
EXTRACT_DIR="$TMP_ROOT/extract"
MOCK_BIN="$TMP_ROOT/bin"
BUNDLE_DIR="$TMP_ROOT/fscanx-bundle"
TMUX_CALLS_LOG="$TMP_ROOT/tmux_calls.log"
mkdir -p "$HOME_DIR" "$EXTRACT_DIR" "$MOCK_BIN" "$BUNDLE_DIR"

cleanup() {
  rm -rf "$TMP_ROOT"
  rm -f "$ARCHIVE" "$CHECKSUM"
}
trap cleanup EXIT

cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${TMUX_CALLS_LOG:?}"

if [[ "${1:-}" == "has-session" ]]; then
  exit 1
fi

exit 0
EOF

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  -s)
    echo "Linux"
    ;;
  -m)
    echo "x86_64"
    ;;
  *)
    echo "Linux"
    ;;
esac
EOF

cat > "$TMP_ROOT/mock-fscanx" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode=""
host_targets=""
host_file=""
ports=""

args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -h)
      host_targets="${args[$((i + 1))]}"
      mode="phase1"
      ;;
    -hf)
      host_file="${args[$((i + 1))]}"
      mode="phase2"
      ;;
    -p)
      ports="${args[$((i + 1))]}"
      ;;
  esac
done

if [[ "$mode" == "phase1" ]]; then
  if [[ "$host_targets" != "192.168.1.0/24,192.168.20.0/24" ]]; then
    echo "unexpected phase1 targets: $host_targets" >&2
    exit 21
  fi

  if [[ "$ports" != "22,80,443,445,3389" ]]; then
    echo "unexpected phase1 ports: $ports" >&2
    exit 22
  fi

  cat > result.txt <<'JSON'
{"type":"Port","text":"open\t192.168.1.10:80\t\n"},
{"type":"Port","text":"open\t192.168.20.15:22\t\n"},
JSON
  exit 0
fi

if [[ "$mode" == "phase2" ]]; then
  if [[ ! -f "$host_file" ]]; then
    echo "missing alive host file: $host_file" >&2
    exit 23
  fi

  if [[ "$ports" != "1-65535" ]]; then
    echo "unexpected phase2 ports: $ports" >&2
    exit 24
  fi

  cat > result.txt <<'JSON'
{"type":"Port","text":"open\t192.168.1.10:80\t\n"},
{"type":"Port","text":"open\t192.168.20.15:22\t\n"},
{"type":"Port","text":"open\t192.168.20.15:445\t\n"},
JSON
  exit 0
fi

echo "unsupported mock call: $*" >&2
exit 25
EOF

chmod +x "$MOCK_BIN/tmux" "$MOCK_BIN/uname" "$TMP_ROOT/mock-fscanx"
cp "$TMP_ROOT/mock-fscanx" "$BUNDLE_DIR/fscanx-linux-amd64"
chmod +x "$BUNDLE_DIR/fscanx-linux-amd64"
cat > "$BUNDLE_DIR/manifest.json" <<'EOF'
{
  "targets": ["linux-amd64"],
  "files": ["fscanx-linux-amd64"]
}
EOF
cat > "$BUNDLE_DIR/checksums.txt" <<'EOF'
dummy  fscanx-linux-amd64
EOF
export TMUX_CALLS_LOG

FSCANX_BUNDLE_SOURCE="$BUNDLE_DIR" bash "$BUILD_SCRIPT" --version "$VERSION"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "release archive was not created" >&2
  exit 1
fi

if [[ ! -f "$CHECKSUM" ]]; then
  echo "release checksum was not created" >&2
  exit 1
fi

ARCHIVE_LIST="$TMP_ROOT/archive.list"
tar -tzf "$ARCHIVE" > "$ARCHIVE_LIST"

for expected in \
  "nmap-fscanx-$VERSION/README.md" \
  "nmap-fscanx-$VERSION/Makefile" \
  "nmap-fscanx-$VERSION/fscanx-bundle/manifest.json" \
  "nmap-fscanx-$VERSION/fscanx-bundle/fscanx-linux-amd64" \
  "nmap-fscanx-$VERSION/install.sh" \
  "nmap-fscanx-$VERSION/uninstall.sh" \
  "nmap-fscanx-$VERSION/bin/nmap-fscanx" \
  "nmap-fscanx-$VERSION/libexec/fscanx_pipeline.sh" \
  "nmap-fscanx-$VERSION/libexec/nmap-fscanx-entry.sh" \
  "nmap-fscanx-$VERSION/conf/default.env" \
  "nmap-fscanx-$VERSION/examples/run-all.example.sh" \
  "nmap-fscanx-$VERSION/docs/INSTALL.md"; do
  if ! grep -Fq "$expected" "$ARCHIVE_LIST"; then
    echo "missing archive entry: $expected" >&2
    exit 1
  fi
done

tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
PACKAGE_ROOT="$EXTRACT_DIR/nmap-fscanx-$VERSION"

HOME="$HOME_DIR" PATH="$MOCK_BIN:/usr/bin:/bin" make -C "$PACKAGE_ROOT" install

if [[ ! -x "$HOME_DIR/.local/bin/nmap-fscanx" ]]; then
  echo "public command was not linked into ~/.local/bin" >&2
  exit 1
fi

if [[ ! -f "$HOME_DIR/.config/nmap-fscanx/config.env" ]]; then
  echo "runtime config was not created" >&2
  exit 1
fi

if [[ ! -x "$HOME_DIR/.local/nmap-fscanx/bin/fscanx" ]]; then
  echo "bundle scanner was not installed into package bin directory" >&2
  exit 1
fi

HOME="$HOME_DIR" PATH="$MOCK_BIN:$PATH" make -C "$PACKAGE_ROOT" check > "$TMP_ROOT/check.txt"

if ! grep -Fq "SCANNER_STATUS=ok" "$TMP_ROOT/check.txt"; then
  echo "check output should report scanner ready" >&2
  cat "$TMP_ROOT/check.txt" >&2
  exit 1
fi

HOME="$HOME_DIR" PATH="$MOCK_BIN:$PATH" "$HOME_DIR/.local/bin/nmap-fscanx" run \
  --targets "192.168.1.0/24,192.168.20.0/24" \
  --scan-root "$TMP_ROOT/scans/demo" \
  > "$TMP_ROOT/run.stdout"

if [[ ! -f "$TMP_ROOT/scans/demo/report.json" ]]; then
  echo "report.json was not created by installed command" >&2
  exit 1
fi

alive_count="$(jq -r '.phase1.alive_ip_count' "$TMP_ROOT/scans/demo/report.json")"
if [[ "$alive_count" != "2" ]]; then
  echo "unexpected alive_ip_count: $alive_count" >&2
  exit 1
fi

asset_count="$(jq -r '.phase2.open_ip_port_count' "$TMP_ROOT/scans/demo/report.json")"
if [[ "$asset_count" != "3" ]]; then
  echo "unexpected open_ip_port_count: $asset_count" >&2
  exit 1
fi

HOME="$HOME_DIR" PATH="$MOCK_BIN:$PATH" "$HOME_DIR/.local/bin/nmap-fscanx" start \
  --targets "192.168.1.0/24,192.168.20.0/24" \
  --scan-root "$TMP_ROOT/scans/tmux" \
  > "$TMP_ROOT/start.stdout"

if ! grep -Fq "new -ds" "$TMUX_CALLS_LOG"; then
  echo "start command should launch a detached tmux session" >&2
  cat "$TMUX_CALLS_LOG" >&2
  exit 1
fi

echo "prod-lite packaging regression test passed"
