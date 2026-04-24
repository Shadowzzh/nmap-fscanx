#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_OUTPUT_DIR="$REPO_ROOT/fscanx-bundle"
DEFAULT_TARGETS="linux-amd64,linux-arm64,linux-armv7,windows-amd64,windows-386"
SOURCE_REPO_URL="https://github.com/killmonday/fscanx.git"

OUTPUT_DIR="$DEFAULT_OUTPUT_DIR"
TARGETS="$DEFAULT_TARGETS"
SOURCE_DIR=""
REF=""
TEMP_ROOT=""

BUILT_TARGETS=()
BUILT_FILES=()

print_help() {
  cat <<'EOF'
用法：
  build_fscanx_bundle.sh [参数]

说明：
  构建常见 Linux 和 Windows 的 fscanx 二进制，
  并将产物写入仓库根目录下的 fscanx-bundle 目录。

参数：
  --source-dir <path>    使用本地源码目录构建
  --ref <git-ref>        构建指定远端 git ref，不能和 --source-dir 同时使用
  --output-dir <path>    指定输出目录，默认 <repo>/fscanx-bundle
  --targets <list>       目标列表，逗号分隔
                         默认 linux-amd64,linux-arm64,linux-armv7,windows-amd64,windows-386
  -h, --help             显示帮助
EOF
}

fail() {
  echo "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]]; then
    rm -rf "$TEMP_ROOT"
  fi
}
trap cleanup EXIT

ensure_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    fail "缺少依赖命令：$name"
  fi
}

timestamp_now() {
  date '+%Y-%m-%dT%H:%M:%S%z' | sed 's/\([0-9][0-9]\)\([0-9][0-9]\)$/\1:\2/'
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --source-dir)
        [[ $# -ge 2 ]] || fail "--source-dir 缺少参数"
        SOURCE_DIR="$2"
        shift 2
        ;;
      --ref)
        [[ $# -ge 2 ]] || fail "--ref 缺少参数"
        REF="$2"
        shift 2
        ;;
      --output-dir)
        [[ $# -ge 2 ]] || fail "--output-dir 缺少参数"
        OUTPUT_DIR="$2"
        shift 2
        ;;
      --targets)
        [[ $# -ge 2 ]] || fail "--targets 缺少参数"
        TARGETS="$2"
        shift 2
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      *)
        fail "不支持的参数：$1"
        ;;
    esac
  done
}

prepare_output_dir() {
  mkdir -p "$OUTPUT_DIR"
  find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
}

resolve_source_dir() {
  if [[ -n "$SOURCE_DIR" && -n "$REF" ]]; then
    fail "--source-dir 与 --ref 不能同时使用"
  fi

  if [[ -n "$SOURCE_DIR" ]]; then
    [[ -d "$SOURCE_DIR" ]] || fail "本地源码目录不存在：$SOURCE_DIR"
    SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd)"
    return 0
  fi

  ensure_command git

  TEMP_ROOT="$(mktemp -d)"
  SOURCE_DIR="$TEMP_ROOT/fscanx-source"

  if [[ -n "$REF" ]]; then
    git clone "$SOURCE_REPO_URL" "$SOURCE_DIR" >/dev/null 2>&1
    git -C "$SOURCE_DIR" checkout --detach "$REF" >/dev/null 2>&1
    return 0
  fi

  git clone --depth 1 "$SOURCE_REPO_URL" "$SOURCE_DIR" >/dev/null 2>&1
}

resolve_source_commit() {
  if git -C "$SOURCE_DIR" rev-parse HEAD >/dev/null 2>&1; then
    git -C "$SOURCE_DIR" rev-parse HEAD
    return 0
  fi

  printf 'unknown'
}

target_env() {
  local target="$1"

  TARGET_GOOS=""
  TARGET_GOARCH=""
  TARGET_GOARM=""
  TARGET_FILENAME=""

  case "$target" in
    linux-amd64)
      TARGET_GOOS="linux"
      TARGET_GOARCH="amd64"
      TARGET_FILENAME="fscanx-linux-amd64"
      ;;
    linux-arm64)
      TARGET_GOOS="linux"
      TARGET_GOARCH="arm64"
      TARGET_FILENAME="fscanx-linux-arm64"
      ;;
    linux-armv7)
      TARGET_GOOS="linux"
      TARGET_GOARCH="arm"
      TARGET_GOARM="7"
      TARGET_FILENAME="fscanx-linux-armv7"
      ;;
    windows-amd64)
      TARGET_GOOS="windows"
      TARGET_GOARCH="amd64"
      TARGET_FILENAME="fscanx-windows-amd64.exe"
      ;;
    windows-386)
      TARGET_GOOS="windows"
      TARGET_GOARCH="386"
      TARGET_FILENAME="fscanx-windows-386.exe"
      ;;
    *)
      fail "不支持的目标平台：$target"
      ;;
  esac
}

