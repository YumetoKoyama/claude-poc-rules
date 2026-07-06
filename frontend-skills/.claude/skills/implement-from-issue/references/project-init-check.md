# プロジェクト初期化チェック詳細（ビルド定義・品質 config・新規依存の確定表照合）

implement-from-issue（frontend-skills 系統）本文から 2026-07-02 に PP-5 分解で外出し。本文の該当手順から参照される。

### 2.5. プロジェクト初期化チェック（ビルド定義の存在確認）

実装対象リポジトリの**ビルド定義**（`package.json`）が存在するか確認する。

```bash
ls package.json 2>/dev/null || echo "MISSING"
```

`package.json` と静的解析・テスト設定（`vitest.config.*` / `vite.config.*` / `eslint.config.*` 等）が**存在しない**場合は **実装を開始せず中断し、事前配置を依頼する**:

> ビルド定義（`package.json`）／静的解析・テスト設定が見つかりません。設定一式の事前配置が必要です。対象リポジトリのルートに配置してから再実行してください。

存在する場合はそのまま手順3へ進む（`npm run ...` 等が通る前提とし、設定の即興生成はしない）。

#### 2.5.1. 品質 config 群の存在・参照照合（RC-07 / D-21）

品質設定（vitest / eslint / prettier / tsconfig 等）が **スタック確定表 `frontend-00-stack.md` #12 に記載されたファイルとして実在し、`package.json` のスクリプトから参照されているか**を照合する。即興生成はせず、欠落があれば中断して事前配置を依頼する。

```bash
ls vitest.config.* vite.config.* eslint.config.* .eslintrc* .prettierrc* tsconfig.json 2>/dev/null || echo "MISSING-CONFIG"
grep -E 'vitest|eslint|prettier|tsc' package.json 2>/dev/null
```

- 確定表 #12 記載の config がファイルとして存在しない、または `package.json` から参照されていない場合は **中断**し、「品質 config（vitest/eslint/prettier/tsconfig）が確定表 #12 の固定 config として存在・参照されていません。事前配置してください」と報告する。

#### 2.5.2. 新規依存の確定表照合と実在性確認（RC-06 / D-14）

実装で**新規ライブラリ依存**を追加する場合は、追加前に次を満たすこと。満たさなければ中断する。

- スタック確定表（`frontend-00-stack.md`）に**記載された依存・バージョン**であること（未記載の依存は人間に確定を求める）。
- 指定バージョンが**実在する安定版**であること（npm registry で実在確認。`package-lock.json` 整合）。
- 実在しない／確定表に無いバージョンを「それらしく」追加しない（幻覚パッケージの混入防止）。

