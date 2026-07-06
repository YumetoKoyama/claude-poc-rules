#!/usr/bin/env bash
# _common/scripts/check-truncation.sh
#
# 第1層（決定論）: 指定ファイル/ディレクトリ配下のテキストファイルが
# 切断・破損していないかを検出し、review JSON と同じ findings 形式で
# stdout に JSON 配列を出力する。
#
# 検出内容:
#   - BLOCK: Invalid UTF-8（マルチバイト文字途中で切断）
#   - SUGGEST: 日本語末尾で句読点等なく終わる（途中切断の疑い。体言止めは許容）
#   - SUGGEST: Markdown テーブル行が | で閉じていない
#   - SUGGEST: 末尾近傍で 括弧（／(／「／『 が閉じていない
#   - SUGGEST: 連続する ASCII-only 行が 5 行以上（英語混入の疑い・category=i18n。RC-11）
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

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません（check-truncation を実行できません）" >&2
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
                dn[:] = [d for d in dn if (d not in SKIP_DIRS and not d.startswith(".")) or d in {".claude", ".github"}]
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

    # 2) 末尾が日本語文字で句読点等なく終わる → SUGGEST（リスト末尾・体言止めは除外）
    #    RC-11: 体言止め（名詞・カタカナ語・漢字で終わる見出し的な文）を許容して
    #    false positive を削減する。明確に切断と判断できる場合のみ指摘する。
    if last_char and last_char not in NATURAL_END:
        # 日本語ブロック以降の文字なら切断の疑いあり
        if ord(last_char) >= 0x2E80:
            ls = last_line.lstrip()
            is_list_item = bool(ls.startswith(("-", "*", "+")) or
                                (ls[:2].rstrip(".").isdigit() if ls[:2].rstrip(".") else False))
            is_heading = ls.startswith("#")
            # 体言止め許容: 末尾が名詞相当（漢字・カタカナ・英数）で終わり、
            # 直前に明確な「文の途中」シグナルが無ければ切断とみなさない。
            # 「文の途中」シグナル = 助詞・読点・接続表現・開き括弧未閉じ で終わる。
            CONNECTIVE_TAIL = (
                "、", "，",
                "は", "が", "を", "に", "へ", "と", "で", "も", "や", "の",
                "て", "し", "り",  # 連用中止・て形（文が続く疑い）
            )
            open_paren_unclosed = ("（" in last_line[-30:] and "）" not in last_line[-30:])
            looks_truncated = (
                last_char in CONNECTIVE_TAIL or
                open_paren_unclosed
            )
            # 見出し・リスト項目・体言止め（上記シグナルなし）は許容（指摘しない）
            if looks_truncated and not is_heading:
                findings.append({
                    "severity": "SUGGEST", "path": path, "line": len(lines),
                    "category": "completeness",
                    "message": f"末尾が日本語の文の途中（助詞・読点・括弧途中）で終わっています（切断の可能性）。末尾: ...{last_line[-40:]}",
                    "suggested_fix": "意図的な末尾（体言止め等）ならそのまま。途中で切れている場合は補完する",
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

    # 6) 連続 ASCII-only 行（コードブロック・テーブル・URL 以外）が 5 行以上 → SUGGEST（category=i18n）
    #    RC-11 / RC-09: 日本語で記述する原則に反する英語混入を機械検出する。
    if path.endswith(".md"):
        in_code_block = False
        ascii_run_start = None
        ascii_run_count = 0
        for i, line in enumerate(text.splitlines(), 1):
            stripped_line = line.strip()
            if stripped_line.startswith("```"):
                in_code_block = not in_code_block
                ascii_run_count = 0
                continue
            if in_code_block:
                continue
            # テーブル行・URL・$ref・空行・HTML コメント・Mermaid ディレクティブはスキップ
            if (stripped_line.startswith("|") or
                stripped_line.startswith("http") or
                stripped_line.startswith("$ref") or
                stripped_line == "" or
                stripped_line.startswith("<!--")):
                ascii_run_count = 0
                continue
            is_ascii_only = all(ord(c) < 0x80 for c in stripped_line)
            if is_ascii_only and len(stripped_line) > 20:
                if ascii_run_count == 0:
                    ascii_run_start = i
                ascii_run_count += 1
            else:
                ascii_run_count = 0
            if ascii_run_count >= 5:
                findings.append({
                    "severity": "SUGGEST", "path": path, "line": ascii_run_start,
                    "category": "i18n",
                    "message": f"L{ascii_run_start} 付近から連続 {ascii_run_count} 行以上が ASCII のみです（英語文章の混入の可能性）。日本語で記述する原則に沿っているか確認してください",
                    "suggested_fix": "英語の説明文は日本語に翻訳する。コードブロック・ID・URL 等は除外して問題なし",
                })
                ascii_run_count = 0
                break  # 1 ファイル 1 件まで

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
