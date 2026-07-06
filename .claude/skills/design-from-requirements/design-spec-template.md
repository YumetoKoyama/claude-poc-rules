# 設計書テンプレート

設計書は以下のディレクトリ構成で出力する。各セクションのテンプレートを参照してファイルを作成すること。

```
docs/design/
├── 概要.md
├── screens/
│   ├── 画面遷移.md          # 画面遷移図（Mermaid）
│   ├── 共通レイアウト.md      # 全画面共通のアプリシェル設計
│   └── [画面名].md                    # 画面ごとに 1 ファイル（例: SCR-001-ログイン.md）
├── sequences/
│   └── [シーケンス名].md              # 主要シーケンスごとに 1 ファイル（SEQ-XXX 採番、Mermaid sequenceDiagram。例: 応募確定.md）
├── api/
│   ├── _common.yaml                  # API 共通スキーマ（OpenAPI 3.1 components）
│   └── [リソース名].yaml              # リソースごとに 1 ファイル（例: jobs.yaml, users.yaml, applications.yaml）
├── IF定義.md
├── DB定義.md                  # DB 全体方針（全体 ER 図含む）
├── tables/
│   └── [テーブル名].md                # テーブルごとに 1 ファイル（部分 ER 図含む）
├── フロントエンド共通設計.md    # FE 横断設計（共通コンポーネント・APIクライアント・エラー表示・ルーティング・状態管理）
├── テスト戦略.md
├── シナリオ戦略.md
└── quickstart.md              # エンドツーエンド動作確認ガイド（SC-XXX / AC-XXX と対応づけ）
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
| API 操作 ID 等の新規略号 | （設計者が導入） | API メソッド / イベント名 等 | 当該ファイル冒頭 |
| DB テーブル略号（任意） | （導入する場合） | ER 図ノードの省略表記 | `DB定義.md` 冒頭 |

略号を導入したのに凡例が無い状態は `/review-design` で検出される。

---

## テンプレートファイル参照

各ドキュメントのテンプレートは以下の参照ファイルを使うこと。

| テンプレート対象ドキュメント | 参照ファイル |
|--------------------------|-----------|
| 概要.md / screens/画面遷移.md / screens/共通レイアウト.md / screens/[画面名].md / フロントエンド共通設計.md | [references/overview-screens.md](references/overview-screens.md) |
| sequences/[シーケンス名].md | [references/sequences.md](references/sequences.md) |
| api/_common.yaml | [references/api-common.md](references/api-common.md) |
| api/[リソース名].yaml | [references/api-resource.md](references/api-resource.md) |
| IF定義.md / DB定義.md / tables/[テーブル名].md | [references/db.md](references/db.md) |
| テスト戦略.md / シナリオ戦略.md | [references/test-strategy.md](references/test-strategy.md) |
