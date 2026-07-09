# Decision Log（意思決定記録）運用ガイド

【P-15 対応（2026-07-02 改善）】「E2E は AWS 環境構築後」「モバイルは第 1 版保証対象外」「batch はルール整備待ち」のような**スコープ・凍結・対象外の判断**が、CLAUDE.md・テスト戦略・非機能要件などに散在して追跡しづらかった。本ガイドはこれらを 1 表に集約する。

## 運用ルール

- 対象: **フェーズ成果物そのものではない横断的な判断**。とくに (a) 工程の凍結・解凍、(b) スコープ対象外の決定、(c) 技術・ツールの採否、(d) プロセス・ルールの変更判断。
- 記録タイミング: 判断した**その場**で 1 行追加する（あとでまとめない。PP-5）。
- 決定者: 人間（採択者）。Claude は「D-ID 起票案」を提示してよいが、確定・記入は人間が行う。
- 各成果物からの参照: 成果物側に判断理由を長文で書かず、`（Decision Log D-xxx 参照）` と参照する（二重管理の禁止）。
- RTM との連動: 意図的にテストしない AC は RTM 備考欄に D-ID を記入する（`generate-rtm-skeleton.sh` の運用ルール参照）。
- クローズ条件（見直し予定日 or 条件）を必ず書く。「無期限凍結」を禁止し、解凍条件を明文化する。

## 記録先

docs リポジトリの `docs/process/decision-log.md`（本ガイドとは別ファイル。プロジェクト実体側に置く）。初回は下の雛型をコピーして作成する。

## ID 採番（2026-07-09 改訂）

D-ID は **2 桁連番**（`D-01`〜。`id-legend.md` 例外規定）。hooks・`_common/scripts`・skill 本文が先行して D-01〜D-21 を引用済みのため、下表「既引用ぶんの遡及登録」で意味を確定し、新規の決定は D-22 以降で採番する。

## 既引用ぶんの遡及登録（hooks/scripts/skill 本文からの逆引き・要確認）

> 本表は本リポジトリのコード・skill 本文中の D-ID コメントから内容を逆引きしたもの。**日付・決定者は原記録が無いため未詳**。人間が判明次第埋めること。

