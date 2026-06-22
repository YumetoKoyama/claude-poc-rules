---
name: review-design
description: docs/design/ 配下の設計書一式をレビューし、BLOCK/SUGGEST/NIT の重大度付き JSON を出力する。design-loop オーケストレータから呼ばれる。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Write
---

# 設計書レビュー

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **review** 段を担当します。

**`context: fork` 必須**: produce skill（`/design-from-requirements`）の意図に引きずられず、書かれた設計だけで独立判定するため。

## 役割

`docs/design/` 配下の設計書を網羅的に読み、要件定義との整合 + 設計品質を観点別にレビューし、機械可読 JSON を生成する。

## 入出力

- 入力: `docs/requirements/`（整合確認の参照元）、`docs/design/` 配下の Markdown / YAML
- 入力: `.skills-state/design/state.json`
- 出力: `.skills-state/design/round-<N>-review.json`
- 出力: `docs/design/レビュー結果.md`（人間用サマリ。PR 差分に残す正。round ごとに最上部へ追記）
- 出力（標準出力）: 生成した review JSON のパスを 1 行

## 手順

1. **state を Read**: iteration を取得し、出力ファイル名を確定。
2. **要件定義を Read**: `docs/requirements/概要.md` `業務ルール.md` `functional/*.md` `ユースケース図.md` `activities/*.md` `画面一覧.md` `非機能要件.md` `権限マトリクス.md` `メッセージ一覧.md` `コード値定義.md` `通知・文面定義.md`
3. **設計書を Read**: `docs/design/概要.md` `screens/画面遷移.md` `screens/*.md` `sequences/*.md` `api/_common.yaml` `api/*.yaml` `IF定義.md` `DB定義.md` `tables/*.md` `方式設計.md` `セキュリティ設計.md` `認可設計.md` `バッチ設計.md` `共通部品設計.md` `運用設計.md` `テスト戦略.md` `シナリオ戦略.md` `非機能テスト計画.md` `セキュリティテスト観点.md`
4. **観点別にレビュー**: 後述のチェックリスト
4.5. 切断チェック（必須）: 次のスクリプトでファイル切断・破損を機械的に検出し、得られた findings を自分の review JSON に取り込む。
   ```bash
   bash .claude/skills/_common/scripts/check-truncation.sh docs/requirements/ docs/design/
   ```
   - 出力は findings JSON 配列（BLOCK / SUGGEST / NIT の重大度付き、`severity` `path` `line` `category` `message` `suggested_fix` の各フィールドを持つ）。
   - 検出内容: Invalid UTF-8（マルチバイト文字途中切断 = BLOCK）、日本語末尾で句読点なし（SUGGEST）、Markdown テーブル行が `|` で閉じていない（SUGGEST）、末尾近傍で括弧未閉じ（SUGGEST）、末尾改行なし（NIT）。
   - スクリプトの findings は **自分の手動レビューで作成した findings 配列に merge してから JSON を Write する**（後述の Write ステップで両者を統合）。重複（同一 path × 同一 message）は片方だけ残す。

5. **JSON を Write**

