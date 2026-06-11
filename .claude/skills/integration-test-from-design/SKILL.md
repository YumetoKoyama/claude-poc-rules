---
name: integration-test-from-design
description: フィーチャ単位で結合テストを設計（結合テストマトリクス/IT-XXX）し、コンポーネントが組み上がった後に @SpringBootTest + Testcontainers で実施する独立工程。製造（implement-from-issue）とは分離した結合テスト工程向け。E2E とは別レイヤー。
context: fork
argument-hint: <フィーチャ名 または 結合テスト Issue 番号>
---

# 結合テスト工程（設計＋実施）

> **なぜ製造と分けるか**: 製造の単位は 1 Issue（1 画面 / 1 API / 1 テーブル）であり、その時点では結合の相手コンポーネントが揃っていないため **結合テストは設計・実施とも完結しない**。結合テストはフィーチャ単位で複数 Issue をまたぐので、構成コンポーネントが `main` に組み上がった後に独立工程として行う（E2E を別工程にしているのと同じ理由）。

> **責務の範囲**: 本工程は 結合テストの **設計（IT マトリクス）と実施（実行）** の両方を担う。単体テスト（TC-XXX）は製造（`/test-design-from-issue` + `/unit-test-from-design`）の責務、E2E（E2E-XXX）はさらに上位の別工程（`/e2e-from-design`・凍結中）の責務。

> **トリガ**: あるフィーチャの構成 Issue 群が採択・マージされ、結合点が成立した後に起動する。製造の各実装 Issue からは呼ばない。`/implement-from-issue` のゲート（unit）とは独立に、本工程のゲート（integration）を持つ。

> **パス解決**: 読み取り入力（`docs/requirements/`・`docs/design/`）は docs リポジトリ ルート相対。書き込み出力（`docs/test/結合テストマトリクス.md`・RTM・結合テストコード）は own リポジトリ（実装リポ）のワーキングツリー直下。

対象: $ARGUMENTS

## 手順

### 1. 結合スコープの確定

1. 対象フィーチャに属する 設計シーケンス（`docs/design/sequences/*.md`・SEQ-XXX）・API（operationId）・画面（SCR-XXX）・関連 Issue 群を洗い出す。
2. 結合点を特定する: Controller→Service→Repository→DB の実結合、サービス間連携（通知発火 × トランザクション境界・排他制御）、認可・テナント境界の越境防止。
3. 構成コンポーネントが揃っているか確認する。未マージの依存がある場合は中断し、対象を待つ。

### 2. 結合テストマトリクスの設計（IT-XXX）

`docs/test/結合テストマトリクス.md` を [test-design-from-issue の test-design-matrix-template.md](../test-design-from-issue/test-design-matrix-template.md) の結合テスト節の様式で作成・更新する。

- 各ケースに **IT-XXX（3 桁ゼロ埋め）** を採番し、AC-XXX・SCR-XXX・API operationId・SEQ-XXX と相互参照する。
- 区分は **正常系 / 異常系 / 境界値 / 権限境界**。特にテナント越境・認可バイパス・トランザクション境界・排他制御の結合観点を含める。
- 結合点が無いフィーチャは、ファイルを作成し `対象外` 区分と理由を明記する。

### 3. 結合テストの実施

@SpringBootTest + Testcontainers（実 DB）で結合テストを実装・実行する。

- Controller→Service→Repository→DB の実結合、サービス間結合、認可フィルタ・例外ハンドラの結合動作を検証する。
- 実装した結合テストコードと IT-XXX を突合し、件数とシナリオを一致させる。
- 結合テストコードの配置・命名は `claude-poc-backend/.claude/rules/backend-*.md` の規約に従う。

### 4. RTM の更新（IT-XXX 列）

`docs/test/トレーサビリティマトリクス.md` の該当 AC / SCR 行の **IT-XXX 列** を埋める（製造で TC-XXX は記入済みの前提。RTM の正は横串カバレッジ）。

### 5. ハードゲート（必須・出力検証）

```bash
bash .claude/skills/_common/scripts/check-test-matrix.sh docs/test <ISSUE> integration
```

`integration` フェーズで 結合マトリクス（IT-XXX、または対象外理由）と RTM を機械検証する。**exit 0 になるまで本工程を完了しない**。

### 6. コミットと push

結合テストマトリクス・RTM・結合テストコードを commit/push して PR に含める。

## 完了条件

- 結合テストマトリクス（IT-XXX、または対象外＋理由）が作成されている
- 結合テストが @SpringBootTest + Testcontainers で実装・実行され通過している
- RTM の IT-XXX 列が更新されている
- `check-test-matrix.sh ... integration` が exit 0 を返す

## 凡例

| 略号 | 正式名称 | 補足 |
| --- | --- | --- |
| IT-XXX | 結合テストケース ID | 3 桁ゼロ埋め |
| TC-XXX | 単体テストケース ID | 製造で採番済み |
| SEQ-XXX | シーケンス ID | `docs/design/sequences/*.md` |
| RTM | トレーサビリティマトリクス | 横串カバレッジの正 |

## 注意事項

- 単体テスト（TC）は製造の責務。本工程では扱わない。E2E はさらに上位の別工程。
- 結合点が成立する前に起動しない（製造の各 Issue からは呼ばない）。
- 強調表記は鉤括弧 `「...」` を使う。
