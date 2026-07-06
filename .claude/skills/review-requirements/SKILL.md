---
name: review-requirements
description: docs/requirements/ 配下の要件定義書一式をレビューし、BLOCK/SUGGEST/NIT の重大度付き JSON を出力する。requirements-loop オーケストレータから呼ばれる。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Write
---

# 要件定義レビュー
> **STATE_DIR の解決（D-03・最初に必ず 1 回）**: `STATE_DIR="$(bash .claude/skills/_common/scripts/state-dir.sh requirements)"` を実行し、以降の `<STATE_DIR>` はこの絶対パスを指す。`.skills-state/...` の相対パス直書きは禁止（書き手による state 置き場の分裂防止）。


> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **review** 段を担当します。

**`context: fork` 必須**: produce skill（`/requirements-from-input`）の思考プロセスを引き継がず、書かれた成果物だけで独立判定するため。

> **判定の独立性（厳守）**: 以下の理由で BLOCK の深刻度を下げてはならない。
> - 「前ラウンドで指摘済みだから」「fix が試みられたが不完全だから SUGGEST に格下げ」
> - 「escalate（人手介入）を避けるため」「残り回数が少ないから」
> - 「ループの最終回だから通してあげる」
>
> 各指摘は**今回の成果物の品質だけ**で判定する。過去の経緯・ループの進行状況・後続フェーズへの影響は一切考慮しない。state.json の iteration 値はファイル名決定にのみ使い、判定基準に影響させない。
>
> **禁止行為**:
> - 前ラウンドの review JSON（`round-*-review.json`）を Read しない
> - 前ラウンドの指摘が対応されたかを確認しない（それは verify-fix の責務）
> - レビュー結果.md を Read しない（追記はオーケストレーターの責務）
> - 標準出力に JSON パス以外（サマリ・対応確認・統計等）を出力しない

## 役割

`docs/requirements/` 配下の要件定義書を網羅的に読み、観点別にレビューして、機械可読 JSON を生成する。

## 入出力

- 入力: `docs/requirements/` 配下の Markdown ファイル一式
- 出力: `<STATE_DIR>/round-<N>-review.json`
- 出力（標準出力）: 生成した review JSON の絶対パスを 1 行だけ出力（orchestrator が読み取る）


## 手順

1. **iteration を取得**: `bash .claude/skills/_common/scripts/get-review-iteration.sh requirements` を実行し、stdout の数値を `N` とする。出力ファイル名を `round-<N>-review.json` とする。state.json を直接 Read してはならない（判定の独立性のため）。
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
3.5. 切断チェック（必須）: 次のスクリプトでファイル切断・破損を機械的に検出し、findings JSON を一時ファイルに保存する。
   ```bash
   bash .claude/skills/_common/scripts/check-truncation.sh docs/requirements/
   bash .claude/skills/_common/scripts/check-doc-lint.sh docs/requirements/   # 非日本語混入・用語表記揺れ・TODO 残置（i18n/NIT 候補。RC-11）
   bash .claude/skills/_common/scripts/check-id-uniqueness.sh docs/requirements/ > <STATE_DIR>/round-<N>-id-uniqueness.json   # AC 採番の機能内重複・曖昧参照（R-01）
   ```
   - 出力は findings JSON 配列（BLOCK / SUGGEST / NIT の重大度付き、`severity` `path` `line` `category` `message` `suggested_fix` の各フィールドを持つ）。
   - 検出内容: Invalid UTF-8（マルチバイト文字途中切断 = BLOCK）、日本語末尾で句読点なし（体言止めは許容・SUGGEST）、Markdown テーブル行が `|` で閉じていない（SUGGEST）、末尾近傍で括弧未閉じ（SUGGEST）、連続 ASCII 行 5 行以上の英語混入（`i18n` SUGGEST・RC-11）、末尾改行なし（NIT）。
   - スクリプトの findings JSON は `<STATE_DIR>/round-<N>-check-truncation.json` 等の一時ファイルに保存し、`format-review-json.sh` の `--merge-json` で取り込む（手動マージ禁止）。 偽陽性の除外は `<STATE_DIR>/suppressions.tsv` への理由つき宣言のみ（D-02・手動除外禁止）。重複（同一 path × 同一 message）は自動的に片方だけ残る。

