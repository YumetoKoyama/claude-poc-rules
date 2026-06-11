---
name: review-requirements
description: docs/requirements/ 配下の要件定義書一式をレビューし、BLOCK/SUGGEST/NIT の重大度付き JSON を出力する。requirements-loop オーケストレータから呼ばれる。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Write
---

# 要件定義レビュー

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **review** 段を担当します。

**`context: fork` 必須**: produce skill（`/requirements-from-input`）の思考プロセスを引き継がず、書かれた成果物だけで独立判定するため。

## 役割

`docs/requirements/` 配下の要件定義書を網羅的に読み、観点別にレビューして、機械可読 JSON を生成する。

## 入出力

- 入力: `docs/requirements/` 配下の Markdown ファイル一式
- 入力: `.skills-state/requirements/state.json`（現在の iteration を取得）
- 出力: `.skills-state/requirements/round-<N>-review.json`
- 出力: `docs/requirements/レビュー結果.md`（人間用サマリ。PR 差分に残す正。round ごとに最上部へ追記）
- 出力（標準出力）: 生成した review JSON の絶対パスを 1 行だけ出力（orchestrator が読み取る）

## 手順

1. **state を確認**: `.skills-state/requirements/state.json` を Read し、`iteration` を取得。出力ファイル名を `round-<iteration>-review.json` とする。
2. **要件定義一式を Read**: 次のファイルを順に Read する（存在しないものはスキップ）:
   - `docs/requirements/概要.md`
   - `docs/requirements/業務ルール.md`
   - `docs/requirements/functional/*.md`
   - `docs/requirements/ユースケース図.md`
   - `docs/requirements/activities/*.md`
   - `docs/requirements/画面一覧.md`
   - `docs/requirements/データモデル.md`
   - `docs/requirements/外部インターフェース一覧.md`
   - `docs/requirements/移行要件.md`
   - `docs/requirements/権限マトリクス.md`
   - `docs/requirements/メッセージ一覧.md`
   - `docs/requirements/コード値定義.md`
   - `docs/requirements/通知・文面定義.md`
   - `docs/requirements/非機能要件.md`
   - `docs/requirements/ブランドガイドライン.md`
   - `docs/requirements/用語集.md`
   - `docs/requirements/オープン課題.md`
3. **観点別にレビュー**: 後述のチェックリストに沿って findings を作る。
3.5. 切断チェック（必須）: 次のスクリプトでファイル切断・破損を機械的に検出し、得られた findings を自分の review JSON に取り込む。
   ```bash
   bash .claude/skills/_common/scripts/check-truncation.sh docs/requirements/
   ```
   - 出力は findings JSON 配列（BLOCK / SUGGEST / NIT の重大度付き、`severity` `path` `line` `category` `message` `suggested_fix` の各フィールドを持つ）。
   - 検出内容: Invalid UTF-8（マルチバイト文字途中切断 = BLOCK）、日本語末尾で句読点なし（SUGGEST）、Markdown テーブル行が `|` で閉じていない（SUGGEST）、末尾近傍で括弧未閉じ（SUGGEST）、末尾改行なし（NIT）。
   - スクリプトの findings は **自分の手動レビューで作成した findings 配列に merge してから JSON を Write する**（後述の Write ステップで両者を統合）。重複（同一 path × 同一 message）は片方だけ残す。

4. **JSON を Write**: 後述のスキーマで `.skills-state/requirements/round-<iteration>-review.json` に書き出す。

5. **JSON 検証（必須）**: 書き出した JSON を次のコマンドで検証する:
   ```bash
   bash .claude/skills/_common/scripts/validate-review-json.sh <output-path>
   ```
   - パース失敗（exit 1）した場合は stderr のエラー位置と前後コンテキストを Read で確認し、未エスケープの `"` `\` 生改行を修正して再 Write → 再検証する。
   - 最大 3 回まで自己修正を試み、それでも通らない場合は標準出力に `ERROR: invalid JSON after 3 attempts` を出力して停止する（orchestrator が中断する）。
6. **レビュー結果サマリ（人間用）を Write（必須・標準出力の直前に実施）**: `docs/requirements/レビュー結果.md` に、人間がレビューできる Markdown サマリを出力する。`.skills-state` の JSON は gitignore 対象で消えるため、**PR 差分に残るこのファイルが人間向けの正となる**。
   - 既存の `docs/requirements/レビュー結果.md` があれば Read し、**今回の round セクションを最上部に追記**（過去 round は残す。最新が一番上）。
   - フォーマット:
     ```markdown
     # レビュー結果（requirements）

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
7. **標準出力**: 最終行に **review JSON の相対パスのみ** を 1 行で出力する（orchestrator がパース）。

