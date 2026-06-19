# 設計書テンプレート

設計書は以下のディレクトリ構成で出力する。各セクションのテンプレートを参照してファイルを作成すること。

```
docs/design/
├── 概要.md
├── screens/
│   ├── 画面遷移.md          # 画面遷移図（Mermaid）+ 画面一覧
│   └── [画面名].md                    # 画面仕様書（画面ごとに 1 ファイル、表紙〜未解決事項を内包。例: SCR-001-ログイン.md）
├── sequences/
│   └── [シーケンス名].md              # 主要シーケンスごとに 1 ファイル（SEQ-XXX 採番、Mermaid sequenceDiagram。例: 応募確定.md）
├── api/
│   ├── _common.yaml                  # API 共通スキーマ（OpenAPI 3.1 components）
│   └── [リソース名].yaml              # リソースごとに 1 ファイル（例: jobs.yaml, users.yaml, applications.yaml）
├── IF定義.md
├── DB定義.md                  # DB 全体方針（全体 ER 図含む）
├── tables/
│   └── [テーブル名].md                # テーブルごとに 1 ファイル（部分 ER 図含む）
├── テスト戦略.md
└── シナリオ戦略.md
```

固定ファイル名（概要.md, IF定義.md 等）は日本語名で統一する。可変部の命名は次のとおり: 画面名（`screens/[画面名].md`）は `SCR-XXX-画面名.md` 形式の日本語名（例: `SCR-001-ログイン.md`）、シーケンス名（`sequences/[シーケンス名].md`）は業務用語の日本語名（例: `応募確定.md`、`評価完了.md`）、API（`api/[リソース名].yaml`）はリソース名の kebab-case 英語（例: `jobs.yaml`, `users.yaml`, `applications.yaml`）、テーブル名（`tables/[テーブル名].md`）は DB 物理名と同じ snake_case 英語（例: `users.md`）とする。

### 略号・ID 採用時の凡例必須ルール

CLAUDE.md の開発ルールに従い、各ドキュメントで **ID または略号を導入する場合は、当該ドキュメントの冒頭付近に凡例（略号一覧表）を必ず出力する**。設計書フェーズで参照・引用する既知の ID 体系は以下のとおり。設計書側で新規に略号を導入する場合（例: API 操作 ID、ER の関連名コード、ステータスコード略号など）は同様に凡例を出力する。

| ID / 略号体系 | 形式例 | 用途 | 凡例の置き場所 |
|--------------|-------|------|--------------|
| `SCR-XXX` | `SCR-001` | 画面 ID（要件定義から継承） | `screens/画面遷移.md` 冒頭または `概要.md` |
| `UC-XXX` | `UC-001` | ユースケース ID（要件定義から継承） | `概要.md` または各シーケンス md |
| `ACT-XXX` | `ACT-001` | 業務アクティビティ ID（要件定義から継承） | `概要.md` または各シーケンス md |
| `SEQ-XXX` | `SEQ-001` | シーケンス ID（**設計で新規採番**、3 桁ゼロ埋め） | `sequences/[シーケンス名].md` 冒頭 |
| `AC-XXX` | `AC-001`, `AC-101` | 受け入れ条件 ID（要件定義から参照） | 各画面 md またはテスト戦略.md |
| `BR-XXX` | `BR-001` | 業務ルール ID（要件定義から参照） | `概要.md` または該当画面 md |
| `MSG-XXX` | `MSG-001` | メッセージ ID（要件 `メッセージ一覧.md` から参照） | 各画面 md「メッセージ」章 |
| `OQ-XXX` | `OQ-001` | 画面仕様書の未解決事項 ID（**設計で新規採番**、3 桁ゼロ埋め、owner 付き） | 各画面 md「未解決事項」章 |
| API 操作 ID 等の新規略号 | （設計者が導入） | API メソッド / イベント名 等 | 当該ファイル冒頭 |
| DB テーブル略号（任意） | （導入する場合） | ER 図ノードの省略表記 | `DB定義.md` 冒頭 |

