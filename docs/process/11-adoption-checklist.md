# 11. 要件採択チェックリスト（R-02 / R-05）

要件定義の採択（= docs リポ `main` へのマージ）を行う人間（要件採択者）の標準手順。
requirements-loop が PASS しただけでは採択ではない（PP-4）。本チェックリストの完遂をもって採択とする。

> 背景: 第 2 サイクルのパイロットで「オープン課題をクローズしても確定値が要件本文に未反映のまま残り、
> 設計フェーズの fix が採択済み要件を書き換えて辻褄を合わせる」事故が発生した（課題台帳 第2サイクル R-02 / D-01）。
> 本手順はその再発防止として、クローズ→反映→機械検査→コミットを一連の採択作業に固定する。

## 手順

1. **PASS 確認**: requirements-loop の PASS サマリと `レビュー結果.md`（検査観点・uncovered）を確認する。
2. **Q クローズ（値の確定）**: `/design-pre-research` を実行し、「設計着手前にクローズ必須」区分の Q-ID について
   解決案の提示を受け、承認・修正して確定する。委任してクローズさせた場合は、決定者欄に代行と判断根拠を明記させる。
3. **確定値の本文反映**: クローズした Q の確定値を、その Q を参照している**すべての要件ファイル**へ反映する
   （オープン課題.md の決定内容欄だけで終わらせない。プレースホルダ「未確定/要確定/要確認 → Q-XXX」を確定表記に置換）。
4. **機械検査（すべて緑になるまで 3. に戻る）**:

   ```bash
   bash .claude/skills/_common/scripts/check-open-issues.sh <requirements-dir>          # 必須 Q が全クローズか（文書の区分表が正）
   bash .claude/skills/_common/scripts/check-closed-reflected.sh <requirements-dir> --gate   # 確定値が本文へ反映済みか
   bash .claude/skills/_common/scripts/check-id-uniqueness.sh <requirements-dir> --gate      # AC 採番の一意性・修飾参照
   bash .claude/skills/_common/scripts/check-confirmed-values.sh <requirements-dir> <requirements-dir>  # 確定値の数値矛盾
   ```

5. **採択コミット**: docs リポ `main` へ PR マージ（ローカル運用時は main へコミット）。
   コミットメッセージにクローズ件数・代行判断の有無を記録する。
6. **凍結・対象外・代行判断の記録**: スコープ外・凍結・委任判断は Decision Log（D-ID）へ記録する（07-decision-log.md）。

## 禁止事項

- 設計フェーズ（design-loop / fix-design）による `docs/requirements/` の直接編集（D-01。要件起因の指摘は
  `requirements-feedback.md` 起票 → 本チェックリストで人手反映）。
- 状態列以外への状態語の記入・Q-ID を含む注記文への「open」等の記載は不要な誤判定を招くため避ける（R-04 対応済みだが慣例として）。
