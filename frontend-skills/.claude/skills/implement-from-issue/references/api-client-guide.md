# フロントエンド API クライアント実装ガイド

## 3a. 型定義の事前確認と生成（必須）

フロントエンド実装を開始する前に、実装対象の API リソース YAML（例: `docs/design/api/jobs.yaml`）に対応する生成型ファイル（例: `src/lib/api/generated/jobs.d.ts`）が存在するかを確認する。

```bash
ls src/lib/api/generated/
```

対応する `.d.ts` が存在しない場合、または `docs/design/api/` 配下の YAML が更新されて生成ファイルが古い可能性がある場合は、型生成を実行する:

```bash
npm run gen:types
```

- スクリプトは `scripts/gen-api-types.sh` が実体。YAML を 1 ファイルずつ検査し、パースエラーのあるファイルは `⚠️ SKIP` して残りを生成する。
- `❌ スキップ` と表示されたファイルがある場合は、対応する YAML の構文エラーを先に修正してから再実行する（`claude-poc-docs/.claude/skills/_common/scripts/validate-yaml-format.sh` で検出可能）。
- 生成ファイルは `.gitignore` 対象のため、コミット対象には含めない。

## 3b. API 呼び出しは `createApiClient` を使用（必須）

`src/features/*/services/*.ts` で API を呼び出す場合は、生の `fetch` や旧来の `apiClient` ではなく `createApiClient<paths>()` を使う。これにより、パス・クエリパラメータ・リクエストボディ・レスポンスの型がすべてコンパイル時に検証される。

```ts
import { createApiClient } from "@/lib/api/client"
import type { paths } from "@/lib/api/generated/jobs"  // 対象リソースの生成型

const client = createApiClient<paths>()

// GET（クエリパラメータ付き）
const { data, error } = await client.GET("/jobs", {
  params: { query: { page: 0, size: 20 } },
})

// GET（パスパラメータ付き）
const { data, error } = await client.GET("/jobs/{jobId}", {
  params: { path: { jobId: "abc-123" } },
})

// POST（リクエストボディ付き）
const { data, error } = await client.POST("/jobs", {
  body: { title: "案件名", ... },
})
```

- `data` は成功時のレスポンス型（`undefined` でなければ成功）、`error` はエラー時のレスポンス型。
- 認証ヘッダーの付与・401 時の `/login` リダイレクトはミドルウェアが自動処理するため、サービス層では意識しない。
- パス文字列（`"/jobs/{jobId}"` 等）は生成型の `paths` キーと完全一致する必要があり、タイポはコンパイルエラーになる。