6. **JSON 検証（必須）**: 書き出した JSON を次のコマンドで検証する:
   ```bash
   bash .claude/skills/_common/scripts/validate-review-json.sh <output-path>
   ```
   - パース失敗（exit 1）した場合は stderr のエラー位置と前後コンテキストを Read で確認し、未エスケープの `"` `\` 生改行を修正して再 Write → 再検証する。
   - 最大 3 回まで自己修正を試み、それでも通らない場合は標準出力に `ERROR: invalid JSON after 3 attempts` を出力して停止する（orchestrator が中断する）。
7. **レビュー結果サマリ（人間用）を Write（必須・標準出力の直前に実施）**: `docs/design/レビュー結果.md` に、人間がレビューできる Markdown サマリを出力する。`.skills-state` の JSON は gitignore 対象で消えるため、**PR 差分に残るこのファイルが人間向けの正となる**。
   - 既存の `docs/design/レビュー結果.md` があれば Read し、**今回の round セクションを最上部に追記**（過去 round は残す。最新が一番上）。
   - フォーマット:
     ```markdown
     # レビュー結果（design）

     > 最新 round が最上部。各 round は機械可読 JSON（`.skills-state/.../round-<N>-review.json`）を人間向けに整形したもの。

     ## Round <N> — <YYYY-MM-DD HH:MM> — overall: <PASS|FAIL>（BLOCK <件> / SUGGEST <件> / NIT <件>）

     | 重大度 | カテゴリ | 該当 | 指摘 | 推奨対応 | 対応状況 |
     |---|---|---|---|---|---|
     | BLOCK | <category> | <path:line> | <message> | <suggested_fix> | 未対応 |
     | SUGGEST | ... | ... | ... | ... | 未対応 |
     ```
   - findings は **BLOCK → SUGGEST → NIT** の順に並べる。JSON の findings と件数・内容を一致させる。
   - 「対応状況」列は初期値 `未対応`。後続の fix skill が反映したら `対応済み` / `見送り（理由）` に更新する想定（fix skill 側で更新）。
   - BLOCK が 0 件で overall=PASS の場合も、その round セクション（指摘なし）を必ず残し、採択者が「クリーンで PASS した」ことを確認できるようにする。
8. **標準出力に JSON パスを 1 行で出す**

## レビュー観点

### BLOCK

- `traceability`: 要件 SCR-XXX / UC-XXX / ACT-XXX / BR-XXX / AC-XXX のいずれかが設計書側で**参照されていない**、または存在しない ID を参照
- `completeness`: 画面ファイル不足（画面一覧.md にあるが個別 md がない）、API YAML 不足、テーブル md 不足、**シーケンスファイル不足**（要件で複数コンポーネント間の交互動作が想定される業務に対応する `sequences/*.md` が無い）。とくに **分岐を持つ業務アクティビティ（ACT-XXX）** に対応するシーケンスが 1 件も無い場合は BLOCK
- `openapi`: OpenAPI YAML が 3.1 規格に違反、`info.description` に関連要件/画面が未記載、`_common.yaml` の共通スキーマを `$ref` せず重複定義
- `db`: `DB定義.md` に全体 ER 図がない（Mermaid `erDiagram` が必要）、テーブル md に部分 ER 図がない、外部キー先のテーブルが未定義
- `screen-transition`: 画面遷移図のノードが SCR-XXX 形式でない、参照画面が存在しない
- `sequence`: `sequences/*.md` で SEQ-XXX 採番が無い／Mermaid `sequenceDiagram` が無い／対応する SCR-XXX・UC-XXX・API operationId のいずれかが 1 件も引用されていない
- `security`: 認証要否・CORS・JWT 取り扱いが API YAML に未記載
- `architecture`: Controller に業務ロジックを書く前提になっている、フロントに業務判定を寄せている等、CLAUDE.md の設計原則に反する記述
- `nonfunc-traceability`: 要件で **要求値として確定した非機能要件**（性能の応答時間・同時接続数、可用性の稼働時間/RTO/RPO、バックアップ頻度、対象ブラウザ/デバイス等）のうち、設計に落ちる性質のもの（DB インデックス方針・ページング・キャッシュ・バッチ設計・対応ブラウザ前提の実装制約など）が設計書のどこにも反映されていない
- `architecture-doc`: `方式設計.md` が **存在しない**、または論理／物理アーキテクチャ・コンポーネント構成・環境別デプロイ構成のいずれも図示されていない（開発環境=devcontainer の記述のみで本番方式が無い場合も BLOCK）
- `security-design`: `セキュリティ設計.md`（認証・認可の正典）が **存在しない**、または JWT ライフサイクル・CORS・パスワードハッシュ・`@PreAuthorize` 規約とテナントフィルタの実装方式が 1 箇所に集約されていない。要件 `権限マトリクス.md` の各行に対応する **認可設計**（API operationId × 必要ロール × テナント条件）が `セキュリティ設計.md` または `認可設計.md` のどちらにも無い場合も BLOCK
- `batch-design`: 要件 `外部インターフェース一覧.md` にバッチ（EXT）があり `IF定義.md` でバッチ IF が定義されているのに、`バッチ設計.md`（トランザクション単位・再実行・分割・監視連携・失敗時詳細）が無い／「バッチなし」の明示も無い
- `operation-design`: `運用設計.md` が **存在しない**、または `非機能要件.md` の運用・可用性要求値（監視・アラート・バックアップ/リストア手順・稼働時間帯）が設計に落ちていない
- `legend`: 設計書側で **新規に導入した ID または略号**（SEQ-XXX、API 操作 ID、ER 関連名コード、ステータスコード略号など）について、当該ドキュメント冒頭に凡例が存在しない、または凡例から漏れている。CLAUDE.md「略号には凡例を明記」ルール違反

### SUGGEST

- `naming`: 同一概念に複数の英語名が混在
- `redundancy`: 同じスキーマが複数 YAML で重複
- `validation`: バリデーション条件が要件と設計で微妙にズレ
- `testability`: test-strategy / scenario-strategy のシナリオ粒度が粗い
- `performance`: N+1 リスクが残るリレーション、欠落しているインデックス
- `common-component`: `共通部品設計.md` が無い、または共通例外ハンドラ・バリデーション共通化・共通レスポンス整形・ロギング方式が未定義（ErrorResponse スキーマの実装方式が API YAML 側にしか無い）
- `nonfunc-test`: `非機能テスト計画.md` が無い／非機能要求値に対する検証方法の対応表が無い。または `セキュリティテスト観点.md`（認可バイパス・テナント越境・JWT 改ざん・機微情報漏えい等）が無い
- `message-trace`: 設計の ErrorResponse コード・通知/メール文面が、要件 `メッセージ一覧.md`（MSG-XXX）・`コード値定義.md`・`通知・文面定義.md` と相互参照されていない（コード値 enum と `_common.yaml` の対応含む）
- `sequence`: SEQ-XXX 採番済みだが例外フロー・代替フローの記述が不足、または対応する AC-XXX 引用が一部欠落
- `legend`: 要件定義で定義済みの ID（`SCR-XXX` / `UC-XXX` / `ACT-XXX` / `AC-XXX` / `BR-XXX` 等）を引用しているが、出典への参照（リンク／パス）が無い

### NIT

- `style`: YAML/MD のインデント揺れ、末尾空白

## 出力 JSON スキーマ

review-requirements と同じ。`phase: "design"`、`category` には上記カテゴリを使う。

## 注意事項

- このスキルでファイルを書き換えない。
- 要件側に問題がある場合（要件定義が完全でない等）は BLOCK ではなく SUGGEST にし、message に「要件定義 phase へのフィードバックが必要」と明記。
- `message` / `title` / `recommendation` などの自然言語フィールドで語句を強調する場合は、ASCII の `"..."` ではなく **鉤括弧 `「...」`** を使う。JSON 文字列内の `"` エスケープ漏れ事故を減らすため（過去発生事例あり）。
