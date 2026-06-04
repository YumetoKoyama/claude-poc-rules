#!/usr/bin/env bash
# _common/scripts/check-truncation.sh
#
# 第1層（決定論）: 指定ファイル/ディレクトリ配下のテキストファイルが
# 切断・破損していないかを検出し、review JSON と同じ findings 形式で
# stdout に JSON 配列を出力する。
#
# 検出内容:
#   - BLOCK: Invalid UTF-8（マルチバイト文字途中で切断）
#   - SUGGEST: 日本語末尾で句読点等なく終わる（途中切断の疑い）
#   - SUGGEST: Markdown テーブル行が | で閉じていない
#   - SUGGEST: 末尾近傍で 括弧（／(／「／『 が閉じていない
#   - NIT: 末尾改行なし
#
# Usage:
#   check-truncation.sh <path> [<path> ...]
#     <path> : ファイルまたはディレクトリ。複数指定可。
#
# 出力: findings JSON 配列を stdout に。例:
#   [
#     {"severity":"BLOCK","path":"docs/x.md","line":null,
#      "category":"completeness",
#      "message":"...","suggested_fix":"..."}
#   ]
#
# Exit:
#   0: 正常（findings の有無に関わらず）
#   2: 引数エラー、ファイル読込エラー等

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "ERROR: パスを 1 つ以上指定してください" >&2
  echo "Usage: check-truncation.sh <path> [<path> ...]" >&2
  exit 2
fi

python3 - "$@" <<'PY'
import json, os, sys

TEXT_EXTS = {
    ".md", ".yaml", ".yml", ".json", ".txt",
    ".java", ".ts", ".tsx", ".js", ".jsx",
    ".html", ".css", ".py", ".sh",
    ".properties", ".xml", ".toml",
}
SKIP_DIRS = {
    ".git", "node_modules", ".skills-state", ".skills-state-test",
    "target", "build", "dist", "coverage", "playwright-report",
    ".venv", "__pycache__",
}

def gather(paths):
    out = []
    for p in paths:
        if os.path.isfile(p):
            out.append(p)
        elif os.path.isdir(p):
            for dp, dn, fn in os.walk(p):
                dn[:] = [d for d in dn if d not in SKIP_DIRS and not d.startswith(".") or d in {".claude", ".github"}]
                # 上の条件だと .claude/.github は通すがその他の隠しは弾く
                for f in fn:
                    ext = os.path.splitext(f)[1].lower()
                    if ext in TEXT_EXTS:
                        out.append(os.path.join(dp, f))
    return out

NATURAL_END = set("。.!?！？:：;；)\"]}>」』）｝】>`*-_=#|/\\")

def check(path):
    findings = []
    try:
        with open(path, "rb") as fp:
            data = fp.read()
    except OSError as e:
        return [{
            "severity": "SUGGEST", "path": path, "line": None,
            "category": "completeness",
            "message": f"ファイルが読み込めません: {e}",
            "suggested_fix": "ファイル権限・存在を確認する",
        }]
    if len(data) == 0:
        return findings  # 0-byte は対象外

    # 1) Invalid UTF-8 → BLOCK
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as e:
        ctx_start = max(0, e.start - 30)
        ctx_end = min(len(data), e.end + 30)
        ctx = data[ctx_start:ctx_end].decode("utf-8", errors="replace")
        findings.append({
            "severity": "BLOCK", "path": path, "line": None,
            "category": "completeness",
            "message": f"ファイルがマルチバイト文字途中で切断されています（Invalid UTF-8 at byte {e.start}-{e.end}, file size {len(data)}）。コンテキスト: ...{ctx}...",
            "suggested_fix": "切断箇所を確認し、本来あるべき末尾を補完してファイルを完成させる",
        })
        return findings

    stripped = text.rstrip("\n").rstrip()
    lines = stripped.splitlines() if stripped else []
    last_line = lines[-1] if lines else ""
    last_char = last_line[-1] if last_line else ""

    # 2) 末尾が日本語文字で句読点等なく終わる → SUGGEST（リスト末尾は除外）
    if last_char and last_char not in NATURAL_END:
        # 日本語ブロック以降の文字なら切断の疑いあり
        if ord(last_char) >= 0x2E80:
            # ただし list item（先頭 -/*/数字.）で末尾の体言止め名詞は除外しにくいので
            # 「文の途中（、、で終わるなど）」「、で終わる」「括弧途中」を強めに見る
            is_list_item = bool(last_line.lstrip().startswith(("-", "*", "+")) or
                                (last_line.lstrip()[:2].rstrip(".").isdigit() if last_line.lstrip()[:2].rstrip(".") else False))
            # リスト項目でも文の途中（、で終わるなど）なら切断疑い
            looks_truncated = (
                last_char in "、" or
                "（" in last_line[-30:] and "）" not in last_line[-30:] or
                (not is_list_item)
            )
            if looks_truncated:
                findings.append({
                    "severity": "SUGGEST", "path": path, "line": len(lines),
                    "category": "completeness",
                    "message": f"末尾が日本語文字で句読点等なく終わっています（切断の可能性）。末尾: ...{last_line[-40:]}",
                    "suggested_fix": "意図的な末尾ならそのまま。途中で切れている場合は補完する",
                })

    # 3) Markdown テーブル行が | で閉じていない
    if last_line.lstrip().startswith("|") and not last_line.rstrip().endswith("|"):
        findings.append({
            "severity": "SUGGEST", "path": path, "line": len(lines),
            "category": "completeness",
            "message": f"Markdown テーブル行が `|` で閉じていません（切断の可能性）。末尾: {last_line[-60:]}",
            "suggested_fix": "テーブル行を完成させる（最後のセル + 末尾の `|`）",
        })

    # 4) 末尾 200 文字以内で開き括弧が閉じていない
    tail = text[-200:]
    pair_list = [("（", "）"), ("「", "」"), ("『", "』")]
    for o_ch, c_ch in pair_list:
        if tail.count(o_ch) > tail.count(c_ch):
            findings.append({
                "severity": "SUGGEST", "path": path, "line": len(lines),
                "category": "completeness",
                "message": f"末尾近傍で `{o_ch}` が `{c_ch}` で閉じられていません（切断の可能性）。末尾: ...{tail[-80:]}",
                "suggested_fix": f"`{o_ch}` の対応する `{c_ch}` を追加するか、本来の末尾を復元する",
            })
            break  # 1 ファイル 1 件まで

    # 5) 末尾改行なし → NIT
    if not text.endswith("\n"):
        findings.append({
            "severity": "NIT", "path": path, "line": len(lines),
            "category": "style",
            "message": "ファイル末尾に改行がありません",
            "suggested_fix": "末尾に改行を 1 行追加する（POSIX 慣習）",
        })

    return findings

all_findings = []
for p in gather(sys.argv[1:]):
    try:
        all_findings.extend(check(p))
    except Exception as e:
        all_findings.append({
            "severity": "SUGGEST", "path": p, "line": None,
            "category": "completeness",
            "message": f"切断チェック中に例外: {e}",
            "suggested_fix": "ファイルを目視確認する",
        })

# severity 順: BLOCK > SUGGEST > NIT、同 severity 内ではパス順
order = {"BLOCK": 0, "SUGGEST": 1, "NIT": 2}
all_findings.sort(key=lambda x: (order.get(x["severity"], 99), x["path"]))

json.dump(all_findings, sys.stdout, ensure_ascii=False, indent=2)
sys.stdout.write("\n")
PY
