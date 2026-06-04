# ③ AI 利用シーン整理

最終更新: 2026-05-27

本文書は、開発の各工程で **どの AI ツールを・どの責任度合いで・どう使い分けるか** を整理します。「AI に任せて良いか」を判断する際の共通の物差しとして使います。

---

## 1. 利用パターンの分類

AI の使い方を **関与度** で 4 段階に分ける。プロンプト・skill・人手レビューの設計はこの分類に応じて変える。

| パターン | 関与度 | AI の役割 | 人の役割 | 例 |
|----------|--------|-----------|----------|-----|
| **P1: 自動化（Autonomous）** | 高 | 生成・修正までを skill が完結 | 採択ゲートでレビュー・承認 | 要件定義書の初稿生成、UT・静的解析の修正適用 |
| **P2: 補助（Assisted）** | 中 | ドラフト生成・候補提示 | 取捨選択・編集・最終決定 | 設計レビューの所見、Issue ドラフト、コードの改善提案 |
| **P3: 参考（Reference）** | 低 | 質問応答・情報整理 | すべての判断 | 技術調査、API 仕様の確認、用語の整理 |
| **P4: 不使用（Manual）** | なし | 使わない | 全工程を人手で実施 | 事業判断、顧客との合意形成、本番リリース判断 |

判断に迷ったら **より低い関与度** に倒す。P1 にするときは必ず BLOCK ゼロのレビューゲートを通す。

---

## 2. ツール × 工程マッピング

### 2.1 利用する AI ツール（claude-poc 現状）

| ツール | 主用途 | 出力先 | 補足 |
|--------|--------|--------|------|
| **Claude Code** | skill 連鎖による要件・設計・実装の自動化 | リポジトリ内ファイル / Issue / PR | 本プロジェクトの基幹。Pattern 4 ループの主役 |
| **Cowork** | 非開発者向け文書化・調査・対話支援 | docs/process/, 各種レポート | このシリーズの作成にも利用 |
| **Claude Design** (`claude.ai/design`) | UI 試作・画面生成 | `docs/design/ui-design/handoff/` に **Export 構造そのまま** 人手で配置 | 設計採択後に `/ui-brief-from-design` を経由（共通 → 画面別の順で投入） |
| **Claude in Chrome** | 動的ページの調査・SaaS UI 操作の補助 | 調査結果のみ | 機密情報のあるサイトは禁止 |
| **GitHub MCP** | Issue 起票・PR 操作 | Issue / PR | `GITHUB_PERSONAL_ACCESS_TOKEN` 必須 |
| **Playwright MCP** | E2E 実行 | テスト結果 | `.mcp.json` で接続 |

### 2.2 工程 × ツール × 関与度

| 工程 | 主ツール | 関与度 | 補助 |
|------|----------|--------|------|
| 要件素材の整理 | Claude Code (`/requirements-from-input`) | P1 | Cowork（事前の素材ヒアリング） |
| 要件レビュー | Claude Code (`/review-requirements`) | P1 | 人手採択ゲート |
| 要件修正 | Claude Code (`/fix-requirements`) | P1 | — |
| 要件採択 | 人 | **P4** | — |
| 設計生成 | Claude Code (`/design-from-requirements`) | P1 | — |
| 設計レビュー / 修正 | Claude Code (`/review-design`, `/fix-design`) | P1 | — |
| 設計採択 | 人 | **P4** | — |
| UI ブリーフ作成 | Claude Code (`/ui-brief-from-design`) | P1 | — |
| UI 試作 | Claude Design | P2 | 人がプロンプトで対話調整 |
| Handoff bundle 配置 | 人 | **P4** | — |
| Issue 起票 | Claude Code (`/create-issues-from-design`) | P1 | GitHub MCP |
| 実装（Issue 単位） | Claude Code (`/implement-loop`) | P1 | — |
| 品質ゲート（UT / 静的解析 / E2E） | Claude Code（Pattern 2 並列） | P1 | Playwright MCP |
| 実装レビュー / 修正 | Claude Code (`/review-implementation`, `/fix-implementation`) | P1 | — |
| PR レビュー / マージ | 人 | **P4** | GitHub MCP（補助） |
| 本番リリース判断 | 人 | **P4** | — |
| 技術調査 | Claude Code / Cowork / Claude in Chrome | P3 | — |
| 障害調査の起点 | Claude Code（`failure-investigator`） | P2 | 仮説提示まで。判断は人 |

> P4（人手必須）が **「ループの境目」** に集中していることに注目。AI で速く回す区間と、判断を確定させる区間が交互に並ぶ構造。

---

## 3. シーン別ガイド

### 3.1 要件定義をはじめる

- 入力: 顧客ヒアリングメモ、既存システム資料、市場調査メモなど雑多な素材。
- AI に任せること: 構造化、抜け漏れ検出、open-questions の抽出（**P1**）。
- 人がやること: 素材の真偽確認、事業優先順位、open-questions の解決方針決定（**P4**）。
- ツール: `/requirements-loop <素材>`。出力は `docs/requirements/`。

### 3.2 設計を進める

- 入力: 採択済みの `docs/requirements/`。
- AI に任せること: 画面 / API / DB / IF / テスト方針のドラフト（**P1**）。
- 人がやること: 標準スタック準拠の判断、性能・運用要件のチューニング（**P4**）。
- ツール: `/design-loop`。

### 3.3 UI を Claude Design で試作する

