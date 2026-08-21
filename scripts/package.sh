#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
addon_name="Todo"
toc_file="$project_root/$addon_name/$addon_name.toc"
dist_dir="$project_root/dist"

"$script_dir/check.sh"

version="$(awk -F': ' '$1 == "## Version" { print $2 }' "$toc_file")"
if [[ -z "$version" ]]; then
    echo "无法从 TOC 读取版本号" >&2
    exit 1
fi

archive="$dist_dir/$addon_name-$version.zip"
mkdir -p "$dist_dir"
rm -f "$archive"

(
    cd "$project_root"
    /usr/bin/zip -q -r "$archive" "$addon_name" -x '*.DS_Store'
)

echo "打包完成：$archive"
