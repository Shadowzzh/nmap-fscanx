#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="/Users/zhangziheng/Documents/code/nmap"
SCRIPT_PATH="$REPO_ROOT/scripts/build_fscanx_bundle.sh"

TMP_ROOT="$(mktemp -d)"
SOURCE_DIR="$TMP_ROOT/fscanx-source"
OUTPUT_DIR="$TMP_ROOT/fscanx-bundle-test"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$SOURCE_DIR"

cat > "$SOURCE_DIR/go.mod" <<'EOF'
module example.com/fscanxstub

go 1.20
EOF

cat > "$SOURCE_DIR/main.go" <<'EOF'
package main

import "fmt"

func main() {
	fmt.Println("fscanx stub")
}
EOF

(
  cd "$SOURCE_DIR"
  git init >/dev/null 2>&1
  git config user.name "Codex Test"
  git config user.email "codex@example.com"
  git add go.mod main.go
  git commit -m "init stub" >/dev/null 2>&1
)

EXPECTED_COMMIT="$(
  cd "$SOURCE_DIR"
  git rev-parse HEAD
)"

bash "$SCRIPT_PATH" \
  --source-dir "$SOURCE_DIR" \
  --output-dir "$OUTPUT_DIR" \
  --targets "linux-amd64,windows-amd64"

for expected in \
  "$OUTPUT_DIR/README.md" \
  "$OUTPUT_DIR/manifest.json" \
  "$OUTPUT_DIR/checksums.txt" \
  "$OUTPUT_DIR/fscanx-linux-amd64" \
  "$OUTPUT_DIR/fscanx-windows-amd64.exe"; do
  if [[ ! -f "$expected" ]]; then
    echo "missing output: $expected" >&2
    exit 1
  fi
done

manifest_commit="$(jq -r '.source_commit' "$OUTPUT_DIR/manifest.json")"
if [[ "$manifest_commit" != "$EXPECTED_COMMIT" ]]; then
  echo "unexpected source_commit: $manifest_commit" >&2
  exit 1
fi

targets_json="$(jq -c '.targets' "$OUTPUT_DIR/manifest.json")"
if [[ "$targets_json" != '["linux-amd64","windows-amd64"]' ]]; then
  echo "unexpected targets in manifest: $targets_json" >&2
  exit 1
fi

if ! rg -Fq 'fscanx-linux-amd64' "$OUTPUT_DIR/checksums.txt"; then
  echo "checksums.txt should include linux binary" >&2
  exit 1
fi

if ! rg -Fq 'fscanx-windows-amd64.exe' "$OUTPUT_DIR/checksums.txt"; then
  echo "checksums.txt should include windows binary" >&2
  exit 1
fi

if ! rg -Fq "$EXPECTED_COMMIT" "$OUTPUT_DIR/README.md"; then
  echo "README.md should mention source commit" >&2
  exit 1
fi

echo "fscanx bundle build regression test passed"
