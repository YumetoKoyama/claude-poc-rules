---
name: feature-completion-check
description: フィーチャ名を入力に、当該フィーチャの完了状態を横串で判定する。全 Issue クローズ / RTM の TC-XXX・IT-XXX 充足 / 結合テスト実施 / review-implementation-overall 要否 / 全品質ゲート（カバレッジ・静的解析・セキュリティ）グリーン を確認し、完了/未完了を判定する。review-implementation-overall の前提ゲートとして使う。
context: fork
allowed-tools: Bash, Read, Glob, Grep
argument-hint: <フィーチャ名（業務用語の日本語名）>
---

# フィーチャ完了判定（横串チェック）

> **位置づけ**: 製造（Issue 単位の `implement-loop`）と結合テスト工程（`integration-test-from-design`）の後段に置く判定スキル。Issue 単位の PASS は揃っても、フィーチャ全体（複数 Issue の集合）が完了したかは別問題であり、その横串判定がこれまで欠落していた。本スキルは **判定のみ**（修正しない）行い、`review-implementation-overall` の前提ゲートとして機能する（フィーチャ完了が PASS でないと横断レビューに進まない）。
>
> **親アンブレラから実行する**: 複数の実装リポジトリ（backend / frontend / batch）と docs リポジトリをまたぐため。

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらのパスに `claude-poc-docs/` を前置する。RTM 等は実装リポ側に置かれる構成のため、`docs/test/` は対象実装リポ配下も併せて確認する。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。

対象フィーチャ: $ARGUMENTS

## 入出力

- 入力: フィーチャ名（業務用語の日本語名。例: `案件成約`）
- 入力: docs リポの設計・要件（フィーチャに属する SCR-XXX / operationId / テーブル / AC-XXX の集合を特定するため）
- 入力: `docs/test/トレーサビリティマトリクス.md`（RTM）・`docs/test/単体テストマトリクス.md`（TC）・`docs/test/結合テストマトリクス.md`（IT）
- 入力: GitHub Issue 状態（`gh`）・各実装リポの品質ゲート結果（カバレッジ・静的解析・セキュリティ）
- 出力: 完了/未完了の判定サマリ（各チェック項目の PASS/FAIL と未充足の根拠一覧）

## 判定項目（すべて PASS で完了）

| # | チェック項目 | PASS 条件 | データ源 |
|---|---|---|---|
| C1 | 全 Issue クローズ | フィーチャに属する全 Issue が CLOSED かつ PR マージ済み | `gh issue list` / `gh issue view` |
| C2 | TC-XXX 充足 | フィーチャ範囲の AC-XXX に対し RTM の TC-XXX 列が埋まっている | RTM / 単体テストマトリクス |
| C3 | IT-XXX 充足 | フィーチャの結合点に対し RTM の IT-XXX 列が埋まっている（結合点が無い場合は対象外＋理由が明記） | RTM / 結合テストマトリクス |
| C4 | 結合テスト実施 | `integration-test-from-design` が実施され、`check-test-matrix.sh ... integration` が exit 0 | 結合テスト工程の成果物 |
| C5 | カバレッジゲート | 各実装リポのカバレッジが確定表閾値を満たす | JaCoCo / Istanbul レポート、確定表 |
| C6 | 静的解析ゲート | 各実装リポの静的解析がグリーン（suppress の不正増殖が無い） | 静的解析レポート |
| C7 | セキュリティゲート | review-implementation の security 観点に BLOCK が残っていない | レビュー結果 |
| C8 | overall レビュー要否 | review-implementation-overall が実施済み、または明示的に不要判定されている | overall レビュー結果 |

## 手順

### 1. フィーチャ構成の特定

1. フィーチャ名から、属する SCR-XXX・operationId・テーブル・AC-XXX の集合を、設計書（`docs/design/`）と RTM から特定する。範囲が曖昧なら人間に確認する（推測でフィーチャ境界を広げない）。
2. その範囲に対応する GitHub Issue 群を `gh issue list`（ラベル・タイトルの `[SCR-XXX]`・`[API]` 等）で洗い出す。

