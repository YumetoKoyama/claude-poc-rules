---
name: propose-canon-patch
description: 正典（rules/・CLAUDE.md・.claude/rules/・レビュースキル等）への改善を「差分提案」として canon-proposals/ に出力する。正典は直接編集しない（protect-canon.sh の保護は維持）。人間がレビューして git apply で反映する。正典改善・ルール改善・スキル改善を提案したい時に使う。
allowed-tools: Bash, Read, Glob, Grep, Write
---

# 正典差分提案（propose-canon-patch）

【P-09 / E-1 対応】`protect-canon.sh` は Claude 実行中の正典編集をブロックする（品質ゲートの
自己書き換え防止として正しい設計）。その代償として改善が滞留していたため、
本スキルで「**Claude が差分を提案 → 人間がレビューして反映**」を正式フローにする。

## 原則（厳守）

- **正典を直接 Edit / Write しない**。`ALLOW_RULES_EDIT=1` の設定・示唆もしない。
- 提案はすべて `canon-proposals/` 配下に**新規ファイルとして**出力する（正典保護と両立）。
- 1 提案 = 1 目的。無関係な変更を 1 つのパッチに混ぜない。
- 適用判断・適用作業は人間が行う。本スキルは適用しない。

## 対象（正典 = protect-canon.sh が保護するもの）

- 親 `CLAUDE.md` / 親 `rules/`（cross-cutting.md）
- 各子リポジトリの `.claude/rules/`（frontend-*.md / backend-*.md / *-00-stack.md）
- `.claude/skills/`（レビュー観点・手順の改善提案を含む）
- `.claude/hooks/`・`_common/scripts/`

## 手順

1. **提案 ID の採番**: `canon-proposals/` 配下の既存ディレクトリを Glob し、
   `CP-<3桁連番>-<日付YYYYMMDD>-<slug>` 形式で新しい提案ディレクトリ名を決める
   （例: `CP-001-20260702-review-aspects`）。
2. **現状の読み取り**: 変更対象の正典ファイルを Read し、変更前の内容を正確に把握する。
   憶測で diff を作らない。
3. **差分の生成**: 変更後の全文を `canon-proposals/<提案ID>/after/<元の相対パス>` に Write し、
   unified diff を機械生成する:
   ```bash
   mkdir -p canon-proposals/<提案ID>
   diff -u <正典の元ファイル> canon-proposals/<提案ID>/after/<相対パス> \
     > canon-proposals/<提案ID>/<連番>.patch || true   # diff は差分ありで exit 1 を返すため || true
   ```
   複数ファイルにまたがる場合はファイルごとに patch を分けて連番を振る。
4. **提案書の作成**: `canon-proposals/<提案ID>/README.md` に次を必ず書く:
   - **目的**: どの課題（P-xx / 課題台帳 ID / レビュー指摘）を解消するか
   - **変更対象**: ファイルと変更点の一覧（1 行ずつ）
   - **影響範囲**: この変更で挙動が変わる工程・スキル・CI
   - **リスクと代替案**: 適用しない場合に何が起き続けるか
   - **適用手順**（人間向け・そのままコピペ可能に）:
     ```bash
     git apply --check canon-proposals/<提案ID>/*.patch   # 事前検証
     git apply canon-proposals/<提案ID>/*.patch
     # 適用後: 同期検査（親→子配布が必要な変更の場合）
     bash .claude/skills/_common/scripts/check-claude-md-sync.sh || true
     bash .claude/skills/_common/scripts/check-skills-lineage-sync.sh . frontend-skills backend-skills || true
     ```
5. **切断チェック**: 生成した after/ と patch に対して
   `bash .claude/skills/_common/scripts/check-truncation.sh canon-proposals/<提案ID>/` を実行し、
   findings があれば修正する（D-1 再発防止）。
6. **報告**: 標準出力に提案ディレクトリのパスと README の要約（目的・対象・適用手順の 3 点）を出す。

## 提案の追跡

- 提案の状態は README 冒頭に `status: proposed | applied | rejected` を記載する
  （applied / rejected への更新は適用判断をした**人間**が行う）。
- 適用済み提案は削除せず残す（改善の監査証跡。課題台帳の「済」根拠として参照される）。

## 注意事項

- レビュー（review-*）や fix（fix-*）の実行中に正典の不備に気づいた場合も、
  その場で直そうとせず本スキルの形式で提案を残すこと（ループの成果物と正典変更を混ぜない）。
- 提案が `shared-canon` ブロックに触れる場合は、README の影響範囲に
  「子リポジトリへの再配布が必要（check-claude-md-sync.sh）」を必ず明記する。
