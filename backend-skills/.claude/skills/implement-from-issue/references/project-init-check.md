# プロジェクト初期化チェック詳細（ビルド定義・品質 config・新規依存の確定表照合）

implement-from-issue（backend-skills 系統）本文から 2026-07-02 に PP-5 分解で外出し。本文の該当手順から参照される。

### 2.5. プロジェクト初期化チェック（ビルド定義の存在確認・全リポ共通）

実装対象リポジトリの**ビルド定義**が存在するか確認する（Java 系＝`pom.xml` / Node 系＝`package.json`。リポジトリ種別に応じてどちらかが存在すべき）。

```bash
ls pom.xml package.json 2>/dev/null || echo "MISSING"
```

そのリポジトリに該当するビルド定義（Java は `pom.xml`、Node は `package.json`）と静的解析設定（`config/` 等）が**存在しない**場合は **実装を開始せず中断し、事前配置を依頼する**:

> ビルド定義（`pom.xml` または `package.json`）／静的解析設定が見つかりません。設定一式の事前配置が必要です。対象リポジトリのルートに配置してから再実行してください。

存在する場合はそのまま手順2.6へ進む（`mvn verify` / `npm run ...` 等が通る前提とし、設定の即興生成はしない）。

#### 2.5.1. 品質 config 群の存在・参照照合（RC-07 / D-21・rules 改善）

品質設定（checkstyle / pmd / spotbugs / jacoco / vitest config 等）が **スタック確定表 #12 に記載されたファイルとして実在し、ビルド定義から参照されているか**を照合する。即興生成はせず、欠落があれば中断して事前配置を依頼する。

```bash
grep -E 'checkstyle|pmd|spotbugs|jacoco' pom.xml 2>/dev/null
ls config/checkstyle config/pmd config/spotbugs 2>/dev/null || echo "MISSING-CONFIG"
```

- 確定表 #12 記載の config がファイルとして存在しない、またはビルド定義から参照されていない場合は **中断**し、事前配置を依頼する。

#### 2.5.2. 新規依存の確定表照合と実在性確認（RC-06 / D-14・幻覚パッケージ防止・rules 改善）

実装で**新規ライブラリ依存**を追加する場合は、追加前に次を満たすこと。満たさなければ中断する。

- スタック確定表（`backend-00-stack.md`）に**記載された依存・バージョン**であること（未記載の依存は人間に確定を求める）。
- 指定バージョンが**実在する安定版**であること（Maven Central で実在確認。lockfile 整合）。
- 実在しない／確定表に無いバージョンを「それらしく」追加しない（幻覚パッケージの混入防止）。

