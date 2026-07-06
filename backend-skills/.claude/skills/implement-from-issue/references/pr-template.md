# PR 本文テンプレート

<!-- 2026-07-02 再生成: 末尾切断(D-1)を SKILL.md 手順7（gh pr create --body-file）と突合して復元 -->

`gh pr create` の `--body-file` に渡す一時ファイルとして使用する。

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
- 設計書: docs/design/（claude-poc-docs。対象の screens/SCR-*.md・api/*.yaml・tables/*.md を列挙）
- レビュー結果: docs/review/（own リポジトリ。implement round ごとの記録）
```

- `<...>` のプレースホルダはすべて実値に置き換えてから `gh pr create` に渡す（残置したまま PR を作らない）。
- 品質チェック結果の数値はレポート実物（`target/site/jacoco/jacoco.xml` / `coverage/`）から転記する（推測値の記入を禁止）。

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
