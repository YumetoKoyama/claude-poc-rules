---
name: reflect-handoff-to-brand
description: Claude Design の Handoff（UI 生成結果）採択後に、採択されたデザインシステム決定（色・タイポグラフィ・トークン・コンポーネント方針）をブランドガイドライン.md へ逆反映する提案を生成する。UI 採択の根拠を文書化し Q-BR 系オープン課題のクローズにつなげる。handoff 反映・ブランドガイドライン更新・デザイン決定の記録に使う。
allowed-tools: Bash, Read, Glob, Grep, Write
---

# Handoff → ブランドガイドライン逆反映（reflect-handoff-to-brand）

【P-16 対応】UI 工程は brief 投入 → Claude Design 生成 → handoff 格納まで整備されているが、
「採択したデザイン決定」がどこにも記録されず、ブランドガイドラインが未整備のまま
（Q-BR1〜3 が open）だった。本スキルは **handoff 採択のタイミングで決定を文書へ固定**する。

> **パス解決（マルチリポジトリ対応）**: `docs/requirements/`・`docs/design/` は docs リポジトリ
> （claude-poc-docs）ルート相対。親アンブレラから実行する場合は `claude-poc-docs/` を前置する。

## 起動条件（ハードゲート）

- `docs/design/ui-design/handoff/` に Export 物が格納済みであること
- `/reconcile-handoff-with-design` の BLOCK が 0 件であること（採択済み handoff にのみ実行する）

## 手順

1. **入力の読み取り**:
   - `docs/design/ui-design/handoff/` の README・tokens（存在すれば）・Export 物のうち
     テキストとして読めるもの（`.dc.html` 内の CSS 変数・トークン定義を含む）
   - `docs/design/ui-design/brief/_共通.md`（投入時に指定した DS 方針）
   - `docs/requirements/ブランドガイドライン.md`（現状）と `docs/requirements/オープン課題.md` の Q-BR 系
2. **採択されたデザイン決定の抽出**: 次の項目を handoff から機械的・網羅的に拾う。
   拾えない項目は「handoff から抽出不能（人間の確認が必要）」と明記する（推測で埋めない）:
   - カラーパレット（プライマリ / セカンダリ / セマンティック色。CSS 変数名と HEX 値）
   - タイポグラフィ（フォントファミリ・サイズスケール・ウェイト）
   - スペーシング / 角丸 / 影 等のデザイントークン
   - 共通コンポーネントの見た目方針（ボタン種別・フォーム・テーブル・バッジ等）
   - ロール別のテーマ差（SHIPPER / CARRIER で色分け等があれば）
3. **逆反映ドラフトの生成**: `docs/design/ui-design/brand-reflection/<日付YYYYMMDD>/` に出力する
   （要件正典 `ブランドガイドライン.md` を**直接書き換えない**。要件変更は人手採択が必要なため）:
   - `ブランドガイドライン_追記案.md` … 現行ガイドラインへの追記・変更を節単位で提示。
     各決定に「出典: handoff のどこから抽出したか」を併記
   - `Q-BR-クローズ案.md` … Q-BR1〜3 それぞれについて「決定内容 / 根拠（handoff 出典）/
     クローズ可否」を記載（クローズの記入自体は要件採択者が行う）
4. **brief への還流チェック**: `brief/_共通.md` の DS 記述と抽出結果が矛盾する箇所を一覧化する
   （次の画面追加時に brief が古い DS を指示してしまう事故の防止）。
5. **切断チェック**: `bash .claude/skills/_common/scripts/check-truncation.sh docs/design/ui-design/brand-reflection/` を実行。
6. **報告**: 抽出できた決定の件数・抽出不能項目・人間がやること
   （追記案のレビュー → ブランドガイドラインへの反映 PR → Q-BR クローズ）を標準出力に要約する。

## 注意事項

- 本スキルは**提案の生成まで**。要件文書（ブランドガイドライン.md）への反映と
  Q-BR クローズは人手（要件採択者）が docs PR で行う（採択ゲートの原則 PP-4 を崩さない）。
- handoff が更新されたら本スキルを再実行し、日付ディレクトリを分けて履歴を残す
  （UI 決定の変遷が追えるようにする）。