## レビュー観点（重大度判定の基準）

### BLOCK（PASS させない致命）

- `completeness`: 必須セクションの欠落（summary が存在しない、AC 列挙がない、open-questions に空セクションがある）
- `consistency`: 業務ルール（BR-XXX）や受け入れ条件（AC-XXX）の参照先が存在しない、または別ファイルと矛盾
- `traceability`: 機能と画面の対応が `画面一覧.md` で取れない、画面 ID が SCR-XXX 形式でない、`概要.md` の主要ユースケース表に UC-XXX が無い／`ユースケース図.md` と不整合
- `security`: 認証要否・権限境界・PII 取り扱いが**完全に未記載**
- `ambiguity`: 「適切に」「必要に応じて」「いい感じに」など実装者が判断不能な指示
- `usecase`: `ユースケース図.md` 自体が **存在しない**、Mermaid `flowchart`（または同等の図）が含まれていない、UC-XXX 採番が無い、または `functional/[機能名].md` の関連ユースケース欄から参照される UC-XXX が `ユースケース図.md` 側で未定義
- `activity`: 業務プロセスに分岐があるにもかかわらず `activities/` 配下が空、ACT-XXX 採番が無い、または各ステップで関連 UC/BR/AC が **1 件も** 引用されていない
- `data_model`: `データモデル.md` が **存在しない**、主要エンティティ表が空、概念 ER 図（Mermaid `erDiagram` または同等の図）が含まれていない、ENT-XXX 採番が無い、またはステータスを持つエンティティ（業務ルール内で状態名が登場するもの）について状態遷移（ST-XXX）が記述されていない
- `external_interface`: `外部インターフェース一覧.md` が **存在しない**、または「外部 IF なし」の明示も無いまま空のテーブルが残っている。`業務ルール.md` / `functional/*.md` でメール送信・バッチ・外部システム連携が言及されているのに、対応する EXT-XXX が `外部インターフェース一覧.md` 側で定義されていない場合も BLOCK
- `migration`: `移行要件.md` が **存在しない**、または「移行なし」の明示も無いまま空のテーブルが残っている
- `authorization`: `権限マトリクス.md` が **存在しない**、または「ロール 1 種・認可制御なし」の明示も無いまま空のテーブルが残っている。`functional/*.md` や `業務ルール.md` で複数ロール（依頼側/受注側・管理者/一般等）や権限境界が言及されているのに、ロール × 操作可否の一覧が `権限マトリクス.md` 側に無い場合も BLOCK
- `message_catalog`: `メッセージ一覧.md` が **存在しない**、または画面仕様・通知でユーザー向け文言が言及されているのに MSG-XXX 採番の正典が無い。エラー/確認/バリデーション文言が各画面に断定で散在し未集約の場合も BLOCK（未確定文言は `Q-MSG*` へ切り出すこと）
- `code_value`: `コード値定義.md` が **存在しない**、または「区分値なし」の明示も無いまま、業務ルール・状態遷移（ST-XXX）でステータス/種別が登場するのに区分値の概念正典が無い
- `operational`: 非機能要件の「運用・障害対応」セクションが完全に空、または **バックアップ・障害通知・稼働時間帯のすべて** が TBD/オープン課題のままで本文に確定値が無い（うち最低限：稼働時間帯・バックアップ最低頻度・障害検知方法は本文確定が必要）
- `security_baseline`: 非機能要件のセキュリティで **パスワードポリシー / セッション有効時間 / 通信暗号化** のいずれかが本文未確定（TBD / オープン課題のみ）。これらは設計着手前に確定が必要
- `legend`: ドキュメント内で **未定義の ID または略号** を使用（例: `Q-A1` などのプレフィックスが本文に登場するのに、当該ドキュメント冒頭に凡例表が無い／凡例から漏れている）。CLAUDE.md「略号には凡例を明記」ルール違反。`SCR-XXX` `AC-XXX` `BR-XXX` のように他ドキュメントで定義済みの ID を **引用のみ** で使用している場合は SUGGEST 扱い（出典への参照リンクが望ましいため）
- `open_question_closure`: `オープン課題.md` に **クローズ運用ルール章（設計着手前クローズ必須課題の区分とクローズ手順）** が存在しない。または `Q-NF*`（パスワードポリシー・対象ブラウザ・バックアップ等）が open のまま本文側で TBD になっている（クローズと本文反映の両方が必要）
- `exception`: 正常系は記述されているが、以下の例外系が **完全に未記載**：同時操作競合の制御方針・取消可否（運送開始 / 完了報告等）・差戻し要否・論理削除中（削除〜物理削除間）データの画面表示方針。詳細パターンは [requirements-guardrails/references/negative-patterns.md](../requirements-guardrails/references/negative-patterns.md) カテゴリ B を参照
- `status-drift`: 用語集で「第 1 版では使用しない」と定義されたステータス、または用語集に未登録のステータスが業務ルール・画面仕様・フロー図などの他資料で参照されている。あるいは同一概念に複数の表記（成約／契約成立／確定 等）が資料間で混在している
- `impl-leak`: フレームワーク名・ライブラリ名（例: Spring Security、React、Redux）・DB カラム名・API パスが要件として記述されている（設計工程の責務であり要件定義書に含めてはならない）。詳細は [requirements-guardrails/SKILL.md](../requirements-guardrails/SKILL.md) カテゴリ D を参照

