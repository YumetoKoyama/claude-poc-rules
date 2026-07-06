---
name: tasks-from-design
description: 採択済み設計書（docs/design/）と要件定義書（docs/requirements/functional/）から、T001 連番・[P] 並列フラグ・[US] ユーザーストーリー紐づけを持つ構造化タスクリスト（docs/design/tasks.md）を生成する。create-issues-from-design の前段として実行する。
context: fork
argument-hint: [設計書のパス（省略時は docs/design/ 配下を全件対象）]
allowed-tools: Bash, Read, Write, Glob, Grep
---

# 設計書から構造化タスクリストを生成する（tasks-from-design）

> **パス解決（マルチリポジトリ対応）**: `docs/design/` / `docs/requirements/` は docs リポジトリ（claude-poc-docs）ルート相対のパス。
> 親アンブレラから実行している場合は `claude-poc-docs/` を前置する。

設計書入力: $ARGUMENTS（省略時は `docs/design/` 配下全件）

## 役割

採択済みの設計書と要件定義書から、実装者がそのまま着手できる粒度の構造化タスクリストを `docs/design/tasks.md` に生成する。出力フォーマットは [tasks-template.md](tasks-template.md) を使う。

## 前提条件

設計書（`docs/design/`）と要件定義書（`docs/requirements/functional/`）が人手レビューを経て docs リポジトリの `main` へマージ済みであること（**マージ＝採択**）。未マージなら中断して人手レビュー・マージを依頼する。

## 成果物

`docs/design/tasks.md` — 構造化タスクリスト

---

## 手順

### Step 1: 入力の読み込み

以下を Read する（存在しないものはスキップ）:

- `docs/requirements/functional/*.md` — ユーザーストーリーの優先度（P1/P2/P3）と AC-XXX
- `docs/requirements/画面一覧.md` / `docs/requirements/データモデル.md`
- `docs/design/概要.md` / `docs/design/screens/*.md` / `docs/design/api/*.yaml`
- `docs/design/tables/*.md` / `docs/design/IF定義.md`
- `docs/design/セキュリティ設計.md` / `docs/design/共通部品設計.md`

### Step 2: ユーザーストーリーと設計成果物のマッピング

1. `functional/*.md` からユーザーストーリーを全件抽出し、優先度（P1/P2/P3）順にソートする。
2. 各ストーリーに対応する設計成果物（画面・API リソース・テーブル・共通コンポーネント）をマッピングする。
3. 複数ストーリーにまたがる成果物（共通認証・共通 ErrorResponse 等）は **Foundation フェーズ** に分類する。
4. プロジェクト初期構築（DB マイグレーション基盤・CI 設定等）は **Setup フェーズ** に分類する。

### Step 3: tasks.md の生成

[tasks-template.md](tasks-template.md) を構造の基準として使い、以下のルールで `docs/design/tasks.md` を生成する。

**タスク形式（全タスク必須）**:
```
- [ ] T001 [P] [US1] 説明（実装対象と成果物パスを含む）
```

| フィールド | ルール |
|-----------|-------|
| `T001` | 全フェーズ通し連番（3 桁ゼロ埋め）。連番に欠番を作らない |
| `[P]` | 異なるファイルを変更する・前タスクの出力に依存しない場合のみ付ける |
| `[US1]` | ユーザーストーリーフェーズのタスクに必須。Setup / Foundation / Polish フェーズには付けない |
| 説明 | 明確なアクション + 成果物パス（例: `src/.../UserService.java を実装する`） |

**依存関係の原則**: Entity → Repository → Service → Controller の順に依存するため、Entity と Repository は `[P]`、Service と Controller は `[P]` なし。

### Step 4: 成果物の検証と出力

生成した `tasks.md` を書き出す前に確認する:

- [ ] 全タスクが `- [ ] T[連番]` 形式（連番欠番なし）
- [ ] Foundation フェーズのタスクに `[USN]` ラベルが付いていない
- [ ] ユーザーストーリーフェーズのタスクに `[USN]` ラベルが付いている
- [ ] 設計書の全画面・全 API リソース・全テーブルに対応するタスクが存在する

---

## 完了条件

- [ ] `docs/design/tasks.md` が生成されている
- [ ] 全タスクが T001 形式（連番・[P]・[USN]）で記述されている
- [ ] ユーザーストーリーマッピング表と依存関係グラフが含まれている
- [ ] 設計書のすべての画面・API リソース・テーブルに対応するタスクが存在する
- [ ] 次のステップ（`/create-issues-from-design` または `/implement-from-issue`）が明記されている
