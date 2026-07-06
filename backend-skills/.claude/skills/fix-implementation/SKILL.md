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

このスキルは [docs/architecture/skill-orchestration.md](../../../docs/architecture/skill-orchestration.md) の Pattern 4 における **fix** 段を担当します。

**`context: fork` 必須**: 入力（review JSON）と出力（コード修正 + テスト追加）がファイル経由のため。

## 役割

直近の review JSON を入力に、**BLOCK・SUGGEST・NIT** をすべて修正する。スキップした指摘は該当箇所にレビューマーカーを残す。同じ feature ブランチに追加コミット + push する。**新規 PR は作らない**（produce skill で既に作成済みの PR を更新する）。

## 入出力

- 入力: `.skills-state/implement/state.json`（`last_review_path` を取得）
- 入力: 該当する `.skills-state/implement/round-<N>-review.json`
- 入力: 関連設計書（`docs/design/` 配下）
- 出力: 現在の feature ブランチへのコミット + push
- 副作用: 既存 PR の自動更新（`git push` だけで PR が自動追従。gh での PR 再作成は不要）

## 手順

1. **state を Read** → `last_review_path` 取得
2. **review JSON を Read** → BLOCK + SUGGEST + NIT をリスト化、カテゴリ別にグルーピング（すべて修正対象）
3. **現在のブランチ確認**: `git branch --show-current` で `feature/issue-<N>` 形式であることを確認。違うブランチなら ESCALATE。
4. **修正を適用**:
   - `quality_gate` BLOCK → 失敗テストを特定し、コード or テストを修正
   - `coverage` BLOCK → 不足箇所のテストを追加（ファイル/パッケージ単位で列挙された未達箇所を埋める）
   - `design_mismatch` BLOCK → 設計書に合わせる方向で修正（migration↔tables↔Entity のカラム/型/制約/nullable・`@Version` 欠落を含む）。設計が間違っている場合は ESCALATE
   - `contract` BLOCK → OpenAPI スキーマ ⇔ FE 型 ⇔ BE DTO のフィールド名・型・nullable/必須を一致させる（Jackson の getter 名による JSON 名乖離＝`errorCode`/`code` 等は `@JsonProperty` で是正）。**設計（OpenAPI）を正典とし、実装側を合わせる**。設計の API レスポンスにフィールドが無い場合は ESCALATE
   - `dead-field` BLOCK → 空文字・固定値・`|| 'デフォルト'` での握り潰しを撤去し、API レスポンスの正規フィールドから値を取得する。供給元フィールドが API に無いなら ESCALATE（設計のレスポンス追加が必要）
   - `concurrency` BLOCK → `@Version`（楽観）/ `@Lock(PESSIMISTIC_WRITE)`（悲観）/ 条件付き UPDATE を追加し、`GlobalExceptionHandler` に 409 マッピングを追加
   - `security-baseline` BLOCK → 設計値に合わせて是正（BCrypt コスト≥12 / `Clock` 注入 / レート制限 / メール送信を `@Transactional` 外へ / JWT 失効方針 / ログインロック保存先の単一化 / EXT-001 メールアダプタの実配線）。設計値そのものを変える必要があるなら ESCALATE
   - `layer-violation` BLOCK → application 層の Spring Security / presentation DTO / 通知 Repository 直接依存を除去（通知は `ApplicationEventPublisher`、ページングは DB ページング、N+1 は一括取得へ）
   - `security` BLOCK → 脆弱性を修正、テスト追加。全 operationId の `@PreAuthorize` を認可設計に一致させ、越境は 404 統一、テナントフィルタを UPDATE/DELETE/COUNT/集計にも適用
   - `architecture` BLOCK → リファクタ
   - `traceability` BLOCK → コミットメッセージへの Issue 参照追加 or テスト追加
   - SUGGEST → 可能な範囲で対応（時間がかかるものはスキップして stdout に「skipped SUGGEST: <理由>」、マーカーは step 6 で挿入）
