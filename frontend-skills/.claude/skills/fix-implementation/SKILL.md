---
name: fix-implementation
description: review-implementation が生成した review JSON の BLOCK・SUGGEST・NIT を、現在の feature ブランチに追加コミットして反映する。implement-loop オーケストレータから呼ばれる。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Edit, Write
---

# 実装の修正

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

このスキルは Pattern 4（Iterative Loop）における **fix** 段を担当します。

**`context: fork` 必須**: 入力（review JSON）と出力（コード修正 + テスト追加）がファイル経由のため。

## 役割

<!-- rules 改善（RC-08）: NIT も修正対象に含める -->
直近の review JSON を入力に、**BLOCK・SUGGEST・NIT** をすべて修正する。スキップした指摘は該当箇所にレビューマーカーを残す。同じ feature ブランチに追加コミット + push する。**新規 PR は作らない**（produce skill で既に作成済みの PR を更新する）。

## 入出力

- 入力: `.skills-state/implement/state.json`（`last_review_path` を取得）
- 入力: 該当する `.skills-state/implement/round-<N>-review.json`
- 入力: 関連設計書（`docs/design/` 配下）
- 出力: 現在の feature ブランチへのコミット + push
- 副作用: 既存 PR の自動更新（`git push` だけで PR が自動追従。gh での PR 再作成は不要）

## 手順

1. **state を Read** → `last_review_path` 取得
2. **review JSON を Read** → BLOCK + SUGGEST + NIT をリスト化、カテゴリ別にグルーピング（すべて修正対象。rules 改善 RC-08）
3. **現在のブランチ確認**: `git branch --show-current` で `feature/issue-<N>` 形式であることを確認。違うブランチなら ESCALATE。
4. **修正を適用**:
   - `quality_gate` BLOCK → 失敗テストを特定し、コード or テストを修正
   - `coverage` BLOCK → 不足箇所のテストを追加
   - `design_mismatch` BLOCK → 設計書に合わせる方向で修正（設計が間違っている場合は ESCALATE）
   - `security` BLOCK → 脆弱性を修正、テスト追加
   - `architecture` BLOCK → リファクタ
   <!-- rules 改善: FE 契約・dead-field・共通部品の BLOCK カテゴリを追加（review-implementation の観点と対応） -->
   - `contract` BLOCK → OpenAPI スキーマ ⇔ FE 型 のフィールド名・型・nullable/必須を一致させる。**設計（OpenAPI）を正典とし、FE 実装側を合わせる**。設計の API レスポンスにフィールドが無い場合は ESCALATE
   - `dead-field` BLOCK → 空文字・固定値・`|| 'デフォルト'` での握り潰しを撤去し、API レスポンスの正規フィールドから値を取得する。供給元フィールドが API に無いなら ESCALATE（設計のレスポンス追加が必要）
   - `common_component` BLOCK → 設計済みの共通部品（`apiClient.ts` 等 `共通部品設計.md` 定義）を再発明している箇所を、既存共通部品の import・利用へ置き換える
   - `frontend_convention` BLOCK → `.claude/rules/frontend-*.md`（ディレクトリ構成・状態管理・API 連携・ルーティング認可3層）に違反する実装を frontend ルールに合わせて是正する（正典は frontend ルール）
   - `traceability` BLOCK → コミットメッセージへの Issue 参照追加 or テスト追加
   - SUGGEST → 可能な範囲で対応（時間がかかるものはスキップして stdout に「skipped SUGGEST: <理由>」、マーカーは step 6 で挿入）
5. **品質ゲートを再実行（②コード変更時のみ）**: まず `bash .claude/skills/_common/scripts/gate-content-hash.sh` を実行し、前回ゲート時の `coverage/.gate-content` と比較する。**コード内容ハッシュが変化している場合**（src / 依存・ビルド定義 / 静的解析設定を修正した場合）のみ、単体テスト（Vitest）・静的解析（ESLint / Prettier / 型チェック）を **Pattern 2 で並列実行**（記事の Parallel Fan-Out）し全グリーンを確認する。**ハッシュが不変の場合**（docs/テストマトリクス等の doc 専用修正のみ）は、高コストな UT/静的解析の再実行は不要（前回結果が現コードに対して有効）。テストマトリクス系は安価な `check-test-matrix.sh docs/test <ISSUE> unit` だけ確認する。
   <!-- rules 改善（RC-09）: forked skill 内のバックグラウンド実行禁止（fix 初回空振り・約30分ロスの直接原因） -->
   **全ゲートは同期実行（完了待ち）とする（RC-09）**。カバレッジ計測・テスト実行をバックグラウンド起動（`run_in_background` / 末尾 `&`）したまま次の手順へ進んではならない。本スキルは `context: fork` で動くため、fork の終了とともにバックグラウンドプロセスが死に、レポート・サイドカー未生成のまま「コミットなしで終了」する事故が実際に発生した。実行が長い場合はディレクトリ分割の**同期**実行（例: `npx vitest run src/features/<feature> --coverage` を順に実施）で対処し、非同期化はしない。