4. **findings を TSV で出力（JSON 手書き禁止・P-08）**: 自分のレビューで見つけた指摘を
   `<STATE_DIR>/round-<N>-findings.tsv` に 1 行 1 指摘のタブ区切りで Write する
   （列: severity/category/path/line/message/suggested_fix/related_files。message 内の強調は鉤括弧「」を使い、タブ・改行を含めない）。
   決定論スクリプト（check-*.sh）の findings JSON はファイルに保存しておき、手動でマージしない。
5. **検査済み観点リストを TSV で出力（P-10・必須）**: `<STATE_DIR>/round-<N>-aspects.tsv` に、
   本スキルの全レビュー観点カテゴリ + 実行した決定論スクリプトを 1 行ずつ
   （列: aspect/status(checked|partial|not-checked)/method(script|llm|none)/note）記載する。
   全観点を必ず列挙し、見なかった観点は not-checked + 理由を書く（沈黙スキップの禁止）。
6. **review JSON を機械生成**:
   ```bash
   bash .claude/skills/_common/scripts/format-review-json.sh requirements \
     <STATE_DIR>/round-<N>-findings.tsv \
     <STATE_DIR>/round-<N>-review.json \
     --aspects <STATE_DIR>/round-<N>-aspects.tsv \
     --summary <summaryファイル(任意)> \
     --merge-json <check-*.shのfindings JSONファイル>...
   ```
   生成とスキーマ検証は機械化されているため、JSON の自己修正リトライは不要。TSV 形式エラー（exit 1）の場合のみ該当行を直して再実行する。