### SUGGEST（修正対象だが PASS は阻害しない）

- `naming`: 用語の表記揺れ（「ユーザ」⇔「ユーザー」、英日混在）
- `term_variation`: 用語集に「同義」と明記されている用語（例: 「テナント」⇔「企業アカウント」、「荷主」⇔「配送依頼企業」）が本文中で混在しており、意図的な使い分けの根拠も書かれていない。用語集準拠で片方に寄せるべき
- `redundancy`: 同じ要件が複数ファイルで重複定義
- `testability`: AC が「動作する」のように検証可能性が低い表現
- `ac_granularity`: 同じプロジェクト内で機能間の AC 粒度が大きく異なる（例: ある機能は異常系 AC が 5 件あるのに別機能は 0〜1 件、または性能観点の AC が一切無い）。「異常系・境界値・権限境界」の各区分のうち、合理的に該当しうるのに 0 件の機能を指摘
- `responsibility_boundary`: 業務ルール（BR-XXX）に該当判定ロジックが定義されているが、**そのルールを実装する責任機能（F-XXX）** が機能要件側で明示されていない（例: 「new 表示条件」が業務ルールにあるが、どの機能で判定するか不明）
- `risk`: open-questions に未解決リスクがあり、放置すると後段で問題化する可能性
- `legend`: 他ドキュメントで定義済みの ID（`SCR-XXX` 等）を引用しているが、出典への参照（リンク／パス）が無い。または凡例表は存在するが新規導入した略号が漏れている
- `usecase`: UC-XXX は採番されているが、`概要.md` 側の主要ユースケース表または `functional/[機能名].md` 側の関連ユースケース欄から **一部の UC-XXX が引用されていない**（俯瞰と詳細の対応が抜けている）
- `activity`: ACT-XXX 採番済みのフローについて、ステップ詳細表が空、または例外フロー・代替フローの記述欠落。または **アカウント登録・論理削除→物理削除** のような分岐を含む業務プロセスが要件素材から読み取れるのに ACT 化されていない
- `data_model`: 主要エンティティは列挙されているが、**ステータスを持つエンティティ** の状態遷移（ST-XXX）が片方向しか書かれていない／例外フロー（差し戻し・キャンセル）が記述されていない。または保持期間・スナップショット方針が一部エンティティで未記載
- `external_interface`: EXT-XXX は列挙されているが、各 IF の **失敗時挙動・冪等性要件・リトライ方針** が未記載
- `migration`: MIG-XXX は列挙されているが、**完了判定基準・切り戻し方針** が未記載
- `authorization`: 権限マトリクスは存在するが、テナント越境（自社外の参照・操作）の拒否条件が未記載、または一部リソース/操作が表から漏れている
- `message_catalog`: メッセージ一覧はあるが、区分（情報/警告/エラー/確認）や表示画面（SCR-XXX）の対応が一部欠落。通知・送信メールの文面（件名/本文/差込変数）が `通知・文面定義.md`（または統合先）に未記載
- `operational`: RTO/RPO・目標稼働率・ログ保管期間・問い合わせ受付方法のいずれかが未記載（BLOCK までではないが、設計と並行で確定が望ましい）
- `nonfunc-value`: 非機能要件の記述が「方針」止まりで **要求値**（数値・期間・条件）が未記載。例: 「高可用性を目指す」だけで稼働率目標数値なし、「主要ブラウザに対応」だけで具体的なブラウザ名・最低バージョンなし。要求値テンプレは [requirements-guardrails/references/nonfunctional-template.md](../requirements-guardrails/references/nonfunctional-template.md) を参照
- `transition-drift`: 同一操作の完了後遷移先が `画面一覧.md` と `functional/[機能名].md` で異なる（例: 登録完了後の遷移先が「ログイン画面」と「ダッシュボード」で混在）。実装が根本的に変わるため要修正
- `ui-mixed`: ブランドガイドライン・UI ライブラリ選定・多言語対応・トーン & ボイスが業務要件と同一粒度で `functional/[機能名].md` などに混在している。`ブランドガイドライン.md` への分離を推奨
- `data-if`: 主要エンティティの識別子・保持単位（`データモデル.md` で定義）、外部 IF の実行主体（バッチ / イベント駆動）・実行タイミング（`外部インターフェース一覧.md` で定義）、論理削除後のデータ保持方針のいずれかが概念レベルでも未記載（物理設計の話ではない）

