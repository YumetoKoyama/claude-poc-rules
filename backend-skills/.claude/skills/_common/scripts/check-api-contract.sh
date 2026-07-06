#!/usr/bin/env bash
# _common/scripts/check-api-contract.sh
#
# 用途（RC-14 S6）:
#   バックエンドの実レスポンスが OpenAPI スキーマに適合するかをテスト実行で検証する
#   ラッパー。@WebMvcTest + MockMvc → Swagger Request/Response Validator 等の起動を想定。
#   検証実行環境（テストタスク・Validator 依存）が揃っていれば実行し、無ければ
#   セットアップ手順を出力して非ブロッキングに倒す（環境未整備での誤 BLOCK を防ぐ）。
#
# Usage:
#   check-api-contract.sh [<backend-root>]
#     <backend-root> : 省略時、./ または ./claude-poc-backend を自動探索
#
# Exit:
#   0: 契約テスト成功、または環境未整備で手順提示（非ブロッキング）
#   1: 契約テスト実行して失敗（実レスポンスが OpenAPI に不適合）
#   2: 引数エラー

set -euo pipefail

BE_ROOT="${1:-}"
if [[ -z "$BE_ROOT" ]]; then
  for c in "." "./claude-poc-backend"; do
    if [[ -f "$c/pom.xml" || -f "$c/build.gradle" || -f "$c/build.gradle.kts" ]]; then
      BE_ROOT="$c"; break
    fi
  done
fi
[[ -z "$BE_ROOT" ]] && BE_ROOT="."

if [[ ! -d "$BE_ROOT" ]]; then
  echo "ERROR: backend ルートが見つかりません: $BE_ROOT" >&2
  exit 2
fi

print_setup() {
  cat <<'GUIDE'
INFO: API 契約テスト（FE↔BE）の実行環境が未整備のため、手順を提示します（非ブロッキング）。

  目的: BE の実レスポンスが docs/design/api/*.yaml（OpenAPI 3.1）に適合するかをテストで保証する。

  推奨セットアップ（backend / Spring Boot 想定）:
    1. 依存追加（例）: com.atlassian.oai:swagger-request-validator-mockmvc
    2. @WebMvcTest（または @SpringBootTest）+ MockMvc で各エンドポイントを叩き、
       OpenApiValidationFilter / OpenApiInteractionValidator で _common.yaml を含む
       OpenAPI 定義に対しレスポンスを検証するテストクラスを追加する。
    3. テストを `*ApiContractTest` 命名で配置し、本スクリプトが検出できるようにする。

  推奨セットアップ（frontend 側の型整合・参考）:
    - openapi-typescript で OpenAPI から型を自動生成し、手書き型と diff（CI で乖離検出）。

  環境が整ったら本スクリプトは契約テストタスクを起動して合否を返します。
GUIDE
}

# 契約テストの存在を検出（命名規約 *ApiContractTest / *ContractTest）
contract_tests="$(grep -rlE 'class\s+\w*(Api)?ContractTest' "$BE_ROOT/src" 2>/dev/null || true)"

if [[ -z "$contract_tests" ]]; then
  echo "INFO: 契約テスト（*ApiContractTest）が見つかりません（$BE_ROOT/src）。"
  print_setup
  exit 0
fi

echo "INFO: 契約テストを検出: $(echo "$contract_tests" | tr '\n' ' ')"

# ビルドツールに応じてテスト実行
if [[ -f "$BE_ROOT/pom.xml" ]]; then
  if command -v mvn >/dev/null 2>&1; then
    echo "INFO: Maven で契約テストを実行します"
    if ( cd "$BE_ROOT" && mvn -q -Dtest='*ContractTest' test ); then
      echo "OK: API 契約テスト成功（S6）。"; exit 0
    else
      echo "NG: API 契約テスト失敗。実レスポンスが OpenAPI スキーマに不適合です（S6）。"; exit 1
    fi
  fi
elif [[ -f "$BE_ROOT/build.gradle" || -f "$BE_ROOT/build.gradle.kts" ]]; then
  GRADLE="./gradlew"; [[ -x "$BE_ROOT/gradlew" ]] || GRADLE="gradle"
  if command -v "${GRADLE##*/}" >/dev/null 2>&1 || [[ -x "$BE_ROOT/gradlew" ]]; then
    echo "INFO: Gradle で契約テストを実行します"
    if ( cd "$BE_ROOT" && "$GRADLE" test --tests '*ContractTest' ); then
      echo "OK: API 契約テスト成功（S6）。"; exit 0
    else
      echo "NG: API 契約テスト失敗（S6）。"; exit 1
    fi
  fi
fi

echo "INFO: ビルドツール（mvn/gradle）が利用できないため契約テストを実行できませんでした（非ブロッキング）。"
print_setup
exit 0