7. **標準出力**: 最終行に **review JSON の相対パスのみ** を 1 行で出力する（orchestrator がパース）。レビュー結果.md への追記はオーケストレーターが担当するため、本スキルでは行わない。

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
- `authorization`: `権限マトリクス.md` が **存在しない**、または「ロール 1 種・認可制御なし」の明示も無いまま空のテーブルが残っている。`functional/*.md` や `業務ルール.md` で複数ロール（依頼側/受注側・管理者/一般等）や権限境界が言及されているのに、ロール × 操作可否の一覧が `権限マトリクス.md` 側に無い場合も BLOCK。**さらに権限マトリクスの完全性を BLOCK として検証する（RC-10）**: (1) `ユースケース図.md` で採番された **全 UC-XXX × 全ロール** の組み合わせについて操作可否（C/R/U/D・状態遷移の可否）が記載されているか（行・列の欠落セルがあれば BLOCK）、(2) **テナント越境（自テナント外リソースの参照・操作）の拒否条件** が明記されているか（マルチテナント前提なのに越境拒否条件の記載が無ければ BLOCK）。「該当しない」セルも空欄でなく「不可」「N/A（理由）」等を明示する
- `message_catalog`: `メッセージ一覧.md` が **存在しない**、または画面仕様・通知でユーザー向け文言が言及されているのに MSG-XXX 採番の正典が無い。エラー/確認/バリデーション文言が各画面に断定で散在し未集約の場合も BLOCK（未確定文言は `Q-MSG*` へ切り出すこと）
- `code_value`: `コード値定義.md` が **存在しない**、または「区分値なし」の明示も無いまま、業務ルール・状態遷移（ST-XXX）でステータス/種別が登場するのに区分値の概念正典が無い
- `operational`: 非機能要件の「運用・障害対応」セクションが完全に空、または **バックアップ・障害通知・稼働時間帯のすべて** が TBD/オープン課題のままで本文に確定値が無い（うち最低限：稼働時間帯・バックアップ最低頻度・障害検知方法は本文確定が必要）
- `security_baseline`: 非機能要件のセキュリティで **パスワードポリシー / セッション有効時間 / 通信暗号化** のいずれかが本文未確定（TBD / オープン課題のみ）。これらは設計着手前に確定が必要
- `legend`: ドキュメント内で **未定義の ID または略号** を使用（例: `Q-A1` などのプレフィックスが本文に登場するのに、当該ドキュメント冒頭に凡例表が無い／凡例から漏れている）。CLAUDE.md「略号には凡例を明記」ルール違反。`SCR-XXX` `AC-XXX` `BR-XXX` のように他ドキュメントで定義済みの ID を **引用のみ** で使用している場合は SUGGEST 扱い（出典への参照リンクが望ましいため）
- `open_question_closure`: `オープン課題.md` に **クローズ運用ルール章（設計着手前クローズ必須課題の区分とクローズ手順）** が存在しない。または `Q-NF*`（パスワードポリシー・対象ブラウザ・バックアップ等）が open のまま本文側で TBD になっている（クローズと本文反映の両方が必要）
- `exception`: 正常系は記述されているが、以下の例外系が **完全に未記載**：同時操作競合の制御方針・取消可否（運送開始 / 完了報告等）・差戻し要否・論理削除中（削除〜物理削除間）データの画面表示方針。詳細パターンは [requirements-guardrails/references/negative-patterns.md](../requirements-guardrails/references/negative-patterns.md) カテゴリ B を参照
- `status-drift`: 用語集で「第 1 版では使用しない」と定義されたステータス、または用語集に未登録のステータスが業務ルール・画面仕様・フロー図などの他資料で参照されている。あるいは同一概念に複数の表記（成約／契約成立／確定 等）が資料間で混在している。**未使用ステータス（例: CANCELLED/ST-007 等、第 1 版で使わないと定義したもの）への遷移経路が状態遷移図・業務ルールに残っている場合も BLOCK**（「遷移禁止」を明記するか、状態自体を削除すること。RC-10 R-04）
- `impl-leak`: フレームワーク名・ライブラリ名（例: Spring Security、React、Redux）・DB カラム名・API パスが要件として記述されている（設計工程の責務であり要件定義書に含めてはならない）。詳細は [requirements-guardrails/SKILL.md](../requirements-guardrails/SKILL.md) カテゴリ D を参照
- `spec_quality`: `functional/[機能名].md` で以下のいずれかが欠如している — (1) ユーザーストーリーに優先度（P1/P2/P3 形式）が付いていない、(2) 成功基準（Success Criteria / SC-XXX）セクションが存在しない、(3) 成功基準が「方針」のみで定量指標（時間・件数・割合等）が 1 件も含まれていない。これらは MVP 判断・受け入れテスト設計の基盤となるため BLOCK
- `spec_quality_impl`: 成功基準（SC-XXX）にフレームワーク名・ライブラリ名・DB 製品名・API 応答時間などの技術実装詳細が含まれている（成功基準は技術非依存・利用者視点で記述する必要がある）

### SUGGEST（修正対象だが PASS は阻害しない）

- `naming`: 用語の表記揺れ（「ユーザ」⇔「ユーザー」、英日混在）
- `term_variation`: 用語集に「同義」と明記されている用語（例: 「テナント」⇔「企業アカウント」、「荷主」⇔「配送依頼企業」）が本文中で混在しており、意図的な使い分けの根拠も書かれていない。用語集準拠で片方に寄せるべき
- `redundancy`: 同じ要件が複数ファイルで重複定義
- `testability`: AC が「動作する」のように検証可能性が低い表現
- `ac_granularity`: 同じプロジェクト内で機能間の AC 粒度が大きく異なる。**具体的な検出基準（ADD-6）**: (1) `functional/*.md` の AC に「異常系」区分が 0 件の機能がある（**入力フォームを持つ機能なら最低 1 件の異常系 AC が期待される**）、(2) 「境界値」区分が 0 件の機能がある（**数値・日付・文字列長の入力がある機能なら最低 1 件が期待される**）、(3) 「権限境界」区分が 0 件の機能がある（**複数ロールが関与する機能なら最低 1 件が期待される**）。いずれかに該当する場合 SUGGEST。区分名（正常系/異常系/境界値/権限境界）が AC 表に列として無い場合も、区分の明示を促す SUGGEST とする
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
- `spec_quality`: `functional/[機能名].md` に以下が欠落している — (1) ユーザーストーリーの独立テスト（`独立テスト: ...` 形式）が記述されていない、(2) 前提条件（Assumptions）セクションが存在しない、(3) エッジケース（AC-401 番台）が 1 件も定義されていない（正常系のみで閉じている）

