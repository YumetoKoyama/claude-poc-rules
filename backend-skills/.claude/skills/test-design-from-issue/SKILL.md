---
name: test-design-from-issue
description: 採択済み Issue と設計書から、製造フェーズのテスト設計成果物（単体テストマトリクス・トレーサビリティマトリクス/RTM）を docs/test/ に生成・更新するときに使う。テスト「設計（ケース化）」専用で、テスト「実施（実行）」は対象外。結合テストは別工程（/integration-test-from-design）。製造フェーズの必須サブステップ。
context: fork
argument-hint: <ISSUE-NUMBER> [draft|finalize]
---

# Issue・設計書からテスト設計（マトリクス）を作成する

> **責務の切り分け**: 本スキルは **テスト「設計（ケース化）」** だけを担う。テストの「実施（実行）」＝ `mvn test` / `npm test` の実行とカバレッジ取得は別責務であり、製造（`/implement-from-issue` 手順5）や担当者が行う。本スキルが強制するのは **単体テスト設計（マトリクス）と RTM の出力** のみ。**結合テストは設計・実施とも別工程**（`/integration-test-from-design`）であり、本スキル・製造フェーズでは扱わない（E2E と同様の切り分け）。

> **パス解決（マルチリポジトリ対応）**:
> - **読み取り入力（docs リポジトリ＝claude-poc-docs）**: `docs/requirements/`・`docs/design/` は docs リポジトリ ルート相対。docs をカレントで実行ならそのまま、親アンブレラからなら `claude-poc-docs/` を前置、CI で workflow が追加チェックアウトした docs があればそのパス、無ければ Issue 本文の埋め込み設計を使う。
> - **書き込み出力（own リポジトリ＝実装リポジトリ）**: マトリクスは **own リポジトリのワーキングツリー直下 `docs/test/`** に書き、feature ブランチへ commit/push して **PR に含める**。docs リポジトリ（claude-poc-docs）には書かない（CI では読み取り専用で push されず PR に残らないため）。

> **呼び出し元**: `/implement-from-issue` から **2 タッチ**で呼ばれる。テスト設計の入力は設計書（AC-XXX・実装内容項目）であり実装コードに依存しないため、実装と並行して前倒しできる。設計フェーズ採択後に単独起動することもできる。`/implement-loop` の produce 段の一部であり、Agent Teams は使わない。

## モード（2 タッチ）

第 2 引数で `draft` / `finalize` を切り替える（省略時 `finalize`）。

| モード | 呼び出し位置 | 実コードとの突合 | ハードゲート | 用途 |
| --- | --- | --- | --- | --- |
| `draft` | 実装と**並行**（`/implement-from-issue` 手順3.5） | しない（計画ケースのみ） | スキップ | 設計書から AC・観点・TC を先出しし、実装の指針にする。未整合セルは「要整合（実装後）」と明記 |
| `finalize` | 実装・テスト実施の**後**（手順5.5） | する（テストメソッドと TC を突合・件数一致） | **必須**（`check-test-matrix.sh`） | ドラフトを実コードに整合させて確定し、PR に含める |

`draft` は設計由来の独立タスクなので実装（手順4）と論理的に並行（Pattern 2 の独立性）。`finalize` はコード存在が前提のため実装後に合流させる。

対象 Issue: $ARGUMENTS

## 手順

### 1. 入力の収集と AC（テスト観点）の確定

1. `gh issue view <ISSUE> --json number,title,body,labels` で Issue を取得し、受け入れ条件 AC-XXX・関連 SCR-XXX・BR-XXX・API operationId を抽出する。
2. 設計書（`docs/design/` 配下の関連ファイル）を読み、テスト対象クラス・メソッド・API・分岐・例外を特定する。
3. **AC-XXX が無い共通基盤 Issue の扱い（必須ルール）**: 受け入れ条件が明示されていない基盤系 Issue（共通部品・基盤設定等）では、設計書の **「実装内容」項目** をテスト観点として採用し、各項目を `IMPL-XX`（実装内容項目の一時識別子。当該 Issue 内ローカル）として列挙してから TC-XXX を採番する。RTM の「AC」列にはこの実装内容項目ID（または「—（基盤）」と項目名）を入れ、テスト観点を空欄にしない。

### 2. 単体テストマトリクスの作成（TC-XXX）

`docs/test/単体テストマトリクス.md` を [unit-test-from-design の unit-test-matrix-template.md](../unit-test-from-design/unit-test-matrix-template.md) の様式で作成または更新する。

