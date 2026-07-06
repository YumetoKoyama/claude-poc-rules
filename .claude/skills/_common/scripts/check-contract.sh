#!/usr/bin/env bash
# _common/scripts/check-contract.sh
#
# 用途（RC-02 界面契約の単一正典化・縦串突合）:
#   API YAML から operationId 一覧と ErrorResponse / コード値（enum）の
#   プロパティ名を抽出し、画面 md・認可設計・（あれば）実装 DTO と機械突合する。
#   「設計に書いたが繋がっていない」「実フィールド名が乖離している」を決定論で検出する。
#
# 検出:
#   1. 画面 md が参照する operationId が API YAML に実在するか（不在 = NG）
#   2. 認可設計（セキュリティ設計.md / 認可設計.md）に各 operationId の行があるか（不在 = WARN）
#   3. _common.yaml の ErrorResponse プロパティ名（code/message/details 等）が
#      共通部品設計.md / 実装 DTO と一致するか（乖離 = NG）
#   4. 同名スキーマが複数 YAML で重複定義されていないか（重複 = NG）
#      ※ (D) $ref 参照のみのブロックは実体定義ではないため除外する
#   5. 画面 md（screens/*.md）の凡例コード値（CODE=表示名）が _common.yaml の
#      enum 値と一致するか。どの enum にも無い値（Tier A）／明示された enum 型名と
#      取り違えた値（Tier B）を検出（shared-canon §4 4層統一・コード値乖離 = NG）
#
# Usage:
#   check-contract.sh [<docs-design-dir>] [<impl-root>]
#     <docs-design-dir> : 省略時 ./docs/design
#     <impl-root>       : 実装 DTO の探索起点（省略時は実装突合をスキップ）
#
# Exit:
#   0: 突合 OK（または対象不在で検査スキップ）
#   1: 不整合検出
#   2: 引数エラー / 必須ツール不在

set -euo pipefail

DESIGN_DIR="${1:-./docs/design}"
IMPL_ROOT="${2:-}"

API_DIR="$DESIGN_DIR/api"
COMMON_YAML="$API_DIR/_common.yaml"

if [[ ! -d "$DESIGN_DIR" ]]; then
  echo "INFO: 設計ディレクトリがありません: $DESIGN_DIR（検査をスキップ）"
  exit 0
fi
if [[ ! -d "$API_DIR" ]]; then
  echo "INFO: API ディレクトリがありません: $API_DIR（検査をスキップ）"
  exit 0
fi

ng=0

# --- 1. operationId 一覧を全 YAML から抽出 ---
opids_file="$(mktemp)"
# クリーンアップは 1 関数に集約する（trap の二重定義による上書き漏れを防止）。
# enum_all / enum_by は後続ブロックで生成されるため :- で未設定時も安全に展開する。
_cleanup() { rm -f "$opids_file" "${enum_all:-}" "${enum_by:-}"; }
trap _cleanup EXIT
grep -rhoE 'operationId:[[:space:]]*[A-Za-z0-9_]+' "$API_DIR" 2>/dev/null \
  | sed -E 's/operationId:[[:space:]]*//' | sort -u > "$opids_file" || true

opid_count="$(wc -l < "$opids_file" | tr -d ' ')"
echo "INFO: API operationId 数: $opid_count"

# --- 1. 画面 md の参照 operationId が実在するか ---
SCREENS_DIR="$DESIGN_DIR/screens"
if [[ -d "$SCREENS_DIR" ]]; then
  # 画面 md 中に現れる camelCase 識別子のうち、operationId として参照されていそうなものを抽出。
  # 厳密化のため「operationId」「API」見出し配下の語、または既知 operationId と一致する語を突合する。
  while IFS= read -r scr; do
    [[ -z "$scr" ]] && continue
    # 画面 md が「operationId」という語に続けて明示参照する識別子のみを厳格突合する
    # （誤検知防止のため、operationId: xxx / operationId `xxx` / operationId xxx の形のみ対象）。
    while IFS= read -r line; do
      # 「operationId」より後ろに現れる最初の camelCase 識別子を抽出
      cand="$(printf '%s' "$line" | sed -E 's/.*[oO]peration[iI]d[`:[:space:]]*//'               | grep -oE '[a-z][A-Za-z0-9]+' | head -1 || true)"
      [[ -z "$cand" ]] && continue
      [[ "$cand" == "operationId" ]] && continue
      if ! grep -qxF "$cand" "$opids_file"; then
        echo "NG: $scr が参照する operationId 「$cand」が API YAML に存在しません"
        ng=1
      fi
    done < <(grep -iE 'operationId' "$scr" 2>/dev/null || true)
  done < <(find "$SCREENS_DIR" -name '*.md' 2>/dev/null)
fi

# --- 2. 認可設計に各 operationId の行があるか（WARN） ---
authz_files=()
for f in "$DESIGN_DIR/認可設計.md" "$DESIGN_DIR/セキュリティ設計.md"; do
  [[ -f "$f" ]] && authz_files+=("$f")
