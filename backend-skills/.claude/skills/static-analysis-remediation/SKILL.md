---
name: static-analysis-remediation
description: バックエンド（Spring Boot）とフロントエンド（React）の双方に対し、設定済みの静的解析を実行し、報告された問題を最小限で妥当な修正へ落とし込むときに使う。品質ゲートやスタイルチェック失敗時向け。
context: fork
argument-hint: [モジュールまたは解析対象]
---

# 静的解析の修正

> **呼び出し元**: `/implement-from-issue` の品質ゲート（手順 5・Pattern 2 並列ファンアウト）から「静的解析」担当として呼ばれる補助 skill。設定済みツールを優先し、新規ツールは導入しない。単独起動も可。

次の対象に対して静的解析を実行し、問題を修正する: $ARGUMENTS

## 指示

1. バックエンドは Maven でどの解析プラグイン（Checkstyle / PMD / SpotBugs 等）が設定されているか、フロントエンドは npm / pnpm 側で ESLint / Prettier / TypeScript 型チェックがどう設定されているかを確認する。
2. まず最も狭い失敗解析タスクを実行する。
3. 問題は原因箇所で修正する。
4. suppression は、ルールが不適切な場合にのみ理由つきで使う。
5. 修正確認には同じ解析コマンドを再実行する。
6. **レイヤ規約違反の機械検出（RC-04・バックエンド）**: 設定済み静的解析（ArchUnit / PMD のパッケージ依存ルール等）に加え、最低限 `grep` で次を検出し、検出時は修正する（suppress しない）:
   - `application/` 配下の `import org.springframework.security`（Spring Security 依存）
   - `application/` 配下の presentation 層 DTO import・通知 Repository（`*NotificationRepository`）直接 import
   - UseCase 内の `subList(`（メモリページング）、ループ内 `save(`（N+1 永続化）
   通知は `ApplicationEventPublisher`、一覧は DB ページングへ是正する。
