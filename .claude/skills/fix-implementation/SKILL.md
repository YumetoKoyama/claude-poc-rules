---
name: fix-implementation
description: review-implementation が生成した review JSON の BLOCK と SUGGEST を、現在の feature ブランチに追加コミットして反映する。NIT は無視する。implement-loop オーケストレータから呼ばれる。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# 実装の修正

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **fix** 段を担当します。

**`context: fork` 必須**: 入力（review JSON）と出力（コード修正 + テスト追加）がファイル経由のため。

## 役割

直近の review JSON を入力に、**BLOCK と SUGGEST のみ**を対象としてコード・テストを修正し、同じ feature ブランチに追加コミット + push する。**新規 PR は作らない**（produce skill で既に作成済みの PR を更新する）。

## 入出力

- 入力: `.skills-state/implement/state.json`（`last_review_path` を取得）
- 入力: 該当する `.skills-state/implement/round-<N>-review.json`
- 入力: 関連設計書（`docs/design/` 配下）
- 出力: 現在の feature ブランチへのコミット + push
- 副作用: 既存 PR の自動更新（`git push` だけで PR が自動追従。gh での PR 再作成は不要）

## 手順

1. **state を Read** → `last_review_path` 取得
2. **review JSON を Read** → BLOCK + SUGGEST のみリスト化、カテゴリ別にグルーピング
3. **現在のブランチ確認**: `git branch --show-current` で `feature/issue-<N>` 形式であることを確認。違うブランチなら ESCALATE。
4. **修正を適用**:
   - `quality_gate` BLOCK → 失敗テストを特定し、コード or テストを修正
   - `coverage` BLOCK → 不足箇所のテストを追加
   - `design_mismatch` BLOCK → 設計書に合わせる方向で修正（設計が間違っている場合は ESCALATE）
   - `security` BLOCK → 脆弱性を修正、テスト追加
   - `architecture` BLOCK → リファクタ
   - `traceability` BLOCK → コミットメッセージへの Issue 参照追加 or テスト追加
   - SUGGEST → 可能な範囲で対応（時間がかかるものはスキップして stdout に「skipped SUGGEST: <理由>」）
5. **品質ゲートを再実行**: 単体テスト・静的解析を **Pattern 2 で並列実行**（記事の Parallel Fan-Out）。全グリーンを確認。
6. **コミットと push**:
   ```bash
   git add <変更ファイルを個別指定>  # git add -A は禁止
   git commit -m "fix(#<ISSUE-N>): <修正概要>

   <修正した BLOCK / SUGGEST のサマリ>

   Refs: #<ISSUE-N>"
   git push
   ```
7. **修正サマリを stdout に出力**

## ルール

- BLOCK は必修。対応不能なら ESCALATE。
- SUGGEST は対応。対応に時間がかかるものはスキップ可（stdout で明示）。
- NIT は触らない。
- **`main` / `master` / `develop` には push しない**（deny ルールでも禁止）。
- **`.github/workflows/**` は編集しない**（deny ルールで禁止）。CI 変更が必要な場合は ESCALATE。
- **新規 PR は作らない**。同じ feature ブランチに push するだけ。
- 品質ゲートが赤のまま push しない（再実行で緑になるまで修正を続ける）。

## 注意事項

- `.env` への書き込み禁止（deny ルール）
- 機密ファイル（SSH 鍵・credentials）の参照禁止（deny ルール + hook）
- 大規模 refactor が必要な BLOCK（30 ファイル以上の変更が要りそう）は ESCALATE して人手介入を求める