build_one_target() {
  local target="$1"
  local output_file=""

  target_env "$target"
  output_file="$OUTPUT_DIR/$TARGET_FILENAME"

  if [[ -n "$TARGET_GOARM" ]]; then
    (
      cd "$SOURCE_DIR"
      env CGO_ENABLED=0 GOOS="$TARGET_GOOS" GOARCH="$TARGET_GOARCH" GOARM="$TARGET_GOARM" \
        go build -trimpath -ldflags "-s -w" -o "$output_file" .
    )
  else
    (
      cd "$SOURCE_DIR"
      env CGO_ENABLED=0 GOOS="$TARGET_GOOS" GOARCH="$TARGET_GOARCH" \
        go build -trimpath -ldflags "-s -w" -o "$output_file" .
    )
  fi

  BUILT_TARGETS+=("$target")
  BUILT_FILES+=("$TARGET_FILENAME")
}

build_targets() {
  local target=""
  local trimmed_target=""
  IFS=',' read -r -a target_array <<< "$TARGETS"

  for target in "${target_array[@]}"; do
    trimmed_target="$(printf '%s' "$target" | xargs)"
    [[ -n "$trimmed_target" ]] || continue
    build_one_target "$trimmed_target"
  done

  [[ ${#BUILT_FILES[@]} -gt 0 ]] || fail "没有可构建的目标平台"
}

write_checksums() {
  (
    cd "$OUTPUT_DIR"
    shasum -a 256 "${BUILT_FILES[@]}" > checksums.txt
  )
}

write_manifest() {
  local source_commit="$1"
  local source_label="$2"
  local targets_json=""
  local files_json=""

  targets_json="$(printf '%s\n' "${BUILT_TARGETS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
  files_json="$(printf '%s\n' "${BUILT_FILES[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"

  jq -n \
    --arg generated_at "$(timestamp_now)" \
    --arg source_repo "$source_label" \
    --arg source_commit "$source_commit" \
    --arg requested_ref "$REF" \
    --argjson targets "$targets_json" \
    --argjson files "$files_json" \
    '{
      generated_at: $generated_at,
      source_repo: $source_repo,
      source_commit: $source_commit,
      requested_ref: $requested_ref,
      targets: $targets,
      files: $files
    }' > "$OUTPUT_DIR/manifest.json"
}

write_readme() {
  local source_commit="$1"
  local source_label="$2"
  local file=""

  {
    printf '# fscanx Bundle\n\n'
    printf 'Source repo: `%s`\n\n' "$source_label"
    printf 'Source commit: `%s`\n\n' "$source_commit"
    printf 'Targets:\n\n'
    for file in "${BUILT_FILES[@]}"; do
      printf -- '- `%s`\n' "$file"
    done
    printf '\nChecksum file: `checksums.txt`\n'
  } > "$OUTPUT_DIR/README.md"
}

main() {
  local source_commit=""
  local source_label=""

  parse_args "$@"

  ensure_command go
  ensure_command jq
  ensure_command shasum

  prepare_output_dir
  resolve_source_dir

  source_commit="$(resolve_source_commit)"
  source_label="$SOURCE_REPO_URL"
  if [[ -n "$SOURCE_DIR" && -z "$TEMP_ROOT" ]]; then
    source_label="local:$SOURCE_DIR"
  fi

  build_targets
  write_checksums
  write_manifest "$source_commit" "$source_label"
  write_readme "$source_commit" "$source_label"

  echo "fscanx bundle ready: $OUTPUT_DIR"
}

main "$@"
