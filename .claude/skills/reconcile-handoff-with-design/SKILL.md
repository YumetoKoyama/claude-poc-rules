---
name: reconcile-handoff-with-design
description: Claude Design の Handoff（docs/design/ui-design/handoff/）と採択済み設計書を突合し、UI 生成で混入した設計外の表示項目・状態・画面遷移・バリデーション・新規画面・DS/コード値の逸脱を検出して、重大度（BLOCK/SUGGEST/NIT）と対処区分（採用/棄却/課題化）付きの突合レポートを出力する。検出専用で設計書・handoff は書き換えない。乖離の設計反映は design-amendment 経由（人手採択）に渡す。create-issues-from-design の前段ゲート。
context: fork
allowed-tools: Bash, Read, Glob, Grep, Write
argument-hint: [handoff ディレクトリのパス（省略時は docs/design/ui-design/handoff/）]
---

# Handoff ↔ 設計書 突合（UI 生成後の整合検証）

> **位置づけ**: `ui-brief-from-design`（設計→ブリーフ）→ Claude Design での UI 生成・Handoff 格納（人手）の **後段**、`create-issues-from-design`（Issue 起票）の **前段**に置く独立工程。Claude Design は人手の対話で UI を作り込むため、採択済み設計書に無い決定（表示項目・状態・遷移・バリデーション・新規画面・DS 逸脱）がほぼ確実に混入する。本工程はその乖離を機械＋目視で洗い出し、設計書（Source of Truth）と Handoff（実物）の食い違いを「採択ゲートを迂回せずに」解消する起点を作る。
>
> **検出のみ（fix なし・ループなし）**: 本スキルは **設計書・handoff・コードを一切書き換えない**（diagnostics のみ）。出力は突合レポート md と機械可読 JSON だけ。乖離の採否・反映方法は人間が判断し、設計へ取り込む場合は `impact-analysis-from-change` → `design-amendment`（→ docs `main` への PR マージ＝採択）→ 必要なら `reopen-issues-from-amendment` の正規ルートに乗せる。Claude・skill が自ら設計書を直したり PR をマージしてはならない（採択ゲート思想と整合。`review-implementation-overall` と同じ立場）。
>
> **設計書・handoff の保護**: 設計書本体（`docs/design/screens/` 等）は採択済み正典なので触らない。Handoff（`docs/design/ui-design/handoff/`）は Export 構造そのままの人手格納物なので触らない。本工程が乖離を見つけても、直すのは「設計書側 = design-amendment」か「handoff 側 = Claude Design での再調整（人手）」のいずれかであり、本スキルはどちらも実行しない。

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は中断して人間に確認する。

入力: $ARGUMENTS（省略時は `docs/design/ui-design/handoff/`）

## 入出力

- 入力: `docs/design/ui-design/handoff/`（`README.md` の scr-id→prototype マッピング表 / `prototype/*.jsx` / `tokens/*.css`）
- 入力: 採択済み設計書（`docs/design/screens/*.md`・`screens/画面遷移.md`・`api/*.yaml`・`api/_common.yaml`・`認可設計.md` または `セキュリティ設計.md`）
- 入力: 要件（`docs/requirements/コード値定義.md`・`メッセージ一覧.md`・`ブランドガイドライン.md`）と UI ブリーフ（`docs/design/ui-design/brief/_共通.md`・画面別）
- 出力: `docs/design/ui-design/突合レポート/handoff-design-<YYYYMMDD-HHMM>.md`（人間用サマリ。乖離一覧＋対処区分＋次工程の案内）
- 出力: `.skills-state/ui-reconcile/<YYYYMMDD-HHMM>-reconcile.json`（機械可読 findings。gitignore 対象・ephemeral）
- 出力（標準出力）: 生成した突合レポートのパスを 1 行

## 前提条件

- 設計書（`docs/design/`）が採択済み（docs の `main` にマージ済み）であること。未採択なら中断し、先に `design-loop` の採択を依頼する（`git log origin/main -- docs/design/` 等で確認）。
- `docs/design/ui-design/handoff/` が **Export 構造そのまま**（`README.md` / `prototype/` / `tokens/`）で格納済みであること。未格納なら中断し、Claude Design 実行と Handoff 格納（人手）を依頼する。
- 本工程は **`create-issues-from-design` の前**に実行する。突合レポートに未解決の BLOCK 乖離が残るうちは Issue 起票へ進まない（ハードゲート。後述）。

## 手順

### 1. 入力把握とマッピング整合（フェイルファスト）

