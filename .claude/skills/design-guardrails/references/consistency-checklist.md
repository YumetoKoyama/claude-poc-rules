# 縦串整合チェックリスト（consistency-checklist）

設計書の **縦串一貫性**（画面→operationId→認可→テーブル→シーケンス）と **データ需給** を確認する手順。`review-design` の手順 4.3 / 4.6 と `design-from-requirements` の手順 4.7 / 8.x から参照する。これらは LLM の意味判断に依存するため、可能な箇所は `_common/scripts/check-vertical-trace.sh` 等の決定論スクリプトで二重化する（RC-13）。

---

## 1. operationId 一覧の抽出

1. `screens/*.md` の各画面が「呼び出す API（operationId）」を列挙する（画面 md に API 欄を必須化）。
2. `api/*.yaml` の `paths` 配下から全 operationId を抽出する。
3. `認可設計.md`／`セキュリティ設計.md` から「operationId × ロール × テナント条件」の行を抽出する。

---

## 2. 縦串突合（5 点一貫性）

各 operationId について次を確認する。1 つでも欠ければ **`vertical-trace`／`contract-consistency` の BLOCK 候補**。

| # | 確認内容 | 欠落時の category |
|---|---|---|
| (a) | `api/*.yaml` の paths に operationId が実在する | `vertical-trace` |
| (b) | `認可設計.md`／`セキュリティ設計.md` に operationId × ロール × テナント条件の行がある（public は public と明記） | `security-design`／`vertical-trace` |
| (c) | API スキーマのエンティティ・フィールドに対応する `tables/*.md` のカラム・型がある（CRUD 系で必須） | `vertical-trace` |
| (d) | 当該 API を含むシーケンス（`sequences/*.md`）が存在する（CRUD 系で必須） | `vertical-trace` |
| (e) | 認可設計の operationId × ロールが API description・要件 `権限マトリクス.md` と一致する | `contract-consistency` |

逆方向も確認する:

- `api/*.yaml` にあるが、どの画面からも参照されない operationId（未使用 API）。
- `認可設計.md` に行があるが `api/*.yaml` に定義が無い operationId（幽霊認可行）。

---

## 3. データ需給表の作成（data-sufficiency）

全画面の表示項目・業務判定用 ID を縦軸に、供給元を対応づける表を機械的に作る。供給元の無い項目は **`data-sufficiency` の BLOCK 候補**。

| 画面 | 表示項目／判定用 ID | データ源（operationId.フィールド） | 供給元有無 |
|---|---|---|---|
| SCR-002 ダッシュボード | ユーザー名 | `login.user.displayName` または `me.displayName` | ✓ |
| SCR-002 ダッシュボード | テナント名 | （未設計） | ✗ → BLOCK |
| SCR-003 一覧 | 自他判定 ownerId | `listItems.items[].ownerId` | ✓ |

確認のポイント:

- ログイン直後の画面・共通レイアウト（ヘッダー等）の表示項目が `LoginResponse` または `/me` 相当から取れるか。
- 自他判定・権限判定に使う ID（tenantId・ownerId 等）の供給元があるか。
- API のパス変数・クエリパラメータの値の出所（前画面のどの項目・どのレスポンスフィールド）が辿れるか（`param-source`）。
- 共通シェル（ヘッダー等）の表示項目が `screens/共通レイアウト.md` に集約され、各画面 md が「所属レイアウト」で参照しているか（共通項目の画面別重複が無いか）。
- FE のエラー表示が `フロントエンド共通設計.md` で `ErrorResponse.code` → 表示文言（MSG-XXX）として対応づけられ、コード体系・文言を再定義していないか（界面契約は `_common.yaml`／要件 `コード値定義.md` が正典）。

レビュー結果 md には、この対応表を根拠として含める。

---

## 4. 界面契約の単一正典（contract-consistency / error-response / code-value-chain）

- ErrorResponse / PageMeta / コード値 enum が `_common.yaml` に一元定義され、各 YAML は `$ref` のみか。
- `共通部品設計.md` がエラーコード体系を再定義していないか（実装方式のみか）。
- 同名スキーマの重複が無いか。
- JSON 実フィールド名（`code` / `details[].reason` 等）が文書間で一致するか。
- コード値が `コード値定義.md`（要件）→ `_common.yaml`（設計）の 2 層で値・表示名が一致するか。設計新設 enum が `コード値定義.md` に掲載済みか。
- 通知の宛先粒度（user/tenant）が `tables/*.md` と一致するか。

---

## 5. 状態遷移と並行制御（concurrency / status-operation）

- 状態遷移を持つ集約（ステータス・カウンタ・先着・上限）に version 列 or 一意制約があるか。
- セット連動・複数テーブル更新のロック取得順序がシーケンスに描かれているか。
- 状態遷移のガード条件（「成約後は編集不可」等の BR-XXX）が、画面（操作の活性/非活性）と API（4xx 応答）の **両方** に反映されているか（`status-operation`）。
- 第 1 版対象外と定義したステータス（例: CANCELLED）への遷移経路が設計に残っていないか。

---

## 6. 必須/任意・enum 整合（validation-pair）

- 要件 `functional/*.md` の AC で「必須入力」の項目 → 対応カラム NOT NULL → API required が一致するか。
- 「任意」の項目 → nullable → optional が一致するか。
- 画面 md のバリデーション（文字数・必須）と API YAML の制約（maxLength・required）が一致するか。
- enum 値・minimum/maximum が要件・DB・API で一致するか。

---

## 7. 修正後の再突合（fix-design 用）

修正で operationId・テーブルカラム・シーケンスを追加/変更した場合、次を即座に確認する（次 iteration の review を待たない）:

- 追加/変更した operationId が `api/*.yaml` と `認可設計.md` の **両方** に存在するか。
- 追加したテーブルカラムが API スキーマと整合するか。
- 追加したシーケンスで参照する operationId が `api/*.yaml` に定義済みか。

---

## 8. BE↔DB 整合表（db-schema-completeness / db-contract）

`review-design` の手順 4.2 で `check-db-design-consistency.sh` を実行する。あわせて、全テーブル × 全カラムを縦軸に次の表を作る（FE↔BE のデータ需給表＝§3 と対称の BE↔DB 版）。

| テーブル.カラム | DB型/桁 | NULL | PK/UNIQUE/FK | 供給/受領 operationId.field | API型/maxLength/required/enum | 判定 |
|---|---|---|---|---|---|---|

- PK/型/桁/nullable/UNIQUE/FK型/インデックス方針/version要否 のいずれか未記載 → `db-schema-completeness`（BLOCK）。不要な項目は「なし」と明記する。
- DB型/桁 と API型/maxLength が不一致 → `db-contract`（BLOCK）。
- 必須/任意（NOT NULL ↔ required）不一致 → `db-contract`（BLOCK）。
- enum 値集合が `コード値定義.md`／`_common.yaml`／tables で不一致 → `db-contract`（BLOCK）。
- 一意制約のカラム組み合わせが業務の重複単位と一致するか → `concurrency`（§5）と突合。

Entity↔migration との三者整合は製造フェーズ（`check-migration-consistency.sh` / `design_mismatch`）が担い、本表は設計成果物だけで閉じる範囲を対象とする。作成した表は `docs/design/レビュー結果.md` に根拠として含める。