- `data-chain`: 「入力した値を後続のどの画面・機能で使うか」のデータ連鎖（例: 登録時のユーザー名 → ヘッダー表示、テナント ID → メッセージ自他判定・配送案件認識）が AC として明示されていない。入力項目に対して利用先が一度も現れない場合に指摘（2026-06-12 ギャップ分析。連鎖の断絶は実装で空文字ワークアラウンドを誘発する根本原因）
- `ext-failure-flow`: 外部 IF（EXT-XXX）失敗時の業務フローへの影響（例: メール送信失敗時に注文を保留するか・キャンセルするか・通知のみ失敗扱いにするか）が AC・業務ルールで未定義
- `row-level-authz`: 「自分の（自テナントの）データだけ操作可」という行レベル制御（Row-level Authorization）の要否が `権限マトリクス.md` に明示されていない。ロール単位の可否だけで、レコード所有者・所属テナントによる絞り込み条件が表に現れない場合に指摘
- `i18n`: ドキュメント本文（コードブロック・テーブル・URL・ID を除く）に、連続する英語のみの文章ブロック（5 行以上）が含まれている。CLAUDE.md の共通応答ルール「日本語で記述する」に抵触する可能性（`check-truncation.sh` の `i18n` finding と対応。RC-11）

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
      "category": "completeness | consistency | traceability | security | ambiguity | legend | usecase | activity | data_model | external_interface | migration | authorization | message_catalog | code_value | operational | security_baseline | open_question_closure | exception | status-drift | impl-leak | spec_quality | spec_quality_impl | naming | term_variation | redundancy | testability | ac_granularity | responsibility_boundary | nonfunc-value | transition-drift | ui-mixed | data-if | data-chain | ext-failure-flow | row-level-authz | i18n | risk | style | typo",
      "message": "<日本語の指摘内容>",
      "suggested_fix": "<推奨修正、任意>",
      "related_files": ["<整合確認に必要な関連ファイルのパス>"]
    }
  ]
}
```

- `overall` は **BLOCK が 1 件でもあれば FAIL**、0 件なら PASS。
- `iteration` は state.json と必ず一致させる。
- `related_files` は指摘の整合確認に必要な関連ファイルのパス配列（任意。`path` 以外に参照すべきファイルがある場合に記載。verify-fix が対応確認時にこのファイルだけ読む）。
- `findings` 配列は重要度順（BLOCK → SUGGEST → NIT）に並べる。
- `checked_aspects` / `uncovered_areas`（P-10）: `format-review-json.sh` が aspects TSV から生成するフィールド。`checked_aspects` は検査した観点の一覧（aspect/status/method/note）、`uncovered_areas` は status が `checked` 以外だった観点（未検査・部分検査とその理由）の一覧。**PASS はこのリストが揃って初めて解釈可能** であり、findings が 0 件でも `uncovered_areas` に重要観点が残っていれば「検査していないだけ」の可能性がある。採択者は `uncovered_areas` を見て残リスクを判断する。

## 注意事項

- **このスキルでファイルを書き換えない**（diagnostics のみ）。修正は fix-requirements の責務。
- 推測で BLOCK にしない。根拠（具体ファイル名・行番号）を明示できないものは SUGGEST にする。
- review JSON の生成に失敗したら標準出力に「ERROR: <理由>」を出して終了し、orchestrator を止めさせる。
- `message` / `suggested_fix` などの自然言語フィールドで語句を強調する場合は、ASCII の `"..."` ではなく **鉤括弧 `「...」`** を使う。JSON 文字列内の `"` エスケープ漏れ事故を減らすため（過去に design phase で同事故あり）。
