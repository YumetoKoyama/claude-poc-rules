## sequences/[シーケンス名].md

> 主要シーケンスごとに 1 ファイル作成する。ファイル名は業務用語の日本語名（例: `応募確定.md`、`評価完了.md`）。シーケンスごとに SEQ-XXX を採番し、対応する画面 ID（SCR-XXX）・ユースケース（UC-XXX）・業務フロー（ACT-XXX）・API（operationId）・受け入れ条件（AC-XXX）を **必ず** 本文中で引用する。フロントエンド ↔ API ↔ DB（必要に応じて外部システム）の交互動作を Mermaid `sequenceDiagram` で描く。

ファイル名規約: 業務用語の日本語名（例: `応募確定.md`、`評価完了.md`）。SEQ-ID は本文側で `# シーケンス: SEQ-001 応募確定` のように冒頭で明示する。

```markdown
# シーケンス: SEQ-001 応募確定

## ID 凡例

| ID 体系 | 形式例 | 用途 |
|---------|-------|------|
| `SEQ-XXX` | `SEQ-001` | シーケンス ID（3 桁ゼロ埋め） |

## メタデータ

- シーケンス ID: SEQ-001
- シーケンス名: 応募確定
- 対応画面: SCR-003 案件詳細, SCR-004 応募確認
- 対応ユースケース: UC-003 応募する
- 対応業務フロー: ACT-001 案件成約フロー（ステップ 3〜5）
- 対応 API（operationId）: `createApplication`, `confirmApplication`
- 関連受け入れ条件: AC-001, AC-101（内容は下記「受け入れ条件」セクションに展開）
- 関連業務ルール: BR-005

## 受け入れ条件（Given/When/Then）

> `docs/requirements/functional/[機能名].md` の AC-XXX を **Given/When/Then 形式のまま**引き継ぐ。AC-ID の列挙のみ記載することは禁止。正常系・異常系・境界値を含める。

| AC-ID | 区分 | Given（前提状態） | When（API 呼び出し） | Then（期待結果） | 関連 BR |
|-------|------|-----------------|-------------------|----------------|--------|
| AC-001 | 正常系 | 案件が応募受付中・ユーザー認証済み | createApplication（POST /applications） | 201 Created、応募レコード登録 | BR-005 |
| AC-101 | 異常系 | 案件が受付終了済み | createApplication | 409 Conflict | — |
| AC-102 | 異常系 | バリデーション違反（必須項目欠落） | createApplication | 400 Bad Request | BR-005 |

## 前提条件

- ユーザーは認証済み（JWT 有効）
- 対象案件が応募受付中ステータス

## シーケンス図

\`\`\`mermaid
sequenceDiagram
    autonumber
    actor User as 利用者
    participant UI as フロントエンド (React)
    participant API as バックエンド (Spring Boot)
    participant DB as データベース

    User->>UI: 応募ボタン押下
    UI->>UI: 入力バリデーション
    UI->>API: POST /applications (createApplication)
    API->>API: 認可チェック
    API->>DB: SELECT 案件状態
    DB-->>API: 案件状態
    alt 受付中
        API->>DB: INSERT applications
        DB-->>API: OK
        API-->>UI: 201 Created
        UI-->>User: 応募確定メッセージ表示
    else 受付終了
        API-->>UI: 409 Conflict (AC-101)
        UI-->>User: エラーメッセージ表示
    end
\`\`\`

## ステップ詳細

| # | ステップ | 担当 | 入力 | 出力 | 関連 AC / BR |
|---|--------|------|------|------|--------------|
| 1 | 応募ボタン押下 | 利用者 |  | UI イベント | - |
| 2 | バリデーション | UI | 入力値 | OK / NG | BR-005 |
| 3 | POST /applications | UI → API | 応募 DTO | 201 / 4xx | AC-001 |
| 4 | 認可チェック | API | JWT | 通過 / 拒否 | - |
| 5 | 案件状態取得 | API → DB | 案件 ID | 状態 | - |
| 6 | 応募登録 | API → DB | 応募レコード | OK | AC-001 |

## 例外・代替フロー

> 正常フローに加え、**主要な例外フローを必ず記述する**。少なくとも該当するものについて、上記シーケンス図の `alt` / `opt` フラグメントとして図示し、ここに対応 AC・HTTP ステータス・ErrorResponse コードを記す。HTTP ステータスとエラーコードは `api/_common.yaml` の `ErrorResponse`（界面契約の正典）と一字一句一致させる。

| 例外区分 | 発生条件 | HTTP / エラーコード | 対応 AC / BR | 振る舞い |
|---------|---------|------------------|------------|---------|
| 認可失敗 | ロール不足 | 403 Forbidden | - | アクセス拒否表示 |
| テナント越境 | 他テナントのリソース | 404 Not Found | - | 存在隠蔽（404 に統一） |
| バリデーションエラー | 入力不正 | 400 Bad Request | AC-102 | エラーメッセージ表示 |
| 状態競合 / 受付終了 | 案件が受付終了 | 409 Conflict | AC-101 | エラーメッセージ表示 |
| 楽観ロック競合 | version 不一致（同時編集） | 409 Conflict | - | 再取得・リトライ案内 |
| 二重操作 | 既に同案件に応募済み | 409 Conflict | BR-005 | 二重応募を拒否 |
| 外部タイムアウト | 外部システム無応答 | 504 Gateway Timeout | - | 再試行案内 / 非同期化 |
```
