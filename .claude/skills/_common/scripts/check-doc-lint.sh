#!/usr/bin/env bash
# _common/scripts/check-doc-lint.sh
#
# 用途（RC-11）:
#   ドキュメントの AI 生成ノイズを決定論で棚卸しする。
#     1. 非日本語文字の混入検出（ハングル 가-힣・ハングル字母・簡体字特有字 等）
#     2. 用語集準拠の表記揺れ（用語集.md の「同義」エントリが本文で混在）
#     3. TODO / FIXME / XXX の残置棚卸し
#   1 はノイズの強い指標なので NG（exit 1）、2・3 は WARN（棚卸し出力・非ブロッキング）。
#
# Usage:
#   check-doc-lint.sh <path> [<path> ...]
#     <path> : ファイルまたはディレクトリ（docs/requirements/ や docs/design/ を渡す）
#
# Exit:
#   0: 非日本語混入なし（WARN は残っていてよい）
#   1: 非日本語文字の混入を検出
#   2: 引数エラー / python3 不在

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "ERROR: パスを 1 つ以上指定してください" >&2
  echo "Usage: check-doc-lint.sh <path> [<path> ...]" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません" >&2; exit 2
fi

python3 - "$@" <<'PY'
import sys, os, re

paths = sys.argv[1:]
SKIP_DIRS = {".git", "node_modules", ".skills-state", "target", "build", "dist",
            "coverage", ".venv", "__pycache__"}

def gather(ps):
    out = []
    for p in ps:
        if os.path.isfile(p) and p.endswith(".md"):
            out.append(p)
        elif os.path.isdir(p):
            for dp, dn, fn in os.walk(p):
                dn[:] = [d for d in dn if d not in SKIP_DIRS]
                for f in fn:
                    if f.endswith(".md"):
                        out.append(os.path.join(dp, f))
    return out

files = gather(paths)
if not files:
    print("INFO: 対象 .md がありません（検査をスキップ）")
    sys.exit(0)

# 非日本語混入: ハングル音節・字母、ハングル互換字母、簡体字特有レンジの一部
hangul_re = re.compile(r"[가-힣ᄀ-ᇿ㄰-㆏]")
# 簡体字でよく出る、日本語常用にほぼ無い字（代表例）
# 日本語常用漢字（国/来 等の日中共通字）は除外し、日本語に存在しない簡体字専用字のみ
simplified_sample = "们这对说时过还经习题让边专东车书风长队节门问见观银钱"
simplified_re = re.compile("[" + re.escape(simplified_sample) + "]")
# キリル文字（混入ノイズ）
cyrillic_re = re.compile(r"[Ѐ-ӿ]")

ng = 0
# XXX は「ID 体系 | 形式例 | 用途」のような凡例表の形式例列（BR-XXX, SC-XXX 等）で使用されるため、
# テーブル行内の形式例パターン（英字-XXX / 英字XXX）はホワイトリスト化してWARN対象外とする
todo_re = re.compile(r"\b(TODO|FIXME)\b|(?<![A-Z\-])XXX\b(?!\s*\|)(?![\s\-]?[0-9])")
# 凡例プレースホルダー（BR-XXX, SC-XXX, ID-XXX 等）を除外する追加パターン
placeholder_re = re.compile(r"\b[A-Z]{1,5}-XXX\b")

# 用語集の同義エントリ収集（任意）
glossary_synonyms = []  # list of (term, synonym)
for f in files:
    if os.path.basename(f) == "用語集.md":
        with open(f, encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                # 「A（同義: B）」「A ⇔ B」「A / B（同義）」のような行から拾う簡易抽出
                m = re.search(r"([^\s|（(]+)\s*[（(]?\s*同義[:：]?\s*([^\s|）)]+)", ln)
                if m:
                    glossary_synonyms.append((m.group(1).strip(), m.group(2).strip()))

for f in files:
    with open(f, encoding="utf-8", errors="replace") as fh:
        lines = fh.readlines()
    for i, ln in enumerate(lines, 1):
        # コードブロック内・インラインコードは簡易にスキップしない（混入は本文以外でも問題）
        for label, rx in (("ハングル", hangul_re), ("簡体字（推定）", simplified_re), ("キリル文字", cyrillic_re)):
            mm = rx.search(ln)
            if mm:
                snippet = ln.strip()[:60]
                print(f"NG: {f}:{i} に{label}の混入を検出: …{snippet}…")
                ng = 1
        for tm in todo_re.finditer(ln):
            # 凡例プレースホルダー（BR-XXX, AC-XXX 等）が含まれる行はスキップ
            if placeholder_re.search(ln):
                continue
            print(f"WARN: {f}:{i} に {tm.group()} が残置: {ln.strip()[:80]}")

# 用語集準拠の表記揺れ（同義ペアが同一ファイルに両方現れる→片方に寄せる候補）
if glossary_synonyms:
    for f in files:
        if os.path.basename(f) == "用語集.md":
            continue
        with open(f, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        for a, b in glossary_synonyms:
            if a and b and a in text and b in text:
                print(f"WARN: {f} に同義表記「{a}」と「{b}」が混在（用語集準拠で統一を検討）")

if ng:
    print("")
    print("ドキュメントに非日本語文字の混入があります（RC-11）。日本語へ修正してください。")
    sys.exit(1)
print("OK: 非日本語文字の混入はありません（RC-11）。WARN（TODO 残置・表記揺れ）は棚卸し対象。")
PY