### NIT（無視。fix 対象外）

- `style`: 末尾空白、見出しレベルのブレ
- `typo`: 軽微な誤字（意味が通る範囲）

## 出力 JSON スキーマ

```json
{
  "phase": "requirements",
  "iteration": <int, state.iteration と一致>,
  "reviewed_at": "<UTC ISO8601>",
  "overall": "PASS | FAIL",
  "summary": "<1〜3 文で総評>",
  "findings": [
    {
      "severity": "BLOCK | SUGGEST | NIT",
      "path": "docs/requirements/xxx.md",
      "line": <int | null>,
      "category": "completeness | consistency | traceability | security | ambiguity | legend | usecase | activity | data_model | external_interface | migration | authorization | message_catalog | code_value | operational | security_baseline | open_question_closure | exception | status-drift | impl-leak | naming | term_variation | redundancy | testability | ac_granularity | responsibility_boundary | nonfunc-value | transition-drift | ui-mixed | data-if | risk | style | typo",
      "message": "<日本語の指摘内容>",
      "suggested_fix": "<推奨修正、任意>"
    }
  ]
}
```

- `overall` は **BLOCK が 1 件でもあれば FAIL**、0 件なら PASS。
- `iteration` は state.json と必ず一致させる。
- `findings` 配列は重要度順（BLOCK → SUGGEST → NIT）に並べる。

## 注意事項

- **このスキルでファイルを書き換えない**（diagnostics のみ）。修正は fix-requirements の責務。
- 推測で BLOCK にしない。根拠（具体ファイル名・行番号）を明示できないものは SUGGEST にする。
- review JSON の生成に失敗したら標準出力に「ERROR: <理由>」を出して終了し、orchestrator を止めさせる。
- `message` / `suggested_fix` などの自然言語フィールドで語句を強調する場合は、ASCII の `"..."` ではなく **鉤括弧 `「...」`** を使う。JSON 文字列内の `"` エスケープ漏れ事故を減らすため（過去に design phase で同事故あり）。