1. `docs/design/ui-design/handoff/README.md` を Read し、**scr-id → prototype 関数（`wf-screens-*.jsx :: ScrXXXName`）マッピング表**を解析して `scr_id -> { file, func, 採用案 }` の対応表を作る。
2. マッピング表の SCR-XXX 集合と、`docs/design/screens/` 配下の `SCR-XXX-*.md` の SCR-XXX 集合を突き合わせる。
   - **設計にあるが handoff に無い** → `missing_screen`（設計画面が未デザイン。SUGGEST。第 1 版スコープ外なら README に明記されているか確認）。
   - **handoff にあるが設計に無い** → `new_screen`（設計外画面。**BLOCK**。Claude Design が独自に起こした画面の疑い）。
3. 参照する prototype ファイル（`wf-screens-*.jsx` 等）が `docs/design/ui-design/handoff/prototype/` に実在するか確認する。実在しない参照は `missing_screen` として上げる。
4. 期待する入力（handoff README・prototype・設計 screens）が見つからない場合は**推測で別ディレクトリを対象にせず**、確認した絶対パスを提示して中断する。

### 2. 画面ごとの突合（prototype ⇔ 設計 md）

各 scr-id について、prototype 関数（`prototype/wf-screens-*.jsx` 内の該当 React 関数）を Read し、対応する `docs/design/screens/SCR-XXX-*.md` および `docs/design/ui-design/brief/[scr-id]-*.md` と突合する。prototype はデザイン参照用モックなので、**ビジュアルの細部ではなく「設計に無い情報・挙動が混入していないか」**を見る。

#### 観点 A: 表示項目とデータ連鎖（display_field / data_sufficiency）※最重要

- prototype が画面に**表示している主要データ項目**（テキスト・テーブル列・バッジ・ラベル等の動的値）を列挙し、設計 md の「出力・表示内容」と突き合わせる。
- 設計 md に無い表示項目を prototype が出している場合 → `display_field`（設計外表示項目）。さらにその項目について、供給元 API（operationId × レスポンスフィールド）が `docs/design/api/*.yaml` に存在し、画面 md の API 欄に取得経路があるかを辿る。
  - 供給元が辿れない（API が当該フィールドを返さない / 画面 md に取得経路が無い）→ **`data_sufficiency` 欠落 = BLOCK**（CLAUDE.md 原則 #6）。とくにログイン直後画面・共通ヘッダーの表示値が `LoginResponse` / `/me` 相当から取れない場合は BLOCK。
- 逆に、設計 md が「表示する」とした項目を prototype が落としている場合 → `display_field`（表示欠落。SUGGEST）。
- 辿った「画面項目 → operationId → レスポンスフィールド」の対応表をレポートに根拠として残す。

#### 観点 B: 状態表現（state）

- prototype が持つ状態分岐（empty / loading / error / 権限不足 / 成功・確認・楽観更新中 等）を列挙し、`_共通.md` の状態規約および画面別ブリーフの States と突き合わせる。
- 共通規約に無い・逸脱する状態を prototype が持つ → `state`（SUGGEST。規約に取り込むか棄却かを判断対象に）。
- 設計が要求する状態を prototype が欠く → `state`（SUGGEST）。

#### 観点 C: 画面遷移（screen_transition）

- prototype 上のボタン・リンクの遷移先（`onClick` で遷移する画面・モーダル）を抽出し、`docs/design/screens/画面遷移.md`（Mermaid）の遷移と突き合わせる。
- 設計に無い遷移・遷移先 → `screen_transition`（設計外遷移。SUGGEST、遷移先が `new_screen` を指す場合は BLOCK 連動）。
- 設計が定義する遷移を prototype が欠く → `screen_transition`（SUGGEST）。

#### 観点 D: バリデーション・固有コピー・メッセージ（validation / copy）

- prototype の入力フィールド制約（必須・桁・形式・エラー文言）を、設計 md「バリデーションメッセージ」と突き合わせる → 差分は `validation`（SUGGEST）。
- prototype に現れる利用者向け文言（エラー・確認・通知）を `docs/requirements/メッセージ一覧.md`（MSG-XXX）と突き合わせ、MSG に無い新規文言・文言の食い違いを `copy`（SUGGEST）として上げる。

#### 観点 E: DS / トークン / コード値の逸脱（ds_token / code_value）

- prototype のスタイルが `tokens/colors_and_type.css` の CSS 変数を介さず hex 直書き等で逸脱していないか、`_共通.md`・`ブランドガイドライン.md` の DS と矛盾していないか → `ds_token`（SUGGEST。`ブランドガイドライン.md` 不在時は「未指定」として扱い NIT）。
- prototype に現れる区分値（ステータス・種別のラベル/コード）を、要件 `コード値定義.md` ⇔ 設計 `_common.yaml` の enum と突き合わせる。値・表示名の不一致や定義に無い区分値 → **`code_value`（BLOCK）**（コード値 4 層統一の崩れ）。

### 3. 機械チェック（必須）

