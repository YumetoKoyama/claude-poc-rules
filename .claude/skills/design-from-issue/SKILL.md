---
name: design-from-issue
description: 設計書作成 Issue（要件定義書のマージを契機に自動起票されたもの）をもとに、対象の要件定義書を特定して design-from-requirements と同等の設計成果物を作成するときに使う。設計フェーズ専用であり、実装・テストには進まない。
context: fork
argument-hint: <ISSUE-NUMBER>
---

# GitHub Issue から設計書を作成する

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

このスキルは `/design-loop` の **produce 段**を Issue 起点で担う（review は `/review-design`、fix は `/fix-design` が担当）。docs リポジトリでは製造（実装）を行わないため、設計書作成 Issue に対して `implement-from-issue` を呼んではならない。

対象 Issue: $ARGUMENTS

## 前提条件

- `gh` CLI がインストール・認証済みであること（`GH_TOKEN` 環境変数。`gh auth status` で確認）
- 対象 Issue が設計書作成 Issue であること（要件定義書の `main` マージを契機に `create-issues-from-docs` が起票したもの。本文に「変更された要件定義書」セクションを持つ）

## 手順

### 1. Issue 情報の取得

1. `gh issue view $ARGUMENTS --json number,title,body,labels,url` で Issue を取得する。
2. Issue 本文から以下を内部メモに整理する:
   - 「変更された要件定義書」セクションのファイルパス一覧（設計入力のスコープ）
   - 受け入れ条件・依存する Issue
3. Issue が設計書作成 Issue でない場合（実装 Issue・要件 Issue 等）は**中断**し、対象外である旨と適切なスキル（実装は各実装リポジトリの `/implement-loop`）を報告する。

### 2. 採択ゲート（必須）

設計の入力は**採択済み（= docs の `main` にマージ済み）の要件定義書**に限る。

- CI（main マージ契機で自動起票された Issue）の場合: 起票元の要件定義書は `main` にマージ済みのため自明。チェックアウトされている `docs/requirements/` をそのまま入力とする。
- ローカル実行の場合: `git log origin/main -- docs/requirements/` 等で、ステップ 1 で特定したファイルが `main` に存在することを確認する。未マージなら**中断**し、人手レビュー・マージを依頼する。Claude 自身がマージして採択扱いにしてはならない。

### 3. スタック確定ゲート（必須）

`bash .claude/skills/_common/scripts/check-stack-decided.sh` を実行する。exit 1（`要確定` の残存、または確定表 `*-00-stack.md` の不存在）の場合は設計を**開始せず**、未確定項目の一覧をそのまま人間に提示して中断する。Claude が既定値で補完して続行してはならない（CLAUDE.md「技術スタックの正典と確定ルール」）。

### 4. 設計成果物の作成

ステップ 1 で特定した要件定義書（特定できない場合は `docs/requirements/` 全件）を入力として、
**[design-from-requirements/SKILL.md](../design-from-requirements/SKILL.md) の「成果物」「指示」「完了条件」にそのまま従って** `docs/design/` 配下に設計書を作成・更新する。

- ファイル構造テンプレート: [design-spec-template.md](../design-from-requirements/design-spec-template.md)
- 変更された要件定義書に関係する設計書のみ作成・更新し、無関係な既存ファイルは書き換えない（加算型の変更を優先）。
- 要件定義に存在しない仕様を勝手に補完しない。不明点は `docs/design/概要.md` の「前提と未解決事項」節に列挙する。

### 5. 結果の報告

作成・更新した設計書の一覧と、design-from-requirements の完了条件に対する充足状況を報告する。

## 責務の境界

- 本スキルの責務は**設計成果物の作成まで**。レビュー・修正の反復は `/design-loop`（`/review-design` / `/fix-design`）が行う。
- feature ブランチの作成・コミット・push・PR 作成・Issue へのコメントは**呼び出し元**（CI workflow または設計書作成 Issue の実施手順に従う人手 / 上位セッション）の責務であり、本スキルでは行わない。
- 実装、UT、カバレッジ改善、静的解析、E2E の実行やファイル作成には進まない。
- 設計書の採択は人手レビューと docs `main` への PR マージで行う。本スキル・ループの PASS は採択ではない。

## 完了条件

- Issue 本文から設計入力（対象の要件定義書）が特定されている。
- 採択ゲート・スタック確定ゲートを通過している（未通過なら中断し報告済み）。
- design-from-requirements の完了条件を満たす設計成果物が `docs/design/` 配下に出力されている。
- 後続工程（コミット・PR・人手レビュー）が未着手であることが明記されている。