5. **品質ゲートを再実行（②コード変更時のみ）**: まず `bash .claude/skills/_common/scripts/gate-content-hash.sh` を実行し、前回ゲート時の `target/.gate-content` と比較する。**コード内容ハッシュが変化している場合**（src / ビルド定義 / 静的解析設定を修正した場合）のみ、単体テスト・静的解析を **Pattern 2 で並列実行**（Parallel Fan-Out）し全グリーンを確認する。**ハッシュが不変の場合**（docs/テストマトリクス等の doc 専用修正のみ）は、高コストな UT/静的解析の再実行は不要（前回結果が現コードに対して有効）。テストマトリクス系は安価な `check-test-matrix.sh ... unit` だけ確認する。
5.5. **修正後の簡易整合チェック（ADD-2・実装版）**: 追加・変更した実装が設計値・契約と整合するかを、同じ fix 内で確認する（次の review iteration を待たずに自己是正し、ループ回数を削減する）。
   - 契約: 触れた API について OpenAPI スキーマ ⇔ FE 型 ⇔ BE DTO のフィールド名・型・nullable が一致するか（可能なら `bash .claude/skills/_common/scripts/check-api-contract.sh` を再実行）。
   - 設計値: 変更したセキュリティ実装値（BCrypt コスト・JWT 有効期限・CORS・ログイン試行制限）が `docs/design/セキュリティ設計.md` の値と一致するか。
   - DB: 変更した migration / Entity が `docs/design/tables/*.md` のカラム・型・制約・nullable と一致するか（可能なら `bash .claude/skills/_common/scripts/check-migration-consistency.sh` を再実行）。
   - 追加した TC-XXX が単体マトリクス・RTM に反映され `check-test-matrix.sh ... unit` が exit 0 か。
   新たな不整合を発見したら **同じ fix 内で修正**し、品質ゲートと本チェックを再実行する。設計変更が必要な不整合は ESCALATE。
6. **レビューマーカーを挿入**: スキップした指摘（SUGGEST・NIT 問わず）の該当箇所にマーカーコメントを挿入（「レビューマーカー」節参照）
7. **サイドカー更新 → コミットと push**: まず最終コード（手順6のレビューマーカー挿入後）に対して `bash .claude/skills/_common/scripts/gate-content-hash.sh > target/.gate-content`（FE 同居時は `coverage/.gate-content` にもコピー）でサイドカーを更新する（コード内容基準なのでコミットしても review 側の再計算と一致する）。続いてコミット:
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
- **NIT も極力対応する**。命名規約・インポート順序・コメント体裁・型の厳密化など、機能に影響しない軽微な修正は積極的に行う。品質ゲート（UT / 静的解析）が通る範囲で対応し、リスクが大きい場合のみスキップ可（stdout に「skipped NIT: <理由>」）。
- **スキップした SUGGEST・NIT は該当箇所にレビューマーカーを残す**（後述「レビューマーカー」節参照）。
- **`main` / `master` / `develop` には push しない**（deny ルールでも禁止）。
- **`.github/workflows/**` は編集しない**（deny ルールで禁止）。CI 変更が必要な場合は ESCALATE。
- **新規 PR は作らない**。同じ feature ブランチに push するだけ。
- 品質ゲートが赤のまま push しない（再実行で緑になるまで修正を続ける）。

## レビューマーカー

スキップした SUGGEST・NIT は、該当箇所にマーカーコメントを挿入する。

### 形式

ソースコード（Java / TypeScript 等）:

```java
// REVIEW-SUGGEST: [RI-042] この Service メソッドのトランザクション境界を見直す
// REVIEW-NIT: [RI-058] メソッド名を設計書の命名規約に合わせる
```

```typescript
// REVIEW-SUGGEST: [RI-042] useEffect の依存配列を精査する
// REVIEW-NIT: [RI-058] props の型名を PascalCase に統一
```

テストコード:

```java
// REVIEW-SUGGEST: [RI-042] 境界値テストケースを追加する
```

Markdown（テストマトリクス等）:

```
<!-- REVIEW-SUGGEST: [RI-042] TC-015 の期待値が設計書と不一致 -->
```

### ルール

- `REVIEW-SUGGEST:` / `REVIEW-NIT:` を prefix とする（既存の `TODO` / `FIXME` と区別するための専用 prefix）。
- review JSON の finding ID があれば `[RI-042]` 形式で付与する。
- 該当箇所の **直前行** に挿入。特定できない場合はクラス/関数の先頭コメントにまとめる。
- マーカーは修正ではないため、既存のコードを書き換えない。
- マーカー挿入後も品質ゲート（コンパイル・テスト・静的解析）が通ることを確認する。コメント構文が言語に合っていることに注意（`.yaml` は `#`、`.md` は `<!-- -->`、`.java` / `.ts` は `//`）。

## 注意事項

- `.env` への書き込み禁止（deny ルール）
- 機密ファイル（SSH 鍵・credentials）の参照禁止（deny ルール + hook）
- 大規模 refactor が必要な BLOCK（30 ファイル以上の変更が要りそう）は ESCALATE して人手介入を求める