- 各テストケースに **TC-XXX（3 桁ゼロ埋め）** を採番し、対応する AC-XXX（無ければ実装内容項目ID）・BR-XXX を紐付ける。
- **採番の一意化（RC4 / T-03）**: 複数 Issue 間で TC 番号が衝突しないよう、**既存マトリクスの最大 TC 番号の続番**から開始する。`docs/test/単体テストマトリクス.md` が既存の場合、冒頭で次のコマンドで最大番号を取得し、続番で採番する（新規作成時は TC-001 から）。
  ```bash
  grep -Eo 'TC-[0-9]{3}' docs/test/単体テストマトリクス.md 2>/dev/null | sort -t- -k2 -n | tail -1
  ```
  ※ check-test-matrix.sh は TC-XXX の重複を検出してハードゲートで弾くため、衝突したまま finalize しない。
- 「区分」は **正常系 / 異常系 / 境界値 / 権限境界** のいずれかを必ず指定し、各観点で合理的に該当する区分を網羅する。
- **finalize モード**: 実装済みの単体テスト（メソッド名）と TC-XXX を突合し、件数とシナリオを一致させる。**draft モード**: コードは未存在でよく、計画ケースを起こすに留める（突合は finalize で行う）。

### 3. 結合テストは対象外（別工程）

結合テスト（IT-XXX）は設計・実施とも **結合テスト工程**（`/integration-test-from-design`）が担う。結合テストはフィーチャ単位で複数 Issue のコンポーネントをまたぐため、1 Issue の製造では設計・実施いずれも完結しない。本スキル（製造）では `結合テストマトリクス.md` を作成しない。

### 4. トレーサビリティマトリクス（RTM）の更新

`docs/test/トレーサビリティマトリクス.md` に当該 Issue の行を追記・更新する（様式は [test-design-matrix-template.md](test-design-matrix-template.md)）。

- 列: `UC / AC（または実装内容項目）/ BR / SCR / API operationId / Issue# / TC-XXX / IT-XXX / E2E-XXX`。
- 当該 Issue 番号（`#<ISSUE>`）を必ず含め、採番した **TC-XXX** を反映する。**IT-XXX 列は結合テスト工程が記入**するため製造時点では `—`（未）でよい。E2E も別工程のため `—`。

### 5. ハードゲート（finalize モードで必須・出力検証）

`draft` モードではゲートをスキップし、未整合セル（TC↔コード・IT 行・RTM の確定値）を「要整合（実装後）」と明記して終了する。`finalize` モードではマトリクス出力を機械的に検証し、**exit 0 になるまで本スキルを完了しない**。

```bash
bash .claude/skills/_common/scripts/check-test-matrix.sh docs/test <ISSUE> unit
```

- NG（exit 1）の場合は、表示された不足項目（単体マトリクスの TC 行・RTM の Issue 行）を補ってから再実行する。
- `docs/test` のパスは own リポジトリのワーキングツリー直下。CI（子リポジトリ単体チェックアウト）でも `docs/test` でよい。

### 6. コミットと push（own リポジトリ）

ゲート通過後、`docs/test/` 配下のマトリクスのみを現在の feature ブランチへ commit/push して PR に含める（テストコード本体・アプリコードはここでは触れない）。

```bash
git add docs/test/単体テストマトリクス.md docs/test/トレーサビリティマトリクス.md
git commit -m "docs(test): テスト設計マトリクス (#<ISSUE>)" || true
git push || true
```

## 完了条件

- 単体テストマトリクス（TC-XXX）が AC-XXX（または実装内容項目）に対応づけて作成されている
- RTM に当該 Issue の行（TC-XXX）が反映されている（IT-XXX 列は結合テスト工程が後で記入）
- `check-test-matrix.sh ... unit` が exit 0 を返す
- マトリクスが feature ブランチへ commit/push され PR に含まれている

## 凡例

| 略号 | 正式名称 | 補足 |
| --- | --- | --- |
| TC-XXX | 単体テストケース ID | 3 桁ゼロ埋め |
| IT-XXX | 結合テストケース ID | 3 桁ゼロ埋め |
| E2E-XXX | E2E テストケース ID | 3 桁ゼロ埋め（現環境では別工程） |
| RTM | トレーサビリティマトリクス | 要件→設計→Issue→テストの追跡表 |
| AC-XXX | 受け入れ条件 | 要件定義 `functional/*.md` で定義 |
| IMPL-XX | 実装内容項目 | AC が無い基盤 Issue で設計書「実装内容」を観点化した一時 ID（Issue 内ローカル） |

## 注意事項

- テスト実施（テスト実行・カバレッジ取得）は本スキルの対象外。マトリクスとコードの件数突合のみ行う。
- マトリクスは own リポジトリの `docs/test/` に書く。docs リポジトリ（claude-poc-docs）には書かない。
- 強調表記は ASCII の `"..."` ではなく鉤括弧 `「...」` を使う。
