---
name: design-guardrails
description: >
  設計書を作成・レビュー・修正するときに必ず適用するスキル。
  「設計書を書いて」「設計書を作成して」「画面設計を書いて」「API 設計をして」
  「DB 設計をして」「シーケンス設計を書いて」「セキュリティ設計を書いて」
  「設計書のレビューをして」「設計を修正して」といった設計関連作業すべてに適用する。
  requirements-guardrails の設計版。
version: 1.0.0
---

# 設計書 ガードレールスキル

このスキルは、AI が設計書を生成・補完・修正する際に、過去の評価で判明した典型的な設計欠陥パターン（Controller 肥大化・N+1 設計・ErrorResponse 分散・認可を FE に寄せる・データ需給の断絶・並行制御の欠落 等）を出力しないためのネガティブプロンプトと、縦串整合・セキュリティの必須チェックリストを提供する。

設計フェーズの produce（`design-from-requirements` / `design-from-issue`）・review（`review-design`）・fix（`fix-design`）から参照する。**CI 到達性の大原則（RC-13）**に従い、本スキルは子リポジトリへ配布されるスキル本文として実装されており、親 CLAUDE.md 単独記載に依存しない。

> **汎用化に関する注記**: 本スキルおよび本文中の具体例（「成約」「応募」「先着」「セット応募」「テナント越境」など）は、検証に用いた **運送マッチングという参考ドメイン固有の実例** である。別ドメインに適用する場合は、これらを抽象パターン（「状態遷移を持つ集約の並行制御」「界面契約の単一正典」「行レベル認可」等）として読み替えること。

---

## MUST NOT（設計書に出力してはいけないアンチパターン）

以下に該当する設計を出力してはならない。該当しそうな場合は、`negative-patterns.md` の正しいパターンに置き換えてから出力する。詳細は [references/negative-patterns.md](references/negative-patterns.md)。

### カテゴリ A: アーキテクチャ／レイヤ責務の崩れ

```
❌ Controller に業務判定・トランザクション制御・複数集約の整合ロジックを書く前提の設計（Controller 肥大化）
❌ 認可判定・自他判定・テナント越境拒否をフロントエンド側の表示制御だけに寄せる（防御の正典を FE に置く）
❌ application 層が Spring Security / presentation DTO / 通知リポジトリを直接扱う前提の設計
❌ 業務ロジックを Repository / Entity に書く前提（ドメイン貧血を超えてデータ層へ業務流出）
```

### カテゴリ B: 並行性・整合性制御の欠落（RC-01）

```
❌ 状態遷移・先着・上限 N・二重不可を、アプリ層の read-modify-write（SELECT してから判定して UPDATE）だけで保証する設計
❌ 非正規化カウンタ単独で上限判定する設計（DB 一意制約・条件付き UPDATE・行ロックの裏付けが無い）
❌ 状態遷移を持つ集約に version 列（楽観ロック）も悲観ロック方針も無い設計
❌ 複数テーブルを跨ぐ更新でロック取得順序がシーケンスに描かれていない設計
```

### カテゴリ C: 界面契約の分散・二重管理（RC-02 / RC-06）

```
❌ ErrorResponse / エラーコード値 / PageMeta を _common.yaml 以外（各 API YAML・共通部品設計.md）でも再定義する
❌ 同名スキーマ（MessageResponse 等）を複数 YAML で別定義する
❌ JSON 上の実フィールド名（code / details[].reason 等）を文書間で食い違わせる
❌ コード値 enum を コード値定義.md と _common.yaml で値・表示名が一致しないまま放置する
```

### カテゴリ D: データ需給の断絶（2026-06-12 の核心）

```
❌ 画面で「表示する」と定義した項目に、供給元 API（operationId.フィールド）が存在しない
❌ ログイン直後の画面・共通ヘッダーの表示項目が LoginResponse または /me 相当から取得できない
❌ 自他判定・権限判定に使う ID（tenantId・ownerId 等）の供給元 API が画面 md に明示されていない
❌ API のパス変数・クエリパラメータの値の出所（前画面のどの項目か）が画面遷移・シーケンスに現れない
```

