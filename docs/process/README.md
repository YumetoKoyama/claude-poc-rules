# AI 駆動開発プロセス

最終更新: 2026-05-27

このディレクトリは、本プロジェクト（claude-poc）における AI 駆動開発の運用ガバナンスをまとめたものです。`CLAUDE.md` と `docs/architecture/skill-orchestration.md` がツール・実装レベルの規約であるのに対し、`docs/process/` は **「人と AI のどちらが、いつ、何を、どのように行うか」** という運用レベルの規約を定義します。

## 目的

- AI に何を任せ、どこから人手が必須かを **明文化** する
- skill / agent / プロンプトの作成・改訂ルールを **統一** する
- AI 生成物の **品質基準** と **レビュー観点** を共通化する
- 工程と AI ツール（Claude Code / Cowork / Claude Design 等）の使い分けを **整理** する
- 既存の skill オーケストレーション運用を、上記ルールに沿って **継続的に更新** する

## 文書構成

| # | 文書 | 内容 | 主な読者 |
|---|------|------|----------|
| 1 | [01-prompt-rules.md](01-prompt-rules.md) | プロンプト生成ルール／skill・agent 作成ルール | skill 作者・プロンプト編集者 |
| 2 | [02-review-criteria.md](02-review-criteria.md) | AI 成果物レビュー基準（マトリクス + チェックリスト） | レビュア・PM・QA |
| 3 | [03-ai-usage-scenes.md](03-ai-usage-scenes.md) | AI 利用シーン整理（工程 × ツール × 可否判断） | 開発メンバ全般 |
| 4 | [04-development-flow.md](04-development-flow.md) | 開発フロー更新（①〜③を skill オーケストレーションへ統合） | 全員 |
| 5 | [05-test-process.md](05-test-process.md) | テスト工程（戦略・生成・実行・カバレッジ改善） | QA・開発メンバ |
| 6 | [06-issue-management.md](06-issue-management.md) | Issue 管理運用（ラベル体系・ステータス遷移・依存関係・レビュー記録） | PM・開発メンバ |

## 二層構成（汎用 + プロジェクト固有）

各文書は次の二層で記述します。

- **汎用ガイドライン**: 他プロジェクトにも展開可能な、ツール非依存・スタック非依存の原則
- **本プロジェクト固有**: claude-poc（Spring Boot + React、skill オーケストレーション、GitHub Issues 中心）に特化した具体ルール

文書内では `### 汎用` / `### claude-poc 固有` セクションで明示的に分離します。

## 関連ドキュメント

- `CLAUDE.md` — 開発フロー全体・標準スタック・開発ルール（**最上位の規約**）
- `docs/architecture/skill-orchestration.md` — skill オーケストレーションの設計原則
- `docs/requirements/` — 要件定義成果物（AI 生成 + 人手レビュー）
- `docs/design/` — 設計成果物（AI 生成 + 人手レビュー）
- `.claude/skills/` — skill 定義一式

## 更新ルール

- 本ディレクトリの文書は **加算型** で更新する。重大な原則変更は PR レビュー必須。
- 各文書冒頭の「最終更新」日付を必ず更新する。
- ルール変更が `CLAUDE.md` や既存 skill に影響する場合は、同一 PR 内で関連ファイルも更新する。
- 用語は `docs/requirements/用語集.md` と整合させる。

## クイック索引

- skill を新規作成したい → [01-prompt-rules.md §3](01-prompt-rules.md#3-skill-作成ルール)
- レビュー観点を確認したい → [02-review-criteria.md §3](02-review-criteria.md#3-成果物種別チェックリスト)
- ある作業を AI に任せて良いか迷った → [03-ai-usage-scenes.md §4](03-ai-usage-scenes.md#4-ai-可否の判断フロー)
- 改訂後の開発フローを通読したい → [04-development-flow.md §2](04-development-flow.md#2-全体フロー図)
- テスト工程の運用を確認したい → [05-test-process.md](05-test-process.md)
- Issue のラベル・ステータス・依存関係を確認したい → [06-issue-management.md](06-issue-management.md)