done
if [[ ${#authz_files[@]} -gt 0 && "$opid_count" -gt 0 ]]; then
  missing_authz=0
  while IFS= read -r opid; do
    [[ -z "$opid" ]] && continue
    if ! grep -qhE "\b${opid}\b" "${authz_files[@]}" 2>/dev/null; then
      echo "WARN: operationId 「$opid」が認可設計（${authz_files[*]}）に現れません（public なら明記すること）"
      missing_authz=$((missing_authz+1))
    fi
  done < "$opids_file"
  [[ $missing_authz -gt 0 ]] && echo "INFO: 認可設計に未掲載の operationId が $missing_authz 件（詳細は check-authorization-coverage.sh）"
fi

# --- 3. ErrorResponse プロパティ名の正典一致 ---
if [[ -f "$COMMON_YAML" ]]; then
  # _common.yaml の ErrorResponse 配下の properties キーを抽出
  # ErrorResponse: の下の properties: 直下キー（properties より 2 段深いインデント）だけを抽出する。
  # type/format/items 等のスキーマ属性語は除外し、プロパティ名のみを正典として扱う。
  err_props="$(awk '
    /^[[:space:]]*ErrorResponse:[[:space:]]*$/ {inerr=1; errindent=match($0,/[^ ]/); next}
    inerr {
      ind = match($0, /[^ ]/)
      # ErrorResponse と同じか浅いインデントの新キーが来たら抜ける
      if ($0 ~ /:/ && ind <= errindent && $0 !~ /^[[:space:]]*$/) { inerr=0; inprop=0; next }
    }
    inerr && !inprop && /^[[:space:]]*properties:[[:space:]]*$/ {inprop=1; propindent=match($0,/[^ ]/); next}
    inerr && inprop {
      ind = match($0, /[^ ]/)
      if (ind <= propindent && $0 ~ /:/) { inprop=0; next }
      # properties 直下（propindent より深く、かつ最も浅いレベル）のキーのみ
      if (ind == propindent + 2 && $0 ~ /^[[:space:]]+[A-Za-z_]+:[[:space:]]*$/) {
        match($0, /[A-Za-z_]+:/);
        k=substr($0,RSTART,RLENGTH-1); gsub(/[[:space:]]/,"",k); print k
      }
    }
  ' "$COMMON_YAML" | sort -u || true)"
  if [[ -n "$err_props" ]]; then
    echo "INFO: _common.yaml ErrorResponse プロパティ: $(echo "$err_props" | tr '\n' ' ')"
    # 共通部品設計.md に ErrorResponse の再定義（独自プロパティ）が無いか軽くチェック
    CC="$DESIGN_DIR/共通部品設計.md"
    if [[ -f "$CC" ]]; then
      # 共通部品設計に errorCode 等、_common.yaml に無いプロパティ名が断定されていれば NG 候補
      # 注: `ErrorCode`（enum クラス名）は camelCase の `errorCode` フィールドとは別物のため除外する
      # grep -v でクラス名定義行（`ErrorCode enum`・`enum ErrorCode`・`public enum ErrorCode`）を除外
      if grep -iE '\berrorCode\b' "$CC" | grep -qviE '(enum\s+ErrorCode|ErrorCode\s+enum|public\s+enum\s+ErrorCode|`ErrorCode`\s+enum)' && ! echo "$err_props" | grep -qx 'errorCode'; then
        echo "NG: 共通部品設計.md に「errorCode」が現れますが _common.yaml の ErrorResponse には無い（界面契約の乖離）。_common.yaml を正典に統一すること"
        ng=1
      fi
    fi
    # 実装 DTO 突合（任意）
    if [[ -n "$IMPL_ROOT" && -d "$IMPL_ROOT" ]]; then
      if grep -rqiE '\berrorCode\b' "$IMPL_ROOT" 2>/dev/null && ! echo "$err_props" | grep -qx 'errorCode'; then
        echo "NG: 実装（$IMPL_ROOT）に「errorCode」がありますが _common.yaml の ErrorResponse に無い（Jackson シリアライズ名の乖離疑い）"
        ng=1
      fi
    fi
  fi
fi

# --- 4. 同名スキーマの重複定義 ---
# (D) $ref 参照のみのブロックは実体定義ではないため除外する。
#     スキーマ名行の直後が $ref: であれば参照として扱い、重複カウントから除外する。
dup_schema="$(awk '
  /^[[:space:]]{4,8}[A-Z][A-Za-z0-9]+:[[:space:]]*$/ {
    name = $0
    gsub(/^[[:space:]]+/, "", name)
    gsub(/:.*$/, "", name)
    # 次の非空行を読み、$ref: なら参照（スキップ）
    while ((getline nextline) > 0) {
      if (nextline ~ /^[[:space:]]*$/) continue  # 空行はスキップ
      if (nextline ~ /\$ref:/) break             # $ref 参照 → このスキーマは定義ではない
      print name                                  # 実体定義
      break
    }
  }
' "$API_DIR"/*.yaml 2>/dev/null | sort | uniq -d || true)"
if [[ -n "$dup_schema" ]]; then
  # _common.yaml にあるべき共通スキーマがリソース YAML で重複定義されているケースを警告
  while IFS= read -r sc; do
    [[ -z "$sc" ]] && continue
    # 実体定義のみをカウント（$ref 参照は除外済み）
    cnt="$(awk -v schema="$sc" '
      $0 ~ "^[[:space:]]{4,8}" schema ":[[:space:]]*$" {
        while ((getline nextline) > 0) {
          if (nextline ~ /^[[:space:]]*$/) continue
          if (nextline ~ /\$ref:/) break
          found++
          break
        }
      }
      END { print found+0 }
    ' "$API_DIR"/*.yaml 2>/dev/null)"
    if [[ "$cnt" -gt 1 ]]; then
      echo "NG: スキーマ名「$sc」が複数 YAML で実体定義されています（$cnt 箇所）。共通は _common.yaml に集約し \$ref 参照に統一すること"
      ng=1
    fi
  done <<< "$dup_schema"
fi

# --- 5. 画面 md の凡例コード値(enum)が _common.yaml の enum と一致するか（shared-canon §4 / 4層統一） ---
# screens/*.md に「CODE=表示名」形式で書かれた凡例トークンを抽出し、_common.yaml の
# enum 値と機械突合する。これは review LLM の目視に依存しがちだったコード値乖離
# （例: ApplicationStatus に PENDING/UNDER_NEGOTIATION/AGREED/DECLINED 等の無効値）を
# 決定論で確実に拾い、レビューのラウンド間のばらつき（検出漏れ→次ラウンドで露見）を防ぐ。
if [[ -d "$SCREENS_DIR" && -f "$COMMON_YAML" ]]; then
  enum_all="$(mktemp)"; enum_by="$(mktemp)"
  # トラップは先頭の _cleanup に集約済み（ここで上書きしない）
  # _common.yaml から「enum名<TAB>値」を抽出（description のブロック箇条書きは enum 終端後なので混入しない）
  awk '
    /^    [A-Za-z][A-Za-z0-9]*:[[:space:]]*$/ { name=$1; sub(/:$/,"",name); inenum=0; next }
    /^[[:space:]]*enum:[[:space:]]*$/ { inenum=1; next }
    {
      if (inenum) {
        if (match($0, /^[[:space:]]*-[[:space:]]+[A-Z][A-Z0-9_]+/)) {
          v=$0; sub(/^[[:space:]]*-[[:space:]]+/,"",v); sub(/[^A-Z0-9_].*$/,"",v);
          print name "\t" v
        } else if ($0 !~ /^[[:space:]]*#/ && $0 !~ /^[[:space:]]*$/) { inenum=0 }
      }
    }
  ' "$COMMON_YAML" > "$enum_by"
  cut -f2 "$enum_by" | sort -u > "$enum_all"
  enum_names="$(cut -f1 "$enum_by" | sort -u)"

  while IFS= read -r scr; do
    [[ -z "$scr" ]] && continue
    lineno=0
    while IFS= read -r line; do
      lineno=$((lineno+1))
      # 「CODE=表示名」形式の凡例トークン（大文字始まり識別子の直後に =）を抽出。
      # status=NEGOTIATING のような小文字フィールド比較は対象外（= 直前が小文字のため不一致）。
      codes="$(printf '%s' "$line" | grep -oE '\b[A-Z][A-Z0-9_]{2,}=' | sed 's/=$//' | sort -u || true)"
      [[ -z "$codes" ]] && continue
      # 同一行に明示された既知 enum 型名（文脈）を収集
      ctx_enums=""
      for en in $enum_names; do
        if printf '%s' "$line" | grep -qw "$en"; then ctx_enums="$ctx_enums $en"; fi
      done
      while IFS= read -r code; do
        [[ -z "$code" ]] && continue
        # Tier A: _common.yaml のどの enum にも存在しない値
        if ! grep -qxF "$code" "$enum_all"; then
          echo "NG: $scr:$lineno コード値「$code」が _common.yaml のどの enum 値にも存在しません（shared-canon §4 4層統一違反）"
          ng=1
          continue
        fi
        # Tier B: 行が enum 型名を明示しているのに、その enum の値集合に無い（型取り違え）
        for en in $ctx_enums; do
          if ! awk -F'\t' -v n="$en" -v c="$code" '$1==n && $2==c{f=1} END{exit f?0:1}' "$enum_by"; then
            echo "NG: $scr:$lineno コード値「$code」は $en の enum 値ではありません（_common.yaml では別 enum の値）。shared-canon §4 違反"
            ng=1
          fi
        done
      done <<< "$codes"
    done < "$scr"
  done < <(find "$SCREENS_DIR" -name '*.md' 2>/dev/null)
fi

if [[ $ng -ne 0 ]]; then
  echo ""
  echo "界面契約の縦串突合に不整合があります（RC-02）。_common.yaml を正典に統一してください。"
  exit 1
fi

echo "OK: 界面契約の縦串突合に致命的な不整合はありません（RC-02）。"
exit 0