```markdown
| D-ID | 日付 | 区分 | 決定内容 | 理由 / 引用元 | 決定者 | 影響範囲 | 見直し条件 | 状態 |
|---|---|---|---|---|---|---|---|---|
| D-01 | 未詳 | プロセス | design フェーズの fix は採択済み要件を直接編集しない。要件起因の指摘は `requirements-feedback.md` への追記で正規に起票する | fix-design の編集範囲ガード／verify-fix の判定基準 | 未詳 | fix-design, verify-fix | - | active |
| D-02 | 未詳 | プロセス | 決定論スクリプトの findings を偽陽性と判断しても手動でマージ除外せず、`suppressions.tsv` に理由付きで宣言し機械的に除外する（手動除外禁止） | review-design / review-requirements / format-review-json.sh | 未詳 | 全 review-* skill | - | active |
| D-03 | 未詳 | プロセス | 各 produce/fix skill の先頭で `state-dir.sh` 経由の絶対パスを取得し `STATE_DIR` とする。`.skills-state/...` の相対パス直書きは禁止 | design-loop, fix-design, fix-requirements ほか | 未詳 | 全 *-loop 系 skill | - | active |
| D-04 | 未詳 | 採否 | `loop-metrics.sh` の `--out` 探索で、root 自体が phase ディレクトリ（state.json を直接含む）の場合も受理する | loop-metrics.sh / design-loop | 未詳 | loop-metrics.sh | - | active |
| D-06 | 未詳 | プロセス | design-loop PASS 時のサマリで、`/humanize-design` 実行と人手採択（11-adoption-checklist.md）を必ず案内する | design-loop 開発フロー 3.5 | 未詳 | design-loop | - | active |
| D-07 | 未詳 | 採否 | `protect-canon.sh` の保護対象を「`.claude/rules/`・ルート直下 `rules/`・境界直下の CLAUDE.md」に限定する。業務コード中の任意階層 `.../rules/` は保護対象から除外する（旧 `(^|/)rules/` パターンの過剰ブロックを是正） | protect-canon.sh | 未詳 | protect-canon.sh, rules/cross-cutting.md | - | active |
| D-08 | 未詳 | 採否 | `block-secrets.sh` に、裸の `rm -rf *` 等の無防備なワイルドカード削除、`.env` の source 取り込み、シェル経由の env 出力を検出パターンとして追加する | block-secrets.sh | 未詳 | block-secrets.sh | - | active |
| D-10 | 未詳 | 採否 | `python3` 不在時は fail-open ではなく fail-closed（deny）にする（block-secrets.sh / protect-canon.sh / block-force-push.sh で統一方針） | 各 hook スクリプト | 未詳 | .claude/hooks/*.sh | - | active |
| D-13 | 未詳 | プロセス | skill 本文で他 skill をコマンド起動する際、slash 表記をコードフェンスに置かず地の文で記述する（Bash に誤って渡り実行されるのを防ぐ） | implement-from-issue / test-design-draft.md | 未詳 | implement-from-issue | - | active |
| D-14 | 未詳 | プロセス | 実装時に新規追加する依存パッケージは、確定表照合に加えて実在性を確認する（幻覚パッケージの混入防止。RC-06 と対） | implement-from-issue / project-init-check.md | 未詳 | implement-from-issue | - | active |
| D-15 | 未詳 | 対象外 | `claude-poc-batch` も実装を伴うリポジトリとして `check-stack-decided.sh` の確認対象に含める（RC-09 と対） | check-stack-decided.sh | 未詳 | check-stack-decided.sh | - | active |
| D-16 | 未詳 | プロセス | 実装は必ず `implement-loop`（結合は `integration-test-loop`）経由で起動し state を初期化する。単独起動された `implement-from-issue` 等は iteration 管理・終了条件・採択ゲートが効かないため無効とする | implement-loop, integration-test-loop | 未詳 | implement-loop, integration-test-loop | - | active |
| D-21 | 未詳 | プロセス | 実装対象リポジトリの品質 config 群（lint/format/coverage 設定等）の存在と参照整合を、実装開始前に確認する（RC-07 と対） | implement-from-issue / project-init-check.md | 未詳 | implement-from-issue | - | active |
```

（D-05, D-09, D-11, D-12, D-17〜D-20 は現時点でコード・skill 本文からの引用が見つからず欠番。将来 D-ID を追跡調査で発見した場合はここに追記する。）

## 雛型（新規決定はここから連番、D-22 以降）

```markdown
| D-ID | 日付 | 区分 | 決定内容 | 理由 | 決定者 | 影響範囲 | 見直し条件 | 状態 |
|---|---|---|---|---|---|---|---|---|
| D-22 | 2026-06-XX | 凍結 | E2E テストは現環境では実行しない | AWS 環境未構築。FE は Vitest+MSW、BE は Testcontainers で代替 | （要件採択者名） | claude-poc-e2e / テスト戦略.md / RTM の E2E 列 | AWS 環境構築完了時に解凍 | active |
| D-23 | 2026-06-XX | 対象外 | モバイル/タブレットは第 1 版の保証対象外（レスポンシブ対応はする） | デモ用途主眼のため | （同上） | 非機能要件.md Q-NF10 / FE 実装 | 第 2 版スコープ検討時 | active |
| D-24 | 2026-06-XX | 待機 | batch は .claude/rules 整備まで実装 Issue に着手しない | 技術スタック未確定（batch-00-stack.md に要確定残） | （同上） | claude-poc-batch | batch-00-stack.md の要確定解消時 | active |
```

（上記 3 行は本 PoC で実際に散在していた判断の例。作成時に日付・決定者を正しく埋めること。E2E-from-design / G-09 等、既存文書が「D-001」で言及していた場合は D-22 に読み替える）

## 区分の凡例

| 区分 | 意味 |
|---|---|
| 凍結 | 工程・機能を一時停止（解凍条件つき） |
| 対象外 | 今スコープでやらないことの確定 |
| 採否 | 技術・ツール・方式の採用/不採用 |
| プロセス | 開発プロセス・ルールの変更判断（正典変更は propose-canon-patch → 人手適用とセット） |