略号を導入したのに凡例が無い状態は `/review-design` で検出される。

---

## 概要.md

```markdown
# 設計サマリー

## 1. スコープ要約（要件定義からの引き継ぎ）

- 参照: `docs/requirements/概要.md`

## 2. 前提条件と未解決事項

### 前提条件

### 未解決事項

| # | 事項 | 影響範囲 | 対応期限 |
|---|------|---------|---------|
|   |      |         |         |

## 3. ユースケースと主要ユーザーフロー

## 4. リスクと影響範囲

## 5. レビュー観点

## 6. 後続工程（人手レビュー・採択後に起動）

- [ ] implement-from-design
- [ ] unit-test-from-design
- [ ] e2e-from-design
```

---

## screens/画面遷移.md

```markdown
# 画面遷移図

要件定義の `docs/requirements/画面一覧.md` の画面 ID 一覧をもとに、画面遷移を Mermaid で表現する。
ノードは画面 ID（SCR-XXX）を使い、ラベルに画面名を含める。

## 全体遷移

\`\`\`mermaid
flowchart LR
    SCR001["SCR-001 ログイン"]
    SCR002["SCR-002 ダッシュボード"]
    SCR003["SCR-003 一覧"]
    SCR004["SCR-004 詳細"]

    SCR001 -->|ログイン成功| SCR002
    SCR001 -->|認証失敗| SCR001
    SCR002 -->|メニュー選択| SCR003
    SCR003 -->|行クリック| SCR004
    SCR004 -->|戻る| SCR003
\`\`\`

## 業務フローごとの遷移（任意）

業務フローが複雑な場合は、業務単位で Mermaid 図を追加する。
```

---

## screens/[画面名].md（画面仕様書 / 画面ごとに 1 ファイル）

ファイル名規約: `[SCR-ID]-[画面名].md`（例: `SCR-001-ログイン.md`、`SCR-003-案件一覧.md`）。SCR-ID は大文字、画面名は業務用語の日本語で記述する。

**1 画面 = 1 ファイル**に、以下の全章を **この順序で** 含む包括的な画面仕様書とする。該当しない章も「なし」と理由を明記して省略しない。各章は要件定義（SCR / UC / AC / BR / MSG / 権限マトリクス）と相互参照する。

| 章 | 内容 | 必須 |
|----|------|------|
| 表紙 | システム名 / 機能名 / 画面ID / 年月日 / 作成者 / 承認者 | ○ |
| 改訂履歴 | 版数 / 日付 / 変更内容 / 変更者 | ○ |
| 画面概要 | 画面ID / 画面名 / 画面種別 / 目的 / 利用者 / 対応UC / 関連API / 関連テーブル / 関連要件 | ○ |
| 画面遷移 | 前の画面 / 次の画面（遷移先 SCR-XXX） | ○ |
| 画面レイアウト | ワイヤーフレーム（ASCII 図 or 画像参照）+ ボタン定義表 | ○ |
| 表示項目 | エリア（セクション）ごとの項目定義表 | ○ |
| 機能概要 | 機能一覧 + 機能詳細 | ○ |
| イベント一覧 | UI イベント → 処理 → 呼出 API の対応 | ○ |
| 振る舞い定義 | イベントごとの Given/When/Then + 処理フロー（Mermaid）+ 処理の流れ | ○ |
| 業務ルール | 画面に紐づく業務ルール（関連 BR-XXX） | ○ |
| メッセージ | 画面で表示する MSG-XXX（種別 / 文言 / 表示条件 / 発生元） | ○ |
| 権限マトリクス | ロール × 操作（C/R/U/D・状態遷移） | ○ |
| テーブルアクセス | テーブル × C/R/U/D | △（DB アクセスがある画面のみ） |
| 未解決事項 | OQ-XXX（owner 付き、設計確定前の論点） | △ |

