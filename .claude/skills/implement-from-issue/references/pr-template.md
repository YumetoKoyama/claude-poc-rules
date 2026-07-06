# PR 本文テンプレート

implement-from-issue 本文から 2026-07-02 に PP-5 分解で外出し。本文の該当手順から参照される。

`gh pr create --base main --head feature/issue-$ARGUMENTS --title "feat(#$ARGUMENTS): <Issue タイトル>" --body-file <一時ファイル>` に渡す本文。
PR 本文の `Closes #$ARGUMENTS` により、マージ時に対象 Issue が自動 close される。

```markdown
## 対応 Issue
- Closes #$ARGUMENTS

## 概要
<日本語で機能概要を 3〜5 行で記載>

## 実装内容
- <変更点 1>
- <変更点 2>

## 品質チェック結果
- 静的解析: ✅ 0 violations
- Unit Test: ✅ <件数> passed（バックエンド: 命令 <xx>% / 分岐 <xx>% ・ フロントエンド: ライン <xx>%、いずれも除外後）
- テスト設計: ✅ 単体マトリクス(TC)・RTM 更新済み（check-test-matrix unit 通過）
- ※ 結合テスト(IT) は結合テスト工程（/integration-test-from-design）で別途実施
- Security Review: ✅ OWASP 観点点検済み

## 関連リンク
- Issue: #$ARGUMENTS
- 要件定義: docs/requirements/（claude-poc-docs）
- 設計書: docs/design/（claude-poc-docs）
```

## 最終報告テーブル（手順9）

手順9で Markdown テーブルとして報告する内容:

```
| 項目 | 値 |
| --- | --- |
| Issue | #$ARGUMENTS |
| ブランチ | feature/issue-$ARGUMENTS |
| PR URL | https://github.com/<org>/<repo>/pull/<n> |
| Issue ラベル | status:in-review |
| 品質チェック | static-analysis ✅ / unit-test ✅ / test-design(unit ゲート) ✅ / security ✅ |
```
