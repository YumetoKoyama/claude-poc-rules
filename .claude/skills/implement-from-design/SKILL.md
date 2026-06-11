---
name: implement-from-design
description: 【非推奨 / DEPRECATED】設計書から直接実装する旧 skill。Issue 起票を経る implement-loop / implement-from-issue に統合されたため非推奨。製造は /create-issues-from-design → /implement-loop <ISSUE-NUMBER> の経路を使うこと。
argument-hint: [設計書パス]
---

# 【非推奨】設計書から実装する

> **この skill は非推奨（DEPRECATED）です。`/implement-from-issue`（および `/implement-loop`）と責務が重複するため、製造フェーズではそちらを使ってください。**
>
> 本プロジェクトの製造フェーズは「設計採択 → `/create-issues-from-design` で GitHub Issue 起票 → `/implement-loop <ISSUE-NUMBER>`」を正典フローとします（[CLAUDE.md](../../../CLAUDE.md) の開発フロー）。Issue を経由することで、トレーサビリティ（Issue ↔ PR ↔ AC-XXX）と品質ゲートの実行・記録が一貫します。
>
> また、この skill が前提としていた Agent Teams（teammate 機能）は使用しません（[docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) §1・§8）。

## 後継

- Issue 起票: `/create-issues-from-design`
- 実装ループ: `/implement-loop <ISSUE-NUMBER>`（内部で `/implement-from-issue` が単一セッションで実装し、UT / 静的解析 / E2E を Pattern 2 で並列実行）

設計から直接（Issue なしで）実装したい特別な事情がある場合も、まず Issue を起票してから `/implement-loop` を使うことを推奨する。
