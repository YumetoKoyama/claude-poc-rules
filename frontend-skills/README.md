# frontend 専用スキル源（frontend-skills）

このディレクトリは **claude-poc-frontend 専用のスキル一式** を rules リポジトリ内でバージョン管理するための源（source）です。親 `.claude/skills/`（generic 正典）とは**別物**として分離して保持します（`backend-skills/` と並列）。

## なぜ親 `.claude/skills/` と分けるのか

親 `.claude/skills/` は backend / frontend / docs とも同期される **generic な正典**で、`check-skills-sync.sh` が「親 = 子」を検査します。一方、本セットは frontend 固有の事情（**FE 規約の正典＝frontend ルール最優先**・Vitest / React Testing Library / MSW・Zustand・`apiClient.ts`・**フロントエンドに IT 層が無いという設計不変条件**・ESLint / Prettier / TypeScript 型チェック・npm audit）を含む **frontend 寄りの版**です。これを親に直接上書きすると generic 正典が frontend 専用色になり、他の子との同期が壊れます。そのため分離しています。

## 中身

`.claude/skills/` 配下は **frontend のスキルをベースに、rules 側のレビュー・品質改善を追加マージ**したものです。マージの詳細・各スキルの「frontend 保持 / rules 追加」内訳・既知の注意点は [差分レポート.md](差分レポート.md) を参照。

主な追加改善: 依存 Issue クローズゲート(S5) / 規模 30 超 ESCALATE(S7) / 横断設計書必読(A-2) / 品質 config 照合(RC-07) / 新規依存実在性=幻覚防止(RC-06) / レイヤ別中間サマリ(S7) / レビューの iteration 独立取得・**ハッシュ照合(RC-07・時刻依存を移行フォールバックへ)** / 設計採択ゲート(M-6) / 上限到達後の再実行検出 / `verify-fix` 段の配線 / NIT も修正対象(RC-08) / TC 続番採番(RC4) ほか。

backend 専用概念（OpenAPI Generator 同期 / 生成モデル `generated.openapi.*` / `augment-generated-models` / `use-generated-models` / Spring Security の `R-SEC-*` / JaCoCo・migration・concurrency）は **frontend には持ち込んでいません**。

## frontend への配布手順

frontend リポジトリの編集が一段落したら、別ブランチで次のように重ねる:

```bash
# rules リポジトリのルートで（claude-poc-frontend は隣接配置の前提）
cp -r frontend-skills/.claude/skills/. claude-poc-frontend/.claude/skills/
```

その後 frontend 側で確認すること:

1. ハッシュ照合はペア導入済み。`review-implementation`（`coverage/.gate-commit` 読込・照合）と `implement-from-issue`（`coverage/.gate-commit` 書込）は**必ずセット**で入れる（片方だけだと review が常時 BLOCK）。移行期はサイドカー不在のレポートを時刻照合にフォールバックする一文を review 側に入れてある（非破壊）。
2. `verify-fix` スキルと `verify-fix-coverage.sh` が入っていること（`implement-loop` の fix 段が参照）。frontend には元から存在し rules と完全一致。
3. **frontend に IT 層は無い**設計不変条件のため、`check-test-matrix.sh` は frontend 版（`unit` フェーズのみ・`integration` を exit 2 で拒否）を**そのまま維持**した（rules 版で上書きしない）。
4. 全 `.sh` の `bash -n` 構文チェック通過と、`/implement-loop <Issue>` ドライランで state 初期化・設計採択ゲート（`check-adopted.sh`）が動くことを確認。

## 親 generic 正典との関係

本セットの「rules 改善」部分の多くは親 `.claude/skills/`（generic 版）に既に存在する。本セットはそれを **frontend 固有実装に取り込んだ版**であり、親正典を置き換えるものではない。親正典の更新は従来どおり親 `.claude/skills/` で行う。
