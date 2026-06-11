---
name: java-todo-team-bootstrap
description: 【非推奨 / DEPRECATED】Agent Teams（teammate 機能）で開発チームを組成する旧 skill。本プロジェクトは Agent Teams を使用しない方針（docs/architecture/skill-orchestration.md §1・§8）に統一したため非推奨。requirements-loop / design-loop / implement-loop の skill 連鎖を使うこと。
---

# 【非推奨】React + Spring Boot Web アプリ用 team 起動

> **この skill は非推奨（DEPRECATED）です。使用しないでください。**
>
> 本プロジェクトの AI 駆動開発は **skill 連鎖だけ**でワークフローを組み立てる方針に統一されました（[docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) §1「Agent Teams は使用しない」、§8「旧 agent は skill 群に責務移管し非推奨スタブ化」）。
>
> この skill が前提としていた Agent Teams（experimental の teammate 機能）と、`requirements-author` / `springboot-backend-implementer` などの custom agent は **使用しません**。

## 後継の使い方

各フェーズは対応する `*-loop` オーケストレータ skill を使う（CLAUDE.md「開発フロー」参照）。

| かつての teammate / 役割 | 後継 |
| --- | --- |
| requirements-author | `/requirements-loop`（内部で `/requirements-from-input` → `/review-requirements` → `/fix-requirements`） |
| requirements-spec-designer | `/design-loop`（内部で `/design-from-requirements` → `/review-design` → `/fix-design`） |
| springboot-backend-implementer / react-frontend-implementer / db-schema-implementer | `/implement-loop <ISSUE>`（内部の `/implement-from-issue` が単一セッションで実装） |
| unit-test-engineer | `/implement-from-issue` の品質ゲート（`/unit-test-from-design`） |
| static-analysis-engineer | 同上（`/static-analysis-remediation`） |
| e2e-test-engineer | 同上（`/e2e-from-design`） |
| coverage-maximizer | `/coverage-to-100`（カバレッジ不足は review-implementation が BLOCK 指摘） |
| failure-investigator | `/fix-implementation`（失敗解析は fix skill 内で実施） |

## 並列実行が必要な場合

品質ゲート（UT / 静的解析 / E2E）の並列化は、Agent Teams ではなく Pattern 2（Parallel Fan-Out）として `/implement-from-issue` 手順 5 で扱う。

> この skill は後方互換のための案内のみを残し、team 組成は行わない。