```bash
# data 連鎖（画面→operationId→認可→テーブル→シーケンス）の決定論検証。連鎖断絶を裏取りに使う
bash .claude/skills/_common/scripts/check-vertical-trace.sh docs/design/ || true
# レポートの切断（不完全な文・表・コードブロック）検出
bash .claude/skills/_common/scripts/check-truncation.sh docs/design/ui-design/突合レポート/
```

- `check-vertical-trace.sh` が報告する連鎖断絶のうち、観点 A で検出した設計外表示項目に関係するものは `data_sufficiency` の裏付けとしてレポートに引用する（grep 由来の機械根拠）。

### 4. 各乖離への対処区分（人間の判断材料）

検出した乖離 1 件ごとに、推奨対処区分を付す（**最終判断は人間**。本スキルは実行しない）。

| 区分 | 意味 | 後続 |
| --- | --- | --- |
| 採用（handoff 正） | UI 側の決定が妥当で、設計書を実物に合わせる | `impact-analysis-from-change` → `design-amendment` → docs PR 採択 → `reopen-issues-from-amendment`（起票済みの場合） |
| 棄却（設計優先） | 設計書が正で、handoff を設計に合わせ直す | Claude Design で当該画面を再調整（人手）→ Handoff 再 Export・再格納 → 本スキル再実行 |
| 課題化 | 即断できず判断を保留する | `docs/requirements/オープン課題.md`（または該当 Q-* 区分）へ転記 |

- 推奨はあくまで根拠付きの提案に留め、断定しない。根拠（prototype の該当関数・行、設計 md の該当節）を `message` に明示できない乖離は SUGGEST 以下にする。

### 5. JSON を Write → 検証

`.skills-state/ui-reconcile/<YYYYMMDD-HHMM>-reconcile.json` に findings を書き出し、検証する。

```bash
bash .claude/skills/_common/scripts/validate-review-json.sh .skills-state/ui-reconcile/<YYYYMMDD-HHMM>-reconcile.json
```

- スキーマは review JSON と同じ（`findings[]` に `severity`(BLOCK/SUGGEST/NIT) / `category` / `path` / `message`、加えて `disposition`(採用/棄却/課題化) / `suggested_fix` を任意で）。`phase: "ui-reconcile"`、`iteration` は常に `1`（ループなし）。
- パース失敗時は最大 3 回自己修正し、それでも通らなければ標準出力に `ERROR: invalid JSON after 3 attempts` を出して停止する。
- `message` / `suggested_fix` 等の自然言語フィールドで語句を強調する場合は ASCII の `"..."` ではなく **鉤括弧 `「...」`** を使う（JSON エスケープ漏れ防止）。

### 6. 突合レポート（人間用）を Write

`docs/design/ui-design/突合レポート/handoff-design-<YYYYMMDD-HHMM>.md` に出力する。

```markdown
# Handoff ↔ 設計書 突合レポート（<YYYY-MM-DD HH:MM>）

> Claude Design の Handoff と採択済み設計書の整合検証。検出専用（設計書・handoff は未変更）。
> 結果: 突合判定: <PASS|FAIL>（BLOCK <件> / SUGGEST <件> / NIT <件>）

## 入力確認（証跡）

| 確認項目 | 結果 |
|---|---|
| 設計書の採択（main マージ） | <確認済 / 絶対パス> |
| handoff（README / prototype / tokens） | <確認済 / 絶対パス> |
| scr-id↔prototype マッピング整合 | <OK / 不整合 N 件> |

## データ連鎖の根拠（観点 A）

| 画面 | 表示項目 | 供給 operationId | レスポンスフィールド | 連鎖 |
|---|---|---|---|---|
| SCR-XXX | <項目> | <opId / なし> | <field / なし> | <OK / 断絶=BLOCK> |

## 乖離一覧

| 重大度 | カテゴリ | 該当（scr-id / prototype 関数 ⇔ 設計 md） | 乖離内容 | 推奨対処 | 対処区分 |
|---|---|---|---|---|---|
| BLOCK | data_sufficiency | SCR-100 / Scr100DashA ⇔ screens/SCR-100-*.md | <message> | <suggested_fix> | 採用 / 棄却 / 課題化 |

## 次工程の案内

- BLOCK が 0 件になるまで `create-issues-from-design` へ進まない（ハードゲート）。
- 「採用」乖離: `impact-analysis-from-change` → `design-amendment` → docs PR 採択 →（起票済みなら）`reopen-issues-from-amendment`。
- 「棄却」乖離: Claude Design で当該画面を再調整 → Handoff 再格納 → 本スキル再実行。
- 「課題化」乖離: `docs/requirements/オープン課題.md` へ転記。
- BLOCK==0 の採択済み handoff が確定したら、`reflect-handoff-to-brand` を実行し、採択されたデザイン決定（色・タイポグラフィ・トークン等）をブランドガイドラインへ逆反映する提案を生成する（Q-BR 系オープン課題のクローズ材料。P-16）。
```

