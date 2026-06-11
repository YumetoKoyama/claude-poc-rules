---
name: fix-design
description: review-design が生成した review JSON の BLOCK と SUGGEST を docs/design/ に反映する。NIT は無視する。design-loop オーケストレータから呼ばれる。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# 設計書の修正

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **fix** 段を担当します。

**`context: fork` 必須**: 入力（review JSON）と出力（docs/design/ の修正）がファイル経由のため。

## 役割

直近の review JSON を入力に、**BLOCK と SUGGEST のみ**を対象として設計書ファイル（Markdown / YAML）を修正する。

## 入出力

- 入力: `.skills-state/design/state.json`（`last_review_path` を取得）
- 入力: 該当する `.skills-state/design/round-<N>-review.json`
- 入力: `docs/design/` 配下、整合確認のため `docs/requirements/` も参照可
- 出力: `docs/design/` 配下の修正

## 手順

1. **state を Read** → `last_review_path` 取得
2. **review JSON を Read** → BLOCK + SUGGEST のみリスト化
3. **修正計画**:
   - OpenAPI YAML 修正は `_common.yaml` 改訂の波及を見て一括対応
   - DB 修正は `DB定義.md` の全体 ER 図と `tables/*.md` の部分 ER 図を**両方更新**
   - 画面修正は `画面一覧.md` の画面遷移図とも整合させる
4. **修正を適用**（Edit / Write）
5. **修正サマリを stdout に**

## ルール

- BLOCK は必修。対応不能なら ESCALATE。
- SUGGEST は対応。要件側の追加判断が必要なものは ESCALATE ではなく「skipped SUGGEST: <理由>」で済ませる。
- NIT は触らない。
- **設計フェーズ中に要件の意思決定をしない**（CLAUDE.md ルール）。要件追加が必要と思ったら ESCALATE。

## 設計書修正の整合チェック（修正後に必ず確認）

- API YAML を変更した場合 → 関連する画面 md と `IF定義.md` を確認
- テーブル md を変更した場合 → 全体 ER 図、関連 API YAML、関連画面 md を確認
- 画面 md を変更した場合 → 画面遷移.md と関連 API YAML を確認
- `_common.yaml` を変更した場合 → 他の API YAML の `$ref` 参照先を確認

## 注意事項

- Mermaid 構文は壊さない（`erDiagram` / `flowchart` の構文エラーで設計書が読めなくなる）
- OpenAPI 3.1 構文を壊さない（yaml パース + spec 検証が可能な状態を保つ）
