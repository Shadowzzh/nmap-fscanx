#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_PATH="$REPO_ROOT/scripts/build_prod_lite.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
BUNDLE_DIR="$TMP_ROOT/fscanx-bundle"
mkdir -p "$MOCK_BIN" "$BUNDLE_DIR"

cleanup() {
  rm -f \
    "$REPO_ROOT/dist/nmap-fscanx-0.1.0-fallback.tar.gz" \
    "$REPO_ROOT/dist/nmap-fscanx-0.1.0-fallback.sha256"
  rm -rf "$REPO_ROOT/dist/nmap-fscanx-0.1.0-fallback"
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

assert_contains() {
  local needle="$1"
  local file="$2"

  if ! grep -Fq -- "$needle" "$file"; then
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

MISSING_BUNDLE_OUTPUT="$TMP_ROOT/missing-bundle.txt"
assert_fails "$MISSING_BUNDLE_OUTPUT" \
  env FSCANX_BUNDLE_SOURCE="$TMP_ROOT/not-found-bundle" \
    /bin/bash "$SCRIPT_PATH" --version "0.1.0-missing-bundle"
assert_contains "缺少 fscanx-bundle 目录" "$MISSING_BUNDLE_OUTPUT"

for tool in bash basename cat chmod cp date dirname find gzip mkdir pwd rm sed sort tar; do
  ln -sf "$(command -v "$tool")" "$MOCK_BIN/$tool"
done

cat > "$MOCK_BIN/shasum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${SHASUM_LOG:?}"
printf 'fallback-checksum  %s\n' "$3"
EOF
chmod +x "$MOCK_BIN/shasum"

export SHASUM_LOG="$TMP_ROOT/shasum.log"
VERSION="0.1.0-fallback"
ARCHIVE="$REPO_ROOT/dist/nmap-fscanx-$VERSION.tar.gz"
CHECKSUM="$REPO_ROOT/dist/nmap-fscanx-$VERSION.sha256"

cat > "$BUNDLE_DIR/fscanx-linux-amd64" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
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

env \
  PATH="$MOCK_BIN" \
  /bin/bash -lc '
    set -euo pipefail
    export PATH="'"$MOCK_BIN"'"
    export SHASUM_LOG="'"$SHASUM_LOG"'"
    export FSCANX_BUNDLE_SOURCE="'"$BUNDLE_DIR"'"
    cd "'"$REPO_ROOT"'"
    bash scripts/build_prod_lite.sh --version "'"$VERSION"'"
  ' > "$TMP_ROOT/fallback.stdout"

if [[ ! -f "$ARCHIVE" ]]; then
  echo "fallback checksum scenario should still produce archive" >&2
  exit 1
fi

if [[ ! -f "$CHECKSUM" ]]; then
  echo "fallback checksum scenario should still produce checksum file" >&2
  exit 1
fi

assert_contains "-a 256 nmap-fscanx-$VERSION.tar.gz" "$SHASUM_LOG"
assert_contains "fallback-checksum  nmap-fscanx-$VERSION.tar.gz" "$CHECKSUM"

echo "build_prod_lite failure-path regression test passed"
