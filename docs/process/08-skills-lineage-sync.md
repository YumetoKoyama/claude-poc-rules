# スキル 3 系統（generic / frontend / backend）の同期方針

【P-13 対応（2026-07-02 改善）】スキルが次の 3 系統に分岐し、手動 grafт（接ぎ木）マージで維持されてきた。差分レポートは丁寧だが、手順依存で壊れやすい（片系統だけの更新・還流漏れ・切断ファイル残存）。本文書はその管理方式を確立する。

| 系統 | 場所 | 役割 |
|---|---|---|
| generic 正典 | 親 `.claude/skills/` | 全子リポ共通のベース。改善はまずここに入れる |
| frontend 版 | `frontend-skills/.claude/skills/` | FE 固有規約（Vitest/MSW/IT 層なし等）を保持した grafт 版 |
| backend 版 | `backend-skills/.claude/skills/` | BE 固有規約（OpenAPI Generator/JaCoCo/migration 等）を保持した grafт 版 |

## 原則（base + overlay）

1. **改善はまず generic 正典へ**。系統固有ファイルへ直接入れた改善は「還流漏れ」としてドリフト検知の対象になる。
2. **系統固有の分岐は宣言制**: 意図的に generic と異なるファイルは、系統ルート直下の `lineage-manifest.txt` に**理由つきで 1 行ずつ宣言**する。宣言なき差分 = 事故（ドリフト）として CI で fail させる。
3. **_common/scripts/*.sh は内容一致が既定**（決定論スクリプトこそ分岐させない）。分岐が必要な場合（例: FE の check-test-matrix.sh は IT 層なしのため integration を exit 2 で拒否）のみ manifest 宣言。
4. **SKILL.md は grafт 前提**のため内容一致は求めない。かわりに (a) grafт マーカー `<!-- rules 改善 ... -->` で由来追跡を残す、(b) generic 側の改善を系統へ反映したら差分レポートを更新する。
5. **切断ファイルを持ち込まない**: 系統への取り込み前に `check-truncation.sh` を必ず通す（backend 原本に未修復切断 4 本が残った反省。D-1）。

## 機械検査

```bash
# 親リポジトリのルートで
bash .claude/skills/_common/scripts/check-skills-lineage-sync.sh . frontend-skills backend-skills
```

検査内容: (1) _common/scripts の未宣言ドリフト（fail）、(2) 親で追加したスクリプトの配布漏れ（fail）、(3) 系統のみに存在するスクリプト＝還流漏れ候補（fail）、(4) スキル所在差分と grafт マーカー残存（情報/WARN）。

CI・pre-push・スキル取り込み作業の完了条件として実行する。

## lineage-manifest.txt の書式

系統ルート直下（例: `frontend-skills/lineage-manifest.txt`）。`#` 以降はコメント。

```
.claude/skills/_common/scripts/check-test-matrix.sh   # FE は IT 層なし: integration を exit 2 で拒否する固有版を維持（差分レポート §4）
```

## 更新フロー（generic に改善が入った場合）

1. generic 正典を更新（正典保護下のスキルは propose-canon-patch → 人手適用）。
2. `check-skills-lineage-sync.sh` を実行 → 配布漏れ（MISSING/DRIFT）が列挙される。
3. 系統へ反映（grafт。系統固有記述を保持し、挿入箇所にマーカーを残す）。
4. 差分レポート（`frontend-skills/差分レポート.md` 等）に反映内容を追記。
5. 再度 `check-skills-lineage-sync.sh` → OK を確認してからコミット。

## 既知の残課題

- backend 原本由来の未修復切断ファイル 4 本（`openapi-gen-sync.md` / `pr-template.md` / `quality-gate-outputs.md` / `test-design-draft.md`）は generic に同等物が無く再生成が必要（backend-skills/差分レポート.md の警告）。再生成時は BE リポジトリの実装実態と突合して人手レビューすること。