- findings は **BLOCK → SUGGEST → NIT** の順。JSON と件数・内容を一致させる。
- BLOCK 0 件で PASS の場合もセクションを必ず残す（クリーン通過を人間が確認できるように）。
- 同日に既存レポートがあれば Read し、今回実行を最上部に追記する（無関係な過去分は書き換えない）。

### 7. 標準出力に突合レポートのパスを 1 行

## create-issues-from-design とのゲート連携（ハードゲート）

- 本スキルが BLOCK を 1 件でも検出した場合、`create-issues-from-design` へ進んではならない。BLOCK が「採用」なら設計反映（design-amendment → 採択）後に再実行して 0 件を確認、「棄却」なら handoff 再調整後に再実行して 0 件を確認する。
- 人手で `create-issues-from-design` を起動する運用者向けに、最新の突合レポートで BLOCK==0 であることを起動前提として README に明記する。CI 側でゲートを効かせたい場合は、突合レポート JSON の BLOCK 件数を判定する軽量チェックを `create-issues-from-docs` workflow に追加する（CLAUDE.md RC-13: CI 到達が必要なルールはスキル本文・workflow に多重化する）。
- BLOCK==0 確定後、`create-issues-from-design` と並行/前後どちらでもよいので `reflect-handoff-to-brand` を 1 回実行し、ブランドガイドライン逆反映の提案を残す（必須ゲートではないが、UI 採択のたびに実行しないと Q-BR 系課題が塞がらない）。

## 完了条件

- scr-id↔prototype マッピングの整合（設計外画面・未デザイン画面）が検証されている。
- 全画面について prototype と設計 md の表示項目・状態・遷移・バリデーション・DS/コード値の突合が行われ、設計外の表示項目は data-sufficiency まで辿られている。
- 各乖離に重大度（BLOCK/SUGGEST/NIT）と対処区分（採用/棄却/課題化）が付き、根拠（prototype 該当箇所 ⇔ 設計 md 該当節）が明示されている。
- 機械可読 JSON が `validate-review-json.sh` を通過している。
- 突合レポート md に乖離一覧・データ連鎖の根拠・次工程の案内が記載されている。
- 設計書本体・handoff が書き換えられていない（diagnostics のみ）。

## 凡例

| 略号 | 正式名称 | 補足 |
| --- | --- | --- |
| SCR-XXX | 画面 ID | 設計 `screens/` と handoff README で同一 ID を引用 |
| operationId | API 操作 ID | OpenAPI の operationId（供給元） |
| MSG-XXX | メッセージ ID | `docs/requirements/メッセージ一覧.md` |
| DS | デザインシステム | `_共通.md` / `tokens/` / `ブランドガイドライン.md` |
| 対処区分 | 採用 / 棄却 / 課題化 | 乖離ごとの推奨対処（最終判断は人間） |

## 注意事項

- **設計書・handoff・コードを書き換えない**（検出専用）。乖離の反映は `design-amendment`（設計側）か Claude Design 再調整（handoff 側）であり、本スキルはどちらも実行しない。
- 採択ゲートを迂回しない: 設計への取り込みは必ず docs `main` への PR マージ（人手採択）を経る。Claude・skill は自ら PR をマージ・`@claude` コメントをしない。
- prototype はデザイン参照用モックである。ビジュアルの細部（余白の数 px 等）の機械判定はせず、「設計に無い情報・挙動の混入」と「data-sufficiency の断絶」を主眼にする。
- 技術スタック固有の規約は再掲せず、必要時に各子の `.claude/rules/` を参照する（二重管理の禁止。矛盾時は frontend ルールが正）。
- `ブランドガイドライン.md` が不在の場合、DS 逸脱（`ds_token`）は NIT 扱いとし、未指定である旨をレポートに明記する。

## 追加資料

- UI ブリーフ作法: [../ui-brief-from-design/SKILL.md](../ui-brief-from-design/SKILL.md)
- 変更管理ルート: [../impact-analysis-from-change/SKILL.md](../impact-analysis-from-change/SKILL.md) → [../design-amendment/SKILL.md](../design-amendment/SKILL.md) → [../reopen-issues-from-amendment/SKILL.md](../reopen-issues-from-amendment/SKILL.md)
- ブランドガイドライン逆反映（BLOCK==0 後）: [../reflect-handoff-to-brand/SKILL.md](../reflect-handoff-to-brand/SKILL.md)
- Issue 起票（後段ゲート）: [../create-issues-from-design/SKILL.md](../create-issues-from-design/SKILL.md)
