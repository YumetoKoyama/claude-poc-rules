#!/usr/bin/env bash
# _common/scripts/validate-review-json.sh
#
# review skill が書き出した review JSON が妥当な JSON か + スキーマに適合するか検証する（RC-08）。
# - 構文 OK かつスキーマ OK: exit 0、stdout に "OK" を 1 行
# - 構文エラー: exit 1、stderr にエラー位置と前後コンテキストを出力
# - スキーマ違反: exit 1、stderr に違反一覧を出力
#
# スキーマ要件:
#   - トップレベルはオブジェクトで "findings" キーを持つ
#   - findings は配列
#   - 各 finding はオブジェクトで、必須キー severity / category / path / message / suggested_fix を持つ
#   - severity は BLOCK / SUGGEST / NIT のいずれか
#
# 【P-10 追加（2026-07-02）】PASS の説明可能性:
#   - checked_aspects（検査済み観点リスト）/ uncovered_areas（未カバー領域）が存在する場合は
#     形式を検証する（aspect/status 必須、status は checked/partial/not-checked）
#   - checked_aspects が無い場合は WARN を stderr に出す（後方互換のため fail はしないが、
#     format-review-json.sh 経由の生成では必ず付与される。手書き JSON の残存検知に使う）
#
# Usage:
#   validate-review-json.sh <path-to-review.json>
#
# review skill は本スクリプトを Write 直後に呼び、失敗時は自己修正して
# 再 Write → 再検証する。3 回失敗したら標準出力に
# "ERROR: invalid JSON after 3 attempts" を出して停止すること。
# （format-review-json.sh を使う場合、生成と検証は機械化されるためこのリトライは通常発生しない）
#
# Exit:
#   0: 構文・スキーマともに OK
#   1: 構文エラー または スキーマ違反
#   2: 引数エラー / ファイル不在 / python3 不在

set -euo pipefail

JSON_PATH="${1:-}"

if [[ -z "$JSON_PATH" ]]; then
  echo "ERROR: review JSON のパスが指定されていません" >&2
  exit 2
fi

if [[ ! -f "$JSON_PATH" ]]; then
  echo "ERROR: ファイルが存在しません: $JSON_PATH" >&2
  exit 2
fi

# python3 不在は fail-closed（検証不能 = 不合格扱い）
if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 が見つかりません（review JSON のスキーマ検証ができません）" >&2
  exit 2
fi

# 構文 + スキーマ検証
python3 - "$JSON_PATH" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

# 1) 構文検証
try:
    data = json.loads(content)
except json.JSONDecodeError as e:
    char_offset = e.pos
    start = max(0, char_offset - 200)
    end = min(len(content), char_offset + 200)
    context = content[start:end]
    print(f"ERROR: invalid JSON at line {e.lineno} col {e.colno} (char {e.pos})", file=sys.stderr)
    print(f"  reason: {e.msg}", file=sys.stderr)
    print(f"  context (±200 chars around char {e.pos}):", file=sys.stderr)
    print("  ----", file=sys.stderr)
    print(f"  {context!r}", file=sys.stderr)
    print("  ----", file=sys.stderr)
    print("  hint: ASCII の \" \\ や生の改行が文字列内で未エスケープになっていないか確認", file=sys.stderr)
    print("  hint: 手書き JSON をやめ、format-review-json.sh（TSV→JSON 機械生成）を使うこと（P-08）", file=sys.stderr)
    sys.exit(1)

# 2) スキーマ検証
ALLOWED_SEVERITY = {"BLOCK", "SUGGEST", "NIT"}
ALLOWED_ASPECT_STATUS = {"checked", "partial", "not-checked"}
REQUIRED_KEYS = ("severity", "category", "path", "message", "suggested_fix")
errors = []
warns = []

if not isinstance(data, dict):
    errors.append("トップレベルが JSON オブジェクトではありません")
else:
    if "findings" not in data:
        errors.append('必須キー "findings" がありません')
    else:
        findings = data["findings"]
        if not isinstance(findings, list):
            errors.append('"findings" が配列ではありません')
        else:
            for i, fnd in enumerate(findings):
                if not isinstance(fnd, dict):
                    errors.append(f"findings[{i}] がオブジェクトではありません")
                    continue
                for k in REQUIRED_KEYS:
                    if k not in fnd:
                        errors.append(f'findings[{i}] に必須キー "{k}" がありません')
                sev = fnd.get("severity")
                if sev is not None and sev not in ALLOWED_SEVERITY:
                    errors.append(
                        f'findings[{i}].severity が不正です: {sev!r}'
                        f"（許可値: {sorted(ALLOWED_SEVERITY)}）"
                    )
                # category / path / message は非空文字列であること
                for k in ("category", "path", "message", "suggested_fix"):
                    v = fnd.get(k)
                    if k in fnd and (not isinstance(v, str) or v.strip() == ""):
                        errors.append(f'findings[{i}].{k} は非空の文字列である必要があります: {v!r}')
                # related_files は存在する場合、文字列の配列であること
                rf = fnd.get("related_files")
                if rf is not None:
                    if not isinstance(rf, list):
                        errors.append(f'findings[{i}].related_files が配列ではありません: {rf!r}')
                    else:
                        for j, item in enumerate(rf):
                            if not isinstance(item, str) or item.strip() == "":
                                errors.append(f'findings[{i}].related_files[{j}] は非空の文字列である必要があります: {item!r}')

    # 3) P-10: 検査観点（checked_aspects / uncovered_areas）の検証
    ca = data.get("checked_aspects")
    if ca is None:
        warns.append('checked_aspects（検査済み観点リスト）がありません。PASS の検査範囲が説明できません。'
                     'format-review-json.sh --aspects で必ず付与すること（P-10 / U-2）')
    elif not isinstance(ca, list):
        errors.append(f'checked_aspects が配列ではありません: {type(ca).__name__}')
    else:
        for i, a in enumerate(ca):
            if not isinstance(a, dict):
                errors.append(f"checked_aspects[{i}] がオブジェクトではありません")
                continue
            if not isinstance(a.get("aspect"), str) or not a.get("aspect", "").strip():
                errors.append(f"checked_aspects[{i}].aspect は非空の文字列である必要があります")
            st = a.get("status")
            if st not in ALLOWED_ASPECT_STATUS:
                errors.append(f"checked_aspects[{i}].status が不正です: {st!r}（許可値: {sorted(ALLOWED_ASPECT_STATUS)}）")
            if st in ("partial", "not-checked") and not (a.get("note") or "").strip():
                errors.append(f"checked_aspects[{i}]: partial/not-checked の観点は note（理由）が必須です")
    ua = data.get("uncovered_areas")
    if ua is not None and not isinstance(ua, list):
        errors.append(f'uncovered_areas が配列ではありません: {type(ua).__name__}')

for w in warns:
    print(f"WARN: {w}", file=sys.stderr)

if errors:
    print("ERROR: review JSON のスキーマ検証に失敗しました:", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    print("  required per finding: severity(BLOCK|SUGGEST|NIT) / category / path / message / suggested_fix", file=sys.stderr)
    sys.exit(1)

print("OK")
PY
