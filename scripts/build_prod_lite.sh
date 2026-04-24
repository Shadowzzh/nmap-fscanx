#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="/Users/zhangziheng/Documents/code/nmap"
PACKAGE_SOURCE="$REPO_ROOT/prod-lite"
DIST_DIR="$REPO_ROOT/dist"
BUNDLE_SOURCE="${FSCANX_BUNDLE_SOURCE:-$REPO_ROOT/fscanx-bundle}"
VERSION="0.1.0-dev"

print_help() {
  cat <<'EOF'
用法：
  bash scripts/build_prod_lite.sh [--version <version>]
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version)
        VERSION="${2:-}"
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

write_checksum() {
  local archive="$1"
  local checksum_file="$2"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$(basename "$archive")" > "$checksum_file"
    return 0
  fi

  shasum -a 256 "$(basename "$archive")" > "$checksum_file"
}

main() {
  local release_name=""
  local release_root=""
  local archive=""
  local checksum_file=""
  local manifest_file=""

  parse_args "$@"

  if [[ ! -d "$BUNDLE_SOURCE" ]]; then
    echo "缺少 fscanx-bundle 目录：$BUNDLE_SOURCE" >&2
    exit 1
  fi

  release_name="nmap-fscanx-$VERSION"
  release_root="$DIST_DIR/$release_name"
  archive="$DIST_DIR/$release_name.tar.gz"
  checksum_file="$DIST_DIR/$release_name.sha256"
  manifest_file="$release_root/MANIFEST.txt"

  rm -rf "$release_root"
  mkdir -p "$release_root" "$DIST_DIR"

  cp -R \
    "$PACKAGE_SOURCE/README.md" \
    "$PACKAGE_SOURCE/Makefile" \
    "$PACKAGE_SOURCE/bin" \
    "$PACKAGE_SOURCE/libexec" \
    "$PACKAGE_SOURCE/conf" \
    "$PACKAGE_SOURCE/examples" \
    "$PACKAGE_SOURCE/docs" \
    "$BUNDLE_SOURCE" \
    "$release_root/"

  cp "$PACKAGE_SOURCE/install.sh" "$PACKAGE_SOURCE/uninstall.sh" "$release_root/"
  cp "$REPO_ROOT/scripts/fscanx_pipeline.sh" "$release_root/libexec/fscanx_pipeline.sh"

  printf '%s\n' "$VERSION" > "$release_root/VERSION"

  {
    echo "# Release Notes"
    echo
    echo "- package: $release_name"
    echo "- built_at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "- includes: prod-lite runtime, installer, examples, docs, bundled fscanx artifacts, existing fscanx pipeline"
  } > "$release_root/RELEASE_NOTES.md"

  (
    cd "$release_root"
    find . -type f | sed 's#^\./##' | sort > "$manifest_file"
  )

  chmod +x \
    "$release_root/bin/nmap-fscanx" \
    "$release_root/libexec/fscanx_pipeline.sh" \
    "$release_root/libexec/nmap-fscanx-entry.sh" \
    "$release_root/install.sh" \
    "$release_root/uninstall.sh" \
    "$release_root/examples/run-all.example.sh" \
    "$release_root/examples/run-phase1.example.sh" \
    "$release_root/examples/run-phase2.example.sh"

  rm -f "$archive" "$checksum_file"
  (
    cd "$DIST_DIR"
    tar -czf "$archive" "$release_name"
    write_checksum "$archive" "$checksum_file"
  )

  echo "$archive"
}

main "$@"
