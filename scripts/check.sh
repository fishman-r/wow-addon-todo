#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
addon_name="Todo"
addon_dir="$project_root/$addon_name"
toc_file="$addon_dir/$addon_name.toc"
core_file="$addon_dir/$addon_name.lua"
ui_file="$addon_dir/UI.lua"

if [[ ! -f "$toc_file" ]]; then
    echo "缺少 TOC 文件：$toc_file" >&2
    exit 1
fi

grep -q '^## Interface: 38002$' "$toc_file"
grep -q '^## Version: 1.0.0-beta.1$' "$toc_file"
grep -q '^## SavedVariables: TodoDB, TitanFlowHelloDB$' "$toc_file"
grep -q 'OptimizeTaskRoute' "$addon_dir/Planner.lua"
grep -q 'GetEffectiveMarketPrice' "$addon_dir/Valuation.lua"
grep -q 'StartTaskTracking' "$addon_dir/Tracking.lua"
grep -q 'Compat38002' "$addon_dir/Compat38002.lua"
grep -q 'QUEST_TURNED_IN' "$core_file"
grep -q 'CreateMainWindow' "$ui_file"
grep -q 'SlashCmdList.TODO' "$core_file"
grep -q 'PLAYER_ENTERING_WORLD' "$core_file"

while IFS= read -r toc_entry; do
    toc_entry="${toc_entry%$'\r'}"
    if [[ -z "$toc_entry" || "$toc_entry" == \#* ]]; then
        continue
    fi

    if [[ ! -f "$addon_dir/$toc_entry" ]]; then
        echo "TOC 引用了不存在的文件：$toc_entry" >&2
        exit 1
    fi
done < "$toc_file"

lua_files=()
while IFS= read -r toc_entry; do
    toc_entry="${toc_entry%$'\r'}"
    if [[ "$toc_entry" == *.lua ]]; then
        lua_files+=("$addon_dir/$toc_entry")
    fi
done < "$toc_file"
if command -v luac >/dev/null 2>&1; then
    for lua_file in "${lua_files[@]}"; do
        luac -p "$lua_file"
    done
elif command -v npx >/dev/null 2>&1; then
    for lua_file in "${lua_files[@]}"; do
        npx --yes luaparse "$lua_file" >/dev/null
    done
else
    echo "警告：未找到 luac 或 npx，跳过 Lua 语法解析。" >&2
fi

test_files=(
    "$project_root/tests/recommendations.lua"
    "$project_root/tests/daily_recommender.lua"
    "$project_root/tests/wow_smoke.lua"
)
if command -v lua >/dev/null 2>&1; then
    for test_file in "${test_files[@]}"; do
        (cd "$project_root" && lua "$test_file")
    done
elif command -v npx >/dev/null 2>&1; then
    for test_file in "${test_files[@]}"; do
        test_output="$(cd "$project_root" && npx --yes --package fengari-node-cli fengari "$test_file" 2>&1)"
        printf '%s\n' "$test_output"
        if grep -q 'stack traceback:' <<<"$test_output"; then
            echo "离线 Lua 测试失败：$test_file" >&2
            exit 1
        fi
    done
else
    echo "警告：未找到 lua 或 npx，跳过离线 Lua 测试。" >&2
fi

echo "结构检查通过：$addon_name"