### カテゴリ E: 性能・認可網羅の欠落（RC-03 / RC-11）

```
❌ 一覧取得を全件取得（ページング未設計）にする、N+1 を誘発するリレーション取得を前提にする
❌ api/*.yaml の operationId の一部が 認可設計（operationId × ロール × テナント条件）に行を持たない
❌ テナント越境の応答コード（403/404）が文書間で統一されていない
❌ 要件の必須/任意・enum が、tables の NULL 制約・API の required/enum/minimum と食い違う
```

---

## 未確定事項の扱い方

設計フェーズでは要件の意思決定（業務ルール追加・画面新設・用語定義）をしてはならない（CLAUDE.md）。設計に必要な値が要件で未確定の場合は断定で書かず、`概要.md` の「前提と未解決事項」節に切り出し、要件フェーズへのフィードバック（ESCALATE）扱いとする。

```markdown
> **[要確認]** {確認が必要な内容を1文で記述}
> - 選択肢A: {パターン1}
> - 選択肢B: {パターン2}
> - 影響範囲: {この決定が影響する画面・API・テーブル・シーケンス}
> - 確認期限の推奨: {実装着手前 / Issue 起票前 など}
```

---

## 縦串整合チェックリスト（必須）

設計書を出力・更新するとき、画面→operationId→認可→テーブル→シーケンスの **縦串一貫性** と **データ需給** を確認する。詳細手順は [references/consistency-checklist.md](references/consistency-checklist.md)。

- [ ] 画面 md が呼ぶ全 operationId が `api/*.yaml` に実在する
- [ ] 全 operationId が `セキュリティ設計.md`／`認可設計.md` に「operationId × ロール × テナント条件」の行を持つ（public は public と明記）
- [ ] CRUD 系 API のスキーマフィールドが対応する `tables/*.md` のカラムに存在する
- [ ] 主要業務・認証・通知のシーケンスが `sequences/*.md` に存在する
- [ ] 画面の表示項目・業務判定用 ID すべてに供給元 API（operationId.フィールド）がある（データ需給表）
- [ ] ErrorResponse・コード値・例外クラス名・通知宛先が `_common.yaml`／`コード値定義.md` に一元化されている
- [ ] 状態遷移を持つ集約に version 列 or 一意制約があり、ロック順序がシーケンスに描かれている
- [ ] 要件の必須/任意・enum と DB の NULL・API の required/enum が一致する

---

## セキュリティ設計チェックリスト（必須）

セキュリティ設計の必須項目（JWT 失効方針・BCrypt コスト・Clock 経由・レート制限・テナント越境応答コード等）が「方針」ではなく「確定値」で記述されているかを確認する。詳細は [references/security-checklist.md](references/security-checklist.md)。

---

## 良い点（変更・追記不要なパターン）

```
✅ 1 ファイル 1 リソースの OpenAPI 3.1（同リソースの全メソッドを集約）
✅ _common.yaml への共通スキーマ集約と $ref 参照
✅ DB定義.md の全体 ER 図 + tables/*.md の部分 ER 図
✅ SEQ / SCR / UC / ACT / API operationId / AC の相互参照構造
✅ 概要.md の「前提と未解決事項」による未確定の別管理
```

これらの構造・フォーマットは維持しながら、不足している内容を補完すること。

---

## 参照ファイル

- `references/negative-patterns.md` — Controller 肥大化・N+1 設計・ErrorResponse 分散・認可を FE に寄せる 等の設計アンチパターン詳細
- `references/consistency-checklist.md` — 画面→operationId→認可→テーブル→シーケンスの縦串＋データ需給表の確認手順
- `references/security-checklist.md` — セキュリティ設計の必須項目チェックリスト
