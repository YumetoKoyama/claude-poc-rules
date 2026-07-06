# PR 本文テンプレート

`gh pr create` の `--body-file` に渡す一時ファイルに以下の内容を書く。
`Closes #$ARGUMENTS` により、マージ時に対象 Issue が自動 close される。

```markdown
## 対応 Issue
- Closes #$ARGUMENTS

## 概要
<日本語で機能概要を 3〜5 行で記載>

## 実装内容
- <変更点 1>
- <変更点 2>

## 品質チェック結果
- Vitest: ✅ <件数> passed（命令 100% / 分岐 <xx>%）
- ESLint: ✅ 0 violations
- Prettier: ✅ フォーマット差分なし
- npm audit: ✅ critical/high 0 件
- Security Review: ✅ OWASP 観点点検済み
- テスト設計マトリクス: ✅ check-test-matrix.sh exit 0

## 関連リンク
- Issue: #$ARGUMENTS
- 要件定義: docs/requirements/
- 設計書: docs/design/
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
| 品質チェック | vitest ✅ / eslint ✅ / prettier ✅ / npm-audit ✅ / security ✅ / test-matrix ✅ |
```
