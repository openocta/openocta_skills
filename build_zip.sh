#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="${ROOT}/dist"

# run_all 使用的临时目录（需全局变量，便于 EXIT trap 在函数返回后仍能清理）
BUILD_ZIP_BUNDLE_TMP=""

_bundle_cleanup() {
  if [[ -n "${BUILD_ZIP_BUNDLE_TMP:-}" ]]; then
    rm -rf "${BUILD_ZIP_BUNDLE_TMP}"
    BUILD_ZIP_BUNDLE_TMP=""
  fi
}

# 不参与「技能目录」识别的名称（小写比较）
SKIP_NAMES=(
  "template"
  "dist"
)

usage() {
  cat <<'EOF'
用法:
  build_zip.sh [选项] <目录名|all>

说明:
  <目录名>   将仓库根目录下名为 <目录名> 的子目录打成 zip，输出到 dist/<目录名>.zip
  all        为每个技能子目录各打一个 zip，再将这些 zip 一并打入外层压缩包:
             dist/openocta-skills-all-YYYYMMDD-HHMMSS.tar.gz

选项:
  -h, --help  显示本帮助并退出

注意:
  - 「all」会跳过模版目录 template、输出目录 dist，以及以 '.' 开头的隐藏目录。
  - 需要系统可用命令: zip, tar

示例:
  ./build_zip.sh k8s_skill
  ./build_zip.sh all
EOF
}

should_skip_dir() {
  local base="$1"
  local lower
  lower="$(printf '%s' "${base}" | tr '[:upper:]' '[:lower:]')"
  if [[ "${base}" == .* ]]; then
    return 0
  fi
  local s
  for s in "${SKIP_NAMES[@]}"; do
    if [[ "${lower}" == "${s}" ]]; then
      return 0
    fi
  done
  return 1
}

list_skill_dirs() {
  local d base
  for d in "${ROOT}"/*; do
    [[ -d "${d}" ]] || continue
    base="$(basename "${d}")"
    if should_skip_dir "${base}"; then
      continue
    fi
    printf '%s\n' "${base}"
  done | LC_ALL=C sort
}

zip_skill_dir() {
  local name="$1"
  local src="${ROOT}/${name}"
  if [[ ! -d "${src}" ]]; then
    echo "错误: 目录不存在: ${src}" >&2
    exit 1
  fi
  mkdir -p "${DIST}"
  local out="${DIST}/${name}.zip"
  rm -f "${out}"
  (cd "${ROOT}" && zip -r "${out}" "${name}" -x "*.DS_Store" >/dev/null)
  echo "已生成: ${out}"
}

run_all() {
  mkdir -p "${DIST}"
  local skills=()
  local line
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -n "${line}" ]] && skills+=("${line}")
  done < <(list_skill_dirs)

  if [[ ${#skills[@]} -eq 0 ]]; then
    echo "错误: 未找到可打包的技能目录（已跳过 template、dist 与隐藏目录）。" >&2
    exit 1
  fi

  BUILD_ZIP_BUNDLE_TMP="$(mktemp -d "${DIST}/.bundle.XXXXXX")"
  trap '_bundle_cleanup' EXIT

  local s
  for s in "${skills[@]}"; do
    zip_skill_dir "${s}"
    mv "${DIST}/${s}.zip" "${BUILD_ZIP_BUNDLE_TMP}/"
  done

  local stamp ts_bundle
  stamp="$(date +%Y%m%d-%H%M%S)"
  ts_bundle="${DIST}/openocta-skills-all-${stamp}.tar.gz"

  tar -czf "${ts_bundle}" -C "${BUILD_ZIP_BUNDLE_TMP}" .
  echo "已生成外层压缩包（内含 ${#skills[@]} 个 zip）: ${ts_bundle}"

  for s in "${skills[@]}"; do
    mv "${BUILD_ZIP_BUNDLE_TMP}/${s}.zip" "${DIST}/"
  done

  trap - EXIT
  _bundle_cleanup
}

main() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
  fi

  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
  esac

  local target="$1"
  if [[ $# -gt 1 ]]; then
    echo "错误: 参数过多。使用 --help 查看用法。" >&2
    exit 1
  fi

  if [[ "${target}" == "all" ]]; then
    run_all
    exit 0
  fi

  local src="${ROOT}/${target}"
  if [[ ! -d "${src}" ]]; then
    echo "错误: 目录不存在: ${target}" >&2
    exit 1
  fi

  zip_skill_dir "${target}"
}

main "$@"
