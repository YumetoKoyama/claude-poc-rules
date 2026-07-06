# backend 専用スキル源（backend-skills）

このディレクトリは **claude-poc-backend 専用のスキル一式** を rules リポジトリ内でバージョン管理するための源（source）です。親 `.claude/skills/`（generic 正典）とは**別物**として分離して保持します。

## なぜ親 `.claude/skills/` と分けるのか

親 `.claude/skills/` は frontend / batch / docs とも同期される **generic な正典**で、`check-skills-sync.sh` が「親 = 子」を検査します。一方、本セットは backend 固有の事情（OpenAPI Generator 同期・生成モデル `generated.openapi.*` 運用・`augment-generated-models` 連携・`references/`・Spring Security の `R-SEC-*` 観点）を含む **backend 寄りの版**です。これを親に直接上書きすると generic 正典が backend 専用色になり、他の子との同期が壊れます。そのため分離しています。

## 中身

`.claude/skills/` 配下は **backend のスキルをベースに、rules 側のレビュー・品質改善を追加マージ**したものです。マージの詳細・各スキルの「backend 保持 / rules 追加」内訳・既知の注意点は [差分レポート.md](差分レポート.md) を参照。

主な追加改善: 依存 Issue クローズゲート(S5) / 規模 30 超 ESCALATE(S7) / 横断設計書必読(A-2) / 品質 config 照合(RC-07) / 新規依存実在性=幻覚防止(RC-06) / レイヤ別中間サマリ(S7) / レビューの iteration 独立取得・**ハッシュ照合(RC-07)** / `verify-fix` 段の追加 / NIT も修正対象(RC-08) ほか。

backend 固有の `augment-generated-models` / `use-generated-models` は本セットに**含めていません**（現行 backend のものをそのまま使う前提）。

## backend への配布手順

backend リポジトリの編集が一段落したら、別ブランチで次のように重ねる:

```bash
# rules リポジトリのルートで（claude-poc-backend は隣接配置の前提）
cp -r backend-skills/.claude/skills/. claude-poc-backend/.claude/skills/
```

その後 backend 側で確認すること:

1. ハッシュ照合はペア導入。`review-implementation`（ハッシュ照合）と `implement-from-issue`（サイドカー出力）は**必ずセット**で入れる（片方だけだと review が常時 BLOCK）。
2. `verify-fix` スキルと `verify-fix-coverage.sh` が入っていること（`implement-loop` の fix 段が参照）。
3. backend 既存の切断ファイル（`implement-from-issue/references/` の openapi-gen-sync.md / pr-template.md / quality-gate-outputs.md / test-design-draft.md）は**末尾が壊れている**ため人手で再生成する（本マージでは復元元が無く未修復）。`review-implementation/SKILL.md` の切断は本セットで修復済み。
4. 全 `.sh` の `bash -n` 構文チェック通過と、`/implement-loop <Issue>` ドライランで state 初期化・採択ゲートが動くことを確認。

## 親 generic 正典との関係

本セットの「rules 改善」部分の多くは親 `.claude/skills/`（generic 版）に既に存在する。本セットはそれを **backend 固有実装に取り込んだ版**であり、親正典を置き換えるものではない。親正典の更新は従来どおり親 `.claude/skills/` で行う。
