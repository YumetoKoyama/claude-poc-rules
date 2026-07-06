---
name: humanize-design
description: AI生成設計書（docs/design/）を人間の認知設計に最適化したレビュー用設計書として新規生成する。AIが参照する既存設計書は書き換えず、人間がレビュー・確認する用の設計書を docs/design/review/ に出力する。内容の乖離ゼロを必須とする。
context: fork
argument-hint: [対象の設計書パス（省略時は docs/design/ 全件）]
allowed-tools: Bash, Read, Write, Glob, Grep
---

# 人間向けレビュー設計書の生成（humanize-design）

> **パス解決（マルチリポジトリ対応）**: `docs/design/` / `docs/requirements/` は docs リポジトリ（claude-poc-docs）ルート相対。親アンブレラから実行する場合は `claude-poc-docs/` を前置する。

入力: $ARGUMENTS（省略時は `docs/design/` 全件）

## 役割

AI が参照する既存設計書（`docs/design/`）の内容を **一切変更せず**、人間がレビュー・承認しやすい形に変換した設計書を `docs/design/review/` に新規生成する。

- 既存設計書（`docs/design/`）は読み取り専用。**書き込み禁止**
- `docs/design/review/` は新規生成専用。同名ファイルは上書きして最新状態に保つ
- 変換は「**表現形式の変更のみ**」。情報の追加・削除・解釈変更は禁止

## 人間向け認知設計の9原則

`mdサンプル/人とLLMの作成する設計書の違い.md` の9観点をすべて適用する。

| 観点 | AI 設計書の傾向 | 変換方針 |
|------|--------------|---------|
| 情報の塊 | 意味が続く長文 | 入力/処理/出力の単位に分割。1セクション1メッセージ |
| 強弱 | 全項目が同重要度 | 重要事項・制約は `> **⚠️**` コールアウト。決定事項は太字 |
| 階層 | 見出しのみで浅い | 全体→業務→機能→画面→項目の4段階。H1〜H4 まで |
| 飛び読み | 背景→詳細→結論の順 | **結論ファースト**。各章は要約(3-5行)→詳細の順 |
| 比較 | A は…B は…と文章で並列 | 比較は必ず表。文章の並列はNG |
| 全体像 | 詳細から書き始める | アーキテクチャ図・画面遷移図・ER図を最初に配置 |
| 余白 | 連続する箇条書き | セクション間に `---` 区切りを置く |
| 粒度 | 業務とSQL が同列 | 業務→機能→画面→項目で階層レベルを揃える |
| 文章比率 | ほぼ文章 | 図40%/表30%/箇条書き10%/文章20% を目安にする |

---

## 手順

### Step 1: 入力の読み込み

以下を Read する（存在しないものはスキップ）:

- `docs/design/概要.md` / `docs/design/方式設計.md`
- `docs/design/screens/画面遷移.md` と `docs/design/screens/*.md`
- `docs/design/sequences/*.md`
- `docs/design/api/_common.yaml` と `docs/design/api/*.yaml`
- `docs/design/DB定義.md` と `docs/design/tables/*.md`
- `docs/design/セキュリティ設計.md` / `docs/design/IF定義.md`
- `docs/requirements/functional/*.md`（ユーザーストーリー参照用）

### Step 2: ID インベントリの作成

元設計書から以下の ID を全件抽出し、**乖離チェック用リスト**を作る。

| 種別 | 抽出元 | ID 例 |
|------|-------|-------|
| 画面 ID | screens/*.md | SCR-001 |
| ユースケース ID | 概要.md / sequences/*.md | UC-001 |
| シーケンス ID | sequences/*.md | SEQ-001 |
| 受け入れ条件 ID | sequences/*.md / screens/*.md | AC-001 |
| API operationId | api/*.yaml | listItems |
| テーブル名 | tables/*.md | users |

### Step 3: レビュー用設計書の生成

[human-review-templates.md](human-review-templates.md) を各ファイルの出力構造の基準とし、以下のファイルを生成する。

#### 出力ファイル構成

```
docs/design/review/
├── README.md                     # 読み方 + 元設計書との対応表 + 変更ルール
├── 00-設計サマリー.md             # 全体像（アーキテクチャ図・主要フロー・スコープ）
├── 01-画面一覧と遷移.md            # 全画面を表 + 遷移図で一覧
├── screens/                      # 画面別詳細仕様（1画面1ファイル）
│   └── SCR-XXX-[画面名].md
├── 02-API仕様サマリー.md           # API を表で整理（詳細は元 YAML を参照）
└── 03-データモデルサマリー.md       # 全体 ER 図 + テーブル一覧表
```

各ファイルの生成指針は以下のテンプレートファイルを参照すること。
- README.md / 00-設計サマリー.md / 01-画面一覧と遷移.md → [human-review-templates.md](human-review-templates.md)
- screens/SCR-XXX / 02-API仕様サマリー.md / 03-データモデルサマリー.md → [human-review-templates-screens.md](human-review-templates-screens.md)

### Step 4: 乖離チェック（必須・完了前に必ず実行）

Step 2 の ID インベントリと生成ファイルを照合する。

```bash
# 生成ファイル内での ID 参照確認
grep -rh "SCR-[0-9]" docs/design/review/
grep -rh "AC-[0-9]" docs/design/review/
```

元設計書にある ID が `docs/design/review/` のどこにも登場しない場合は **その ID のセクションを追記してから完了する**（完了を先送りしない）。

元設計書への変更がないことを確認する:

```bash
git diff docs/design/ --name-only | grep -v "^docs/design/review/"
```

上記コマンドで `docs/design/review/` 以外のファイルが表示された場合は **即停止**してユーザーに報告する。

---

## 完了条件

- [ ] `docs/design/review/README.md` が生成されており、元設計書との対応表を含む
- [ ] `docs/design/review/00-設計サマリー.md` にアーキテクチャ図または全体フロー図が含まれる
- [ ] 画面一覧の全 SCR-XXX に対応する `docs/design/review/screens/` ファイルが存在する
- [ ] 元設計書の全 API operationId が `02-API仕様サマリー.md` の表に登場する
- [ ] 元設計書の全テーブル名が `03-データモデルサマリー.md` の表に登場する
- [ ] `git diff docs/design/ --name-only` の結果が `review/` 配下のみ
- [ ] 各出力ファイルが 200 行以内（超える場合は画面単位に分割）

## 注意事項

- 元設計書が TBD / 空欄の箇所はそのまま「未定」として引き継ぐ（補完しない）
- レビュー用設計書を見た人が「修正が必要」と判断した場合、変更先は必ず `docs/design/` の元ファイル。その旨を `README.md` に明記する
- 認知設計を適用しても、元設計書に書かれていない内容（例: 不足している受け入れ条件）は発見・指摘のみ行い、レビュー用設計書には含めない
