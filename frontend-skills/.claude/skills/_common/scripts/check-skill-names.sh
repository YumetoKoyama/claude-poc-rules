#!/usr/bin/env bash
# _common/scripts/check-skill-names.sh
#
# 第1層（決定論）: *-loop オーケストレータが SlashCommand で呼ぶ skill 名が、
# 実在する skill（.claude/skills/<dir>/SKILL.md の frontmatter name:）と
# 一致しているかを機械的に検証する。
#
# 目的: 「implement-loop が /review-implement を呼ぶが実 skill 名は
#        review-implementation」のような不一致（ループ起動失敗）を CI / 手動で検出する。
#
# Usage:
#   check-skill-names.sh [skills_dir]
#     [skills_dir] : 省略時は本スクリプトの親（.claude/skills）
#
# Exit:
#   0: すべての参照が解決可能
#   1: 未解決の slash command 参照あり（詳細を stderr に出力）
#   2: 引数・環境エラー

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"

if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "ERROR: skills ディレクトリが見つかりません: $SKILLS_DIR" >&2
  exit 2
fi

python3 - "$SKILLS_DIR" <<'PY'
import os, re, sys

skills_dir = sys.argv[1]

# 実在する skill 名（frontmatter の name:）を収集
known = set()
for d in os.listdir(skills_dir):
    sp = os.path.join(skills_dir, d, "SKILL.md")
    if not os.path.isfile(sp):
        continue
    with open(sp, encoding="utf-8") as f:
        for line in f:
            m = re.match(r'^name:\s*(\S+)', line)
            if m:
                known.add(m.group(1).strip())
                break

# *-loop の SKILL.md から `/skill-name` 形式の SlashCommand 参照を抽出して検証
SLASH = re.compile(r'`/([a-z0-9][a-z0-9-]*)`')
problems = []
for d in os.listdir(skills_dir):
    if not d.endswith("-loop"):
        continue
    sp = os.path.join(skills_dir, d, "SKILL.md")
    if not os.path.isfile(sp):
        continue
    with open(sp, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            for name in SLASH.findall(line):
                if name not in known:
                    problems.append((d, i, name, line.strip()))

if problems:
    print("NG: 未解決の SlashCommand 参照があります（loop が起動しません）", file=sys.stderr)
    for d, i, name, ln in problems:
        print(f"  - {d}/SKILL.md:{i}  /{name}  ->  該当する skill 名が存在しません", file=sys.stderr)
        print(f"      {ln}", file=sys.stderr)
    print(f"  既知の skill 名: {sorted(known)}", file=sys.stderr)
    sys.exit(1)

print("OK: すべての *-loop の SlashCommand 参照は実在する skill 名に解決できます")
PY
