---
name: unit-test-from-design
description: 設計書または要件定義書から単体テストを作成し、失敗時は根本原因を調査して修正するときに使う。設計から UT 資産へ落とし込むフェーズ向け。
disable-model-invocation: true
context: fork
argument-hint: [設計書または要件定義書のパス]
---

# 設計書から単体テストを作成する

> **パス解決（マルチリポジトリ対応）**: 本スキル内の `docs/requirements/`・`docs/design/`・`docs/test/` は **docs リポジトリ（claude-poc-docs）ルート相対**のパスを指す。
> - docs リポジトリをカレントとして実行している場合: そのまま使う。
> - 親アンブレラ（claude-poc-rules）から実行している場合（カレント直下に `claude-poc-docs/` が存在する場合）: これらすべてのパスに `claude-poc-docs/` を前置して読み書きする。
> - CI（子リポジトリ単体のチェックアウト）で docs リポジトリが存在しない場合: workflow が追加チェックアウトした docs のパスを使う。それも無い場合は Issue 本文に埋め込まれた設計情報を入力とし、原本の参照が必要なら中断して人間に確認する。

> **呼び出し元**: `/implement-from-issue` の品質ゲート（手順 5・Pattern 2 並列ファンアウト）から「単体テスト」担当として呼ばれる補助 skill。設計フェーズ完了後に単独起動することもできる。Agent Teams は使わない。

次の入力をもとに単体テストを作成または更新する: $ARGUMENTS

## 指示

1. 設計書または要件定義書を読む。
   - 要件定義の受け入れ条件: `docs/requirements/functional/[機能名].md` の AC-XXX
   - API の仕様: `docs/design/api/[リソース名].yaml`（リソースごとに 1 ファイル、共通スキーマは `docs/design/api/_common.yaml`）
   - 画面の仕様: `docs/design/screens/[scr-id]-*.md`
   - DB の仕様: `docs/design/tables/[テーブル名].md`
2. 要件と単体テストの対応表がない場合は [unit-test-matrix-template.md](unit-test-matrix-template.md) を使って作成する。
3. 要件の AC-XXX、業務ルール BR-XXX、API の各レスポンス、入力検証、分岐、例外処理に対して焦点のあるテストを追加する。バックエンドは JUnit 5 + Mockito + MockMvc、フロントエンドは Vitest / Jest + React Testing Library を使う。
4. 最も狭い関連テストコマンドを実行する。
5. テスト失敗時は、アプリケーションコード、テスト設計、セットアップのどこに原因があるかを判断し、根本原因を修正する。
6. 修正ごとに同じ焦点の検証を再実行する。

## 追加資料

- テンプレート: [unit-test-matrix-template.md](unit-test-matrix-template.md)