### 2. 各判定項目の確認

1. **C1 Issue クローズ**: 洗い出した各 Issue の state と関連 PR のマージ状態を `gh` で確認する。OPEN・未マージがあれば C1 = FAIL とし、該当 Issue を列挙する。
2. **C2/C3 TC・IT 充足**: RTM のフィーチャ範囲行で TC-XXX / IT-XXX 列を確認する。空セル（または対象外理由が所定の見出し/セルに無い）があれば FAIL とし、未充足の AC/結合点を列挙する。
3. **C4 結合テスト実施**: 対象実装リポで `bash .claude/skills/_common/scripts/check-test-matrix.sh docs/test <ISSUE> integration` を実行できる場合は実行し、exit code を判定根拠にする。結合点が無いフィーチャは対象外＋理由の明記を確認する。
4. **C5 カバレッジ / C6 静的解析**: 各実装リポの最新レポートを確認し、確定表閾値・グリーン状態と突合する。レポート不在は「未実施」として FAIL（時刻でなく内容・存在で判定）。
5. **C7 セキュリティ**: `docs/test/レビュー結果/` 等の review-implementation 結果で security 観点の BLOCK 残存を確認する。
6. **C8 overall レビュー要否**: `docs/test/レビュー結果/overall-*.md` の有無、または不要判定の記録を確認する。

### 3. 判定とサマリ出力

1. C1〜C8 をすべて評価し、1 つでも FAIL があれば **未完了（INCOMPLETE）**、すべて PASS なら **完了（COMPLETE）** と判定する。
2. 次の様式でサマリを出力する。

```markdown
# フィーチャ完了判定: <フィーチャ名> — <COMPLETE / INCOMPLETE>

## 構成
- 範囲: SCR-XXX 群 / operationId 群 / テーブル群 / AC-XXX 群
- 対象 Issue: #... 

## 判定結果
| # | 項目 | 結果 | 根拠 / 未充足の内訳 |
|---|---|---|---|
| C1 | 全 Issue クローズ | PASS/FAIL | ... |
| ... | ... | ... | ... |

## 次アクション
- COMPLETE の場合: /review-implementation-overall の前提を満たす。横断レビューへ進める。
- INCOMPLETE の場合: 未充足項目の解消（製造/結合テスト/ゲート修正）を促す。横断レビューには進めない。
```

3. **COMPLETE のときのみ** 「review-implementation-overall の前提ゲートを満たす」と明示する。INCOMPLETE のときは未充足項目を解消するまで横断レビューに進まないことを明示する。

## 完了条件

- フィーチャ構成（SCR/operationId/テーブル/AC/Issue）が特定されている
- C1〜C8 がすべて評価され、各項目に PASS/FAIL と根拠が付いている
- COMPLETE / INCOMPLETE が判定され、次アクション（横断レビューへ進む/進まない）が明示されている

## 凡例

| 略号 | 正式名称 | 補足 |
| --- | --- | --- |
| RTM | トレーサビリティマトリクス | `docs/test/トレーサビリティマトリクス.md`。横串カバレッジの正典 |
| TC-XXX | 単体テストケース ID | 製造の成果物 |
| IT-XXX | 結合テストケース ID | 結合テスト工程の成果物 |
| AC-XXX | 受け入れ条件 ID | 3 桁ゼロ埋め |
| COMPLETE / INCOMPLETE | 完了 / 未完了 | 全判定項目 PASS で COMPLETE |

## 注意事項

- 本スキルは判定のみ。修正・起票はしない（未充足は対応工程へ案内する）。
- ゲート判定は時刻でなく内容・存在で行う（レポート不在は FAIL）。
- フィーチャ境界は設計書・RTM から特定し、推測で広げない。
- review-implementation-overall は本スキルが COMPLETE のときの前提ゲートとして位置づける。
- 強調表記は鉤括弧 `「...」` を使う。