- 前提: 設計採択が完了している。
- 流れ: `/ui-brief-from-design` で `_共通.md` + 画面別 md を生成 → Claude Design に **共通ブリーフを最初に投入** してデザインシステムを確立 → 続いて画面別ブリーフを一括（または役割/カテゴリ単位）で添付 → 対話で調整 → Export → `docs/design/ui-design/handoff/` に **Export 構造そのまま**（`README.md` / `prototype/` / `tokens/`）で人手配置。
- prototype/ 配下は画面単位で分割しない。共通プリミティブ・シェル・トークンは横断的共有資産なので画面 ID への切り分けは不可能。画面 ID と prototype 関数の対応は `ui-design/handoff/README.md` のマッピング表が Source of Truth。
- 設計書本体は AI に書き換えさせない（**P4 で配置を制御**）。

### 3.4 Issue を起票する

- 入力: 採択済み設計 + 任意で UI handoff。
- AI に任せること: 画面・API リソース・IF・テーブル単位への分解、テンプレ適用、ラベル付与（**P1**）。
- 人がやること: 優先順・スプリント割当・依存関係の調整（**P4**）。
- ツール: `/create-issues-from-design`、GitHub MCP。

### 3.5 実装する

- 入力: 1 つの Issue 番号。
- AI に任せること: 実装、UT 作成、静的解析対応、E2E、PR 作成までの一連（**P1**）。
- 人がやること: PR レビューと本番マージ判断（**P4**）。
- ツール: `/implement-loop <ISSUE-NUMBER>`。

### 3.6 障害を調査する

- AI に任せること: ログ収集、再現条件の仮説化、関連コード特定（**P2**）。
- 人がやること: 原因の確定、修正方針の決定、ホットフィックスの可否判断（**P4**）。
- ツール: Claude Code + failure-investigator skill（実装フェーズ内のみ）。

### 3.7 技術調査する

- AI に任せること: 公式ドキュメント要約、選択肢比較、サンプルコード提示（**P3**）。
- 人がやること: 採用判断、PoC 計画。
- ツール: Cowork、Claude in Chrome、WebSearch。

---

## 4. AI 可否の判断フロー

新しい作業に取りかかるとき、次の質問で関与度を決める。

```
Q1. その作業の出力は、ファイル / 構造化データとして表現できるか？
  → No → P3 / P4（対話・判断系）
  → Yes → Q2

Q2. 出力の正しさを、自動レビュー（BLOCK/SUGGEST/NIT）で機械的に判定できるか？
  → No → P2（人が最終決定）
  → Yes → Q3

Q3. その作業に「事業判断」「顧客合意」「リリース判断」が含まれるか？
  → Yes → P4（人手）
  → No → Q4

Q4. 失敗時の影響が大きく、不可逆か？（本番DB変更、外部送信など）
  → Yes → P2（AI はドラフトのみ、適用は人）
  → No → P1（自動化候補）
```

判断結果は **skill の frontmatter コメント** か `docs/process/` の追記で残し、次回以降の判断を再利用する。

---

## 5. 機密・コンプライアンス

### 5.1 取り扱い禁止データ

AI に渡してはいけないものを明示する。

- 個人情報（氏名・住所・電話番号・メールアドレス・マイナンバー等）の **実データ**
- 認証情報（API キー、JWT 秘密鍵、DB パスワード）
- 顧客固有の **本番データ** ／ 守秘契約下のドキュメント

これらが必要なシーンでは、**ダミーデータに置換** してから AI に渡す。実データを扱う作業は **P4（人手）**。

### 5.2 Chrome / 外部 SaaS 連携

- Claude in Chrome は **ログイン状態のセッションを利用** するため、業務 SaaS の操作には注意。閲覧のみに留め、書き込みは原則人手。
- WebFetch / WebSearch の結果に機密情報が含まれた場合、リポジトリへの保存は禁止。

### 5.3 ログと監査

- `.skills-state/` は gitignore 対象。ローカルデバッグ用で、外部共有不可。
- Issue / PR / コミットメッセージには機密値を貼らない。

---

## 6. ノウハウ集

### N-01: 「P1 にする条件は『自動判定可能』」

レビューが機械化できないものを P1 にすると、ESCALATE が量産される。逆に判定可能なものを P2 にすると、人手レビューが律速になる。

### N-02: 「P4 はループの『境目』に置く」

採択ゲートを P4 にすると、AI の高速ループと人の合意形成が共存する。境目以外を P4 にすると、フローが詰まる。

### N-03: 「Claude Design は設計書を書き換えない」

UI 試作は補助。設計書本体は `docs/design/` の AI 生成 + 採択フローで管理し、Claude Design は handoff bundle だけを残す。混ぜると整合性が壊れる。

### N-04: 「Cowork は調査・ドキュメント、Claude Code は変更」

役割を分けると、コミット履歴とリポジトリの清潔さが保たれる。本シリーズも Cowork で書いたが、`CLAUDE.md` のような実装規約は Claude Code 経由で変える。

### N-05: 「Chrome は『読む』のみ、書き込みは人手」

業務 SaaS の自動操作はリスクが高い。読み取りだけにし、書き込みは人がレビューしてから実施する。

### N-06: 「P3 の結果は『出典付き』で残す」

技術調査の結論だけメモすると、再現性がなくなる。引用元 URL・読んだ日付・要点 3 行をセットで残す。

---

## 7. claude-poc 固有の運用

- 採択ゲート（要件・設計）と PR マージ判断は **人手必須**（CLAUDE.md「開発ルール」と整合）。
- skill オーケストレーションの停止条件（BLOCK 0 / iteration 上限 3）はそのまま適用。
- UI 設計を Claude Design で行う場合のみ、5 番目の工程として `ui-brief-from-design` を挟む。