<!-- rules 改善（ADD-2）: 修正後の簡易整合チェックを fix 内で行い、次 review を待たずに自己是正してループ回数を削減 -->
5.5. **修正後の簡易整合チェック（ADD-2・FE 版）**: 追加・変更した実装が設計値・契約と整合するかを、同じ fix 内で確認する（次の review iteration を待たずに自己是正する）。
   - 契約: 触れた API について OpenAPI スキーマ ⇔ FE 型 のフィールド名・型・nullable が一致するか（空文字・固定値での握り潰しが残っていないか＝dead-field 回帰）。
   - 共通部品: `apiClient.ts` 等の共通部品を再発明していないか（`fetch`/`axios` の素呼び出しが新規に残っていないか）。
   - 規約: `.claude/rules/frontend-*.md` のディレクトリ構成・テスト命名・状態管理規約に沿っているか。
   - 追加した TC-XXX が単体マトリクス・RTM に反映され `check-test-matrix.sh docs/test <ISSUE> unit` が exit 0 か。
   新たな不整合を発見したら **同じ fix 内で修正**し、品質ゲートと本チェックを再実行する。設計変更が必要な不整合は ESCALATE。
6. **レビューマーカーを挿入**: スキップした指摘（SUGGEST・NIT 問わず）の該当箇所にマーカーコメントを挿入（「レビューマーカー」節参照）
7. **サイドカー更新 → コミットと push**: まず最終コード（手順6のレビューマーカー挿入後）に対して `bash .claude/skills/_common/scripts/gate-content-hash.sh > coverage/.gate-content` でサイドカーを更新する（コード内容基準なのでコミットしても review 側の再計算と一致する）。続いてコミット:
   ```bash
   git add <変更ファイルを個別指定>  # git add -A は禁止
   git commit -m "fix(#<ISSUE-N>): <修正概要>

   <修正した BLOCK / SUGGEST のサマリ>

   Refs: #<ISSUE-N>"
   git push
   ```
8. **修正サマリを stdout に出力**

## ルール

- BLOCK は必修。対応不能なら ESCALATE。
- SUGGEST は対応。対応に時間がかかるものはスキップ可（stdout で明示）。
<!-- rules 改善（RC-08）: NIT も極力対応し、スキップ分はレビューマーカーを残す -->
- **NIT も極力対応する**。命名規約・インポート順序・コメント体裁・型の厳密化など、機能に影響しない軽微な修正は積極的に行う。品質ゲート（UT / 静的解析）が通る範囲で対応し、リスクが大きい場合のみスキップ可（stdout に「skipped NIT: <理由>」）。
- **スキップした SUGGEST・NIT は該当箇所にレビューマーカーを残す**（後述「レビューマーカー」節参照）。
- **`main` / `master` / `develop` には push しない**（deny ルールでも禁止）。
- **`.github/workflows/**` は編集しない**（deny ルールで禁止）。CI 変更が必要な場合は ESCALATE。
- **新規 PR は作らない**。同じ feature ブランチに push するだけ。
- 品質ゲートが赤のまま push しない（再実行で緑になるまで修正を続ける）。
<!-- rules 改善（RC-09）: forked skill 内のバックグラウンド実行禁止 -->
- **バックグラウンド実行の禁止（RC-09）**: `context: fork` の本スキル内では、テスト・カバレッジ・静的解析を含む全コマンドを同期実行し完了を待つ。fork 終了とともにバックグラウンドプロセスは死ぬため、`run_in_background` / 末尾 `&` での起動は禁止。手順5（ゲート再実行）と手順7（サイドカー更新）の完了を確認してからコミット・push する。

## レビューマーカー

スキップした SUGGEST・NIT は、該当箇所にマーカーコメントを挿入する（rules 改善・RC-08）。

### 形式

ソースコード（TypeScript / React 等）:

```typescript
// REVIEW-SUGGEST: [RI-042] useEffect の依存配列を精査する
// REVIEW-NIT: [RI-058] props の型名を PascalCase に統一
```

テストコード:

```typescript
// REVIEW-SUGGEST: [RI-042] 境界値テストケースを追加する
```

Markdown（テストマトリクス等）:

```
<!-- REVIEW-SUGGEST: [RI-042] TC-015 の期待値が設計書と不一致 -->
```

### ルール

- `REVIEW-SUGGEST:` / `REVIEW-NIT:` を prefix とする（既存の `TODO` / `FIXME` と区別するための専用 prefix）。
- review JSON の finding ID があれば `[RI-042]` 形式で付与する。
- 該当箇所の **直前行** に挿入。特定できない場合はコンポーネント/関数の先頭コメントにまとめる。
- マーカーは修正ではないため、既存のコードを書き換えない。
- マーカー挿入後も品質ゲート（型チェック・テスト・静的解析）が通ることを確認する。コメント構文が言語に合っていることに注意（`.md` は `<!-- -->`、`.ts` / `.tsx` は `//`）。

## 注意事項

- `.env` への書き込み禁止（deny ルール）
- 機密ファイル（SSH 鍵・credentials）の参照禁止（deny ルール + hook）
- 大規模 refactor が必要な BLOCK（30 ファイル以上の変更が要りそう）は ESCALATE して人手介入を求める