> **レガシー由来章は出力しない**: 本プロジェクトは React / Spring Boot のグリーンフィールド開発のため、リバースエンジニアリング由来の章（Legacy Source 表・SQL定義・DTO↔DB データマッピング・実装ノートの移行ノート）は作成しない。SQL の物理仕様は `tables/*.md`・`DB定義.md`、API スキーマは `api/*.yaml` を正典とし、画面仕様書からはそれらを参照する。

```markdown
# 画面仕様書: SCR-001 ログイン画面

## 表紙

- **システム名**: {システム名}
- **機能名**: ログイン
- **画面ID**: SCR-001
- **年月日**: YYYY-MM-DD
- **作成者**: {作成者}
- **承認者**: {承認者}

## 改訂履歴

| 版数 | 日付 | 変更内容 | 変更者 | 備考 |
| ---- | ---- | -------- | ------ | ---- |
| 1.0 | YYYY-MM-DD | 新規作成 | {作成者} | - |

## 画面概要

- **画面ID**: SCR-001
- **画面名**: ログイン
- **画面種別**: 認証 / 業務 / マスタ 等
- **目的**: {この画面が果たす業務上の目的}
- **利用者**: {ロール}
- **対応ユースケース**: UC-001
- **関連API（operationId）**: `login`, `refreshToken`
- **関連テーブル**: users, login_attempts
- **関連要件**: `docs/requirements/functional/[機能名].md`

## 画面遷移

- **前の画面**: （直接 URL アクセス / SCR-XXX）
- **次の画面**:
  - ログイン成功 → SCR-002 ダッシュボード
  - 認証失敗 → 自画面（エラーメッセージ表示）

## 画面レイアウト

\`\`\`
┌───────────────────────────────────┐
│ ログイン (SCR-001)                 │
├───────────────────────────────────┤
│ メールアドレス [____________]      │
│ パスワード     [____________]      │
│                       [ログイン]   │
└───────────────────────────────────┘
\`\`\`

- **レイアウト画像**: {UI ハンドオフがあれば prototype 参照、なければ「なし」}

**ボタン定義**:

| ボタン名 | ボタンID | 配置 | 活性/非活性 | 画面遷移 | 備考 |
| -------- | -------- | ---- | ----------- | -------- | ---- |
| ログイン | buttonLogin | フォーム下部 | 入力完了時に活性 | SCR-002 | 認証 API を呼び出す |

## 表示項目

> エリア（セクション）ごとに項目定義表を分割する。`項目ID` はフロント実装の field 名（camelCase）、`対応API項目` は API スキーマ（`api/*.yaml`）のプロパティ名、`参照テーブル` は値の主たる出所テーブル。

### 入力フォーム

| No. | 項目名 | 項目ID | 種別 | データ型 | 入出力 | 必須 | 表示形式 | 最大文字数 | バリデーション | 対応API項目 | 参照テーブル | 備考 |
| --- | ------ | ------ | ---- | -------- | ------ | ---- | -------- | ---------- | -------------- | ----------- | ------------ | ---- |
| 1 | メールアドレス | email | TextInput | String | 入力 | ○ | テキスト | 255 | 必須・メール形式 | email | users | - |
| 2 | パスワード | password | PasswordInput | String | 入力 | ○ | マスク | 128 | 必須 | password | - | 平文は保持しない |

## 機能概要

### 機能一覧

1. **ログイン認証**: 入力された資格情報を検証し、JWT を発行する
2. **入力バリデーション**: メール形式・必須チェックをクライアント側で行う

### 機能詳細

1. **ログイン認証**: `login` API を呼び出し、成功時は JWT をセキュアに保持して SCR-002 へ遷移する。失敗時は MSG-001 を表示する。

## イベント一覧

| No. | イベント | 画面遷移 | 処理 | 呼出API | チェック有無 |
| --- | -------- | -------- | ---- | ------- | ------------ |
| 1 | ログインボタン押下 | ○ | ログイン認証処理 | login | 有り |

## 振る舞い定義

### ログイン認証処理

**Scenario**:
- **Given**: 未認証ユーザーがログイン画面を開いている
- **When**: メール・パスワードを入力して「ログイン」を押下する
- **Then**: 認証成功時はダッシュボードへ遷移し、失敗時はエラーメッセージを表示する

**処理フロー**:

\`\`\`mermaid
flowchart TD
    Start([ログインボタン押下]) --> Validate[入力バリデーション]
    Validate --> VCheck{バリデーション結果}
    VCheck -->|NG| ShowErr[エラー表示]
    ShowErr --> End1([中断])
    VCheck -->|OK| Call[login API 呼出]
    Call --> Decision{認証結果}
    Decision -->|成功| Goto[JWT 保持 → SCR-002 遷移]
    Decision -->|失敗| Err2[MSG-001 表示]
\`\`\`

**処理の流れ**:
1. クライアント側で必須・メール形式バリデーションを実行する
2. `login` API を呼び出す
3. 成功時: JWT を保持し SCR-002 へ遷移する
4. 失敗時: MSG-001（認証失敗）を表示する

## 業務ルール

| No. | ルール | 条件 | 処理内容 | 関連BR |
| --- | ------ | ---- | -------- | ------ |
| 1 | ログイン試行制御 | 連続失敗時 | 一定回数失敗でアカウントロック | BR-010 |

## メッセージ

| メッセージID | 種別 | 文言 | 表示条件 | 発生元 |
| ------------ | ---- | ---- | -------- | ------ |
| MSG-001 | Error | メールアドレスまたはパスワードが正しくありません | 認証失敗 | API |
| MSG-002 | Error | {0} を入力してください | 必須項目未入力 | 画面 |

## 権限マトリクス

| ロール | 参照 | 登録 | 更新 | 削除 | 備考 |
| ------ | ---- | ---- | ---- | ---- | ---- |
| 未認証 | ✓ | - | - | - | ログインのみ可能 |

> 認可の正典は `セキュリティ設計.md` / `認可設計.md`。本表は画面単位のビューであり、矛盾する場合は認可設計を正とする。

## テーブルアクセス

| テーブル | 論理名 | C | R | U | D | 備考 |
| -------- | ------ | - | - | - | - | ---- |
| users | ユーザー | - | ✓ | - | - | 認証情報照合 |
| login_attempts | ログイン試行 | ✓ | ✓ | ✓ | - | 試行制御 |

## 未解決事項

- [ ] OQ-001: {設計確定前の論点} -- owner: {担当}
```

---

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
- 関連受け入れ条件: AC-001, AC-101
- 関連業務ルール: BR-005

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

- 例外1: 案件が受付終了 → 409 Conflict（AC-101）
- 例外2: バリデーション失敗 → 400 Bad Request（AC-102）
- 代替1: 既に同案件に応募済み → 409 Conflict（BR-005）
```

---

## api/_common.yaml

```yaml
openapi: 3.1.0
info:
  title: 共通スキーマ
  version: 0.1.0
  description: |
    全 API で共有する schema / response / parameter / security scheme を定義する。
    各エンドポイント YAML から $ref で参照する。
components:
  schemas:
    ErrorResponse:
      type: object
      required: [code, message]
      properties:
        code:
          type: string
          description: アプリケーション定義のエラーコード
        message:
          type: string
          description: ユーザー向けエラーメッセージ
        details:
          type: array
          items:
            type: object
            properties:
              field: { type: string }
              reason: { type: string }
    PageMeta:
      type: object
      properties:
        page: { type: integer, minimum: 1 }
        size: { type: integer, minimum: 1 }
        totalElements: { type: integer, minimum: 0 }
        totalPages: { type: integer, minimum: 0 }
  parameters:
    PageParam:
      name: page
      in: query
      required: false
      schema: { type: integer, minimum: 1, default: 1 }
    SizeParam:
      name: size
      in: query
      required: false
      schema: { type: integer, minimum: 1, maximum: 100, default: 20 }
  responses:
    BadRequest:
      description: バリデーションエラー
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/ErrorResponse"
    Unauthorized:
      description: 認証エラー
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/ErrorResponse"
    NotFound:
      description: リソース未存在
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/ErrorResponse"
    InternalServerError:
      description: サーバーエラー
      content:
        application/json:
          schema:
            $ref: "#/components/schemas/ErrorResponse"
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
```

---

## api/[リソース名].yaml

ファイル名規約: リソース名の kebab-case 英語（例: `items.yaml`, `users.yaml`, `applications.yaml`）。ファイル名は URL パスのリソース名と一致させ、同一リソースに属する全 HTTP メソッド・パスを 1 ファイル内の `paths:` 配下に集約する。

```yaml
openapi: 3.1.0
info:
  title: アイテム API
  version: 0.1.0
  description: |
    関連要件: docs/requirements/functional/アイテム登録.md, docs/requirements/functional/アイテム検索.md
    関連画面: SCR-003 アイテム一覧, SCR-004 アイテム登録, SCR-005 アイテム詳細
paths:
  /api/items:
    get:
      operationId: listItems
      summary: アイテム一覧を取得する
      description: |
        業務ルール: BR-009
        受け入れ条件: AC-100
      security:
        - bearerAuth: []
      parameters:
        - $ref: "./_common.yaml#/components/parameters/PageParam"
        - $ref: "./_common.yaml#/components/parameters/PageSizeParam"
      responses:
        "200":
          description: 一覧取得成功
          content:
            application/json:
              schema:
                type: object
                properties:
                  items:
                    type: array
                    items:
                      $ref: "#/components/schemas/ItemResponse"
                  total: { type: integer }
        "401":
          $ref: "./_common.yaml#/components/responses/Unauthorized"
        "500":
          $ref: "./_common.yaml#/components/responses/InternalServerError"
    post:
      operationId: createItem
      summary: アイテムを登録する
      description: |
        業務ルール: BR-010, BR-011
        受け入れ条件: AC-001, AC-101
      security:
        - bearerAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/ItemCreateRequest"
      responses:
        "201":
          description: 登録成功
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ItemResponse"
        "400":
          $ref: "./_common.yaml#/components/responses/BadRequest"
        "401":
          $ref: "./_common.yaml#/components/responses/Unauthorized"
        "500":
          $ref: "./_common.yaml#/components/responses/InternalServerError"
  /api/items/{id}:
    get:
      operationId: getItemById
      summary: アイテム詳細を取得する
      description: |
        受け入れ条件: AC-102
      security:
        - bearerAuth: []
      parameters:
        - name: id
          in: path
          required: true
          schema: { type: integer, format: int64 }
      responses:
        "200":
          description: 取得成功
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ItemResponse"
        "404":
          $ref: "./_common.yaml#/components/responses/NotFound"
    patch:
      operationId: updateItem
      summary: アイテムを更新する
      security:
        - bearerAuth: []
      parameters:
        - name: id
          in: path
          required: true
          schema: { type: integer, format: int64 }
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: "#/components/schemas/ItemUpdateRequest"
      responses:
        "200":
          description: 更新成功
          content:
            application/json:
              schema:
                $ref: "#/components/schemas/ItemResponse"
        "400":
          $ref: "./_common.yaml#/components/responses/BadRequest"
        "404":
          $ref: "./_common.yaml#/components/responses/NotFound"
    delete:
      operationId: deleteItem
      summary: アイテムを削除する
      security:
        - bearerAuth: []
      parameters:
        - name: id
          in: path
          required: true
          schema: { type: integer, format: int64 }
      responses:
        "204":
          description: 削除成功
        "404":
          $ref: "./_common.yaml#/components/responses/NotFound"
components:
  schemas:
    ItemCreateRequest:
      type: object
      required: [name, price]
      properties:
        name:
          type: string
          minLength: 1
          maxLength: 100
        price:
          type: integer
          minimum: 0
        description:
          type: string
          maxLength: 1000
    ItemUpdateRequest:
      type: object
      properties:
        name: { type: string, minLength: 1, maxLength: 100 }
        price: { type: integer, minimum: 0 }
        description: { type: string, maxLength: 1000 }
    ItemResponse:
      type: object
      properties:
        id: { type: integer, format: int64 }
        name: { type: string }
        price: { type: integer }
        description: { type: string }
        createdAt: { type: string, format: date-time }
```

### YAML 構造の指針

- **1 ファイル = 1 リソース**: 同じリソース（URL パスの第一階層、例: `/api/items` 系）に属する全 HTTP メソッド・サブパス（`/api/items/{id}` 等）を同一 YAML の `paths:` 配下に集約する。
- ファイル名は URL のリソース名と対応させる（例: `items.yaml` → `/api/items` 系、`jobs.yaml` → `/api/jobs` 系、`applications.yaml` → `/api/jobs/{jobId}/applications` も含めて応募リソース観点で `applications.yaml` に集約）。
- リソースが大きく独立性が高い場合（例: `/api/auth/*`）は別ファイルに切り出して良い（`auth.yaml`）。
- 各 `operationId` は **camelCase** で命名し、後段のコード生成と整合させる（例: `listItems`, `createItem`, `getItemById`, `updateItem`, `deleteItem`）。
- 設計上の Controller / Service / Repository の責務分担、ログ要件、業務ルールの参照などは、各 operation の `description` / `summary` フィールドに自然文で必ず含めること。
- 各 YAML の冒頭 `info.description` で、関連要件ファイル・関連画面 ID・関連業務ルール ID を明示する。

---

## IF定義.md

```markdown
# IF定義

## 外部インターフェース

| IF名 | 種別 | エンドポイント / トピック | 認証方式 | 説明 |
|-----|------|------------------------|---------|------|
|     |      |                        |         |      |

### [IF名] 詳細

- 呼び出し方向:（本システム → 外部 / 外部 → 本システム）
- プロトコル:
- リクエスト仕様:
- レスポンス仕様:
- エラー処理方針:

## 内部インターフェース

| IF名 | 呼び出し元 | 呼び出し先 | 説明 |
|-----|----------|----------|------|
|     |          |          |      |
```

---

## DB定義.md（DB 全体方針）

```markdown
# DB 設計（全体方針）

## 全体方針

- 想定 RDB:
- 文字コード / 照合順序:
- タイムゾーン方針:
- 命名規約（テーブル / カラム / インデックス / 外部キー）:

## テーブル一覧

| テーブル名 | Entity クラス名 | 説明 | 詳細ファイル |
|----------|---------------|------|------------|
| users    | User          |      | `tables/users.md` |
| items    | Item          |      | `tables/items.md` |
| orders   | Order         |      | `tables/orders.md` |

## 全体 ER 図

> Mermaid `erDiagram` を必ず使用すること。テーブルごとの詳細列定義は各 `tables/[テーブル名].md` に置く。

\`\`\`mermaid
erDiagram
    USERS ||--o{ ORDERS : "places"
    ORDERS ||--|{ ORDER_ITEMS : "contains"
    ITEMS  ||--o{ ORDER_ITEMS : "is_referenced_by"

    USERS {
      bigint id PK
      varchar email
    }
    ITEMS {
      bigint id PK
      varchar name
      int    price
    }
    ORDERS {
      bigint id PK
      bigint user_id FK
      datetime ordered_at
    }
    ORDER_ITEMS {
      bigint id PK
      bigint order_id FK
      bigint item_id FK
      int    quantity
    }
\`\`\`

## migration 方針

- ツール:（Flyway / Liquibase など）
- ファイル命名規約:
- 既存データ移行方針:

## index 方針（全体ガイドライン）

| 観点 | 方針 |
|------|------|
| 主キー | 単一サロゲートキー（bigint） |
| 外部キー | 関連先カラムへ自動採番 index |
| 検索系 |  |
```

---

## tables/[テーブル名].md

ファイル名規約: DB 物理名と同じ snake_case 英語で揃える（例: `tables/users.md`、`tables/order_items.md`）。

```markdown
# テーブル定義: users

- 説明:
- Entity クラス名: User
- 関連要件: `docs/requirements/functional/[機能名].md`

## カラム定義

| カラム名 | 型 | NOT NULL | デフォルト | 説明 |
|---------|----|---------|----------|------|
| id      | BIGINT | YES | AUTO_INCREMENT | 主キー |
| email   | VARCHAR(255) | YES |  | ログインメールアドレス（ユニーク） |
| created_at | DATETIME | YES | CURRENT_TIMESTAMP | 作成日時 |

## 制約

| 制約種別 | 対象カラム | 説明 |
|--------|---------|------|
| PRIMARY KEY | id |  |
| UNIQUE | email |  |

## インデックス

| インデックス名 | 対象カラム | 種別 | 理由 |
|------------|---------|------|------|
| idx_users_email | email | UNIQUE | ログイン検索用 |

## リレーション

| 種別 | 相手テーブル | カラム | カーディナリティ | 削除時挙動 |
|------|----------|------|-------------|----------|
| 1:N  | orders   | orders.user_id | 1 ユーザー : 多数注文 | RESTRICT |

## 部分 ER 図（このテーブル + 周辺）

> 自テーブルと、外部キー / 参照されるテーブルを含めて Mermaid で図示する。

\`\`\`mermaid
erDiagram
    USERS ||--o{ ORDERS : "places"

    USERS {
      bigint id PK
      varchar email
      datetime created_at
    }
    ORDERS {
      bigint id PK
      bigint user_id FK
      datetime ordered_at
    }
\`\`\`
```

---

## テスト戦略.md

```markdown
# 単体テスト方針

## テスト対象範囲

| レイヤー | 対象クラス | テスト方針 |
|--------|----------|-----------|
| Controller | | MockMvc を使用 |
| Service | | Mockito でモック |
| Repository | | @DataJpaTest |

## テスト種別と優先度

| 優先度 | 種別 | 内容 |
|-------|------|------|
| 高 | 業務ルール | |
| 高 | 入力検証 | |
| 中 | 分岐 | |
| 中 | 例外処理 | |

## テスト境界とモック方針

- 外部依存（DB・外部 IF）のモック方針:
- テストデータ管理方針:
- カバレッジ目標:

## 要件とテストの対応方針

- 要件定義の受け入れ条件 (AC-XXX) ごとに、少なくとも 1 つの実行可能テストを対応付ける。
- 対応表は `docs/test/単体テストマトリクス.md` で管理する。
```

---

## シナリオ戦略.md

```markdown
# E2Eシナリオ方針

## E2E カバー範囲

| 対象フロー | 優先度 | 説明 |
|----------|-------|------|
|          | 高 / 中 / 低 | |

## シナリオ一覧

| シナリオ ID | シナリオ名 | 関連画面 ID | 前提条件 | 操作概要 | 期待結果 |
|-----------|---------|-----------|--------|---------|---------|
|           |         | SCR-XXX   |        |         |         |

## カバー観点

- 正常系（ゴールデンパス）:
- 入力エラー系:
- 状態遷移:
- 永続化確認:

## 実行環境・テストデータ方針

- 実行環境:
- テストデータ準備方法:
- データクリーンアップ方針:

## シナリオ詳細は `docs/test/E2Eシナリオ.md` で管理する。
```
