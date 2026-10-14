# スノー生命 法人営業 AI アプリ ハンズオン（CoCo CLI）

このフォルダは、ハンズオン参加者が CoCo CLI と対話しながら、Cortex Agent を組み込んだ Web アプリを作り、Snowflake App Runtime にデプロイするための作業場所です。参加者は Snowflake とプログラミングの初心者です。

**参加者への返答・途中経過の説明は、必ずすべて日本語で書いてください**（スキルの説明やツールの出力が英語でも、返答は日本語にします）。専門用語には短い補足を付けてください。

## すでに用意されているもの

| 種類 | 名前 | 内容 |
|---|---|---|
| Cortex Agent | `SNOWLIFE_HANDSON_DB.AI.SALES_AGENT` | 法人営業アシスタント。セマンティックビュー・Cortex Search・業務スキル 3 件を使う |
| セマンティックビュー | `SNOWLIFE_HANDSON_DB.AI.SV_SALES_ANALYTICS` | 取引先・商談・活動・既契約・企業財務・求人件数 |
| Cortex Search | `AI.PRODUCT_DOC_SEARCH` / `AI.MEETING_NOTE_SEARCH` | 商品資料 PDF・面談メモ |
| データ | `SNOWLIFE_HANDSON_DB.RAW` / `MART` | CRM 相当のテーブル（`SF_ACCOUNT`、`SF_OPPORTUNITY`、`SF_ACTIVITY`、`SF_CONTRACT` など） |
| アプリ | `app/`（Next.js） | Agent に質問できるチャット画面。`app.yml` でデプロイ先を定義済み |
| アプリの置き場所 | `SNOWLIFE_HANDSON_DB.APP` | `snow app deploy` で Application Service が作られる |

接続は `handson`（`.snowflake/config.toml`、ロール `ACCOUNTADMIN`）です。

## アプリの構成

- `app/app/page.tsx`: トップページ。`<AgentChat />` を表示
- `app/components/agent-chat.tsx`: チャット画面（クライアントコンポーネント）。`askAgent()` が「受付 → 3 秒ごとに結果確認」を行う
- `app/app/api/agent/route.ts`: Agent を呼ぶ API。`POST` で質問を受け付けて `jobId` をすぐ返し、`GET ?jobId=` で結果（回答テキスト・使ったツール・生成された SQL）を返す。内部では `SNOWFLAKE.CORTEX.DATA_AGENT_RUN` を `querySnowflakeLongRunning` とバインド変数で実行する
  - デプロイ先の入口は **約 90 秒で接続を切る（504 upstream request timeout）**。Agent は 1 分以上かかることがあるので、この 2 段階の仕組みを 1 回のリクエストで待つ形に戻さないでください
  - 画面の別の部品から Agent に質問させたいときも、この API を同じ手順で使ってください
  - 30 秒を超えそうな重い集計を作るときも、同じく「受付 → 結果確認」の形にしてください
- `app/lib/snowflake.ts`: Snowflake への接続。ローカルでは `SNOWFLAKE_HOME` の `config.toml`、デプロイ後は SPCS のトークンを自動で使う
- `app/lib/constants.ts`: アプリのタイトルとロゴ

## 画面の確認方法（参加者の操作）

参加者は別ウィンドウで `start_dev_win.bat`（Mac は `start_dev_mac.command`）を実行し、`http://localhost:3000` を開いています。ファイルを保存すると画面は自動で更新されます。

- あなた（CoCo）は `npm run dev` を自分で起動しないでください。ポートが重なります。
- 変更したら「ブラウザの画面を確認してください」と案内してください。
- 画面がエラーになったら、参加者に dev サーバーのウィンドウに出ているエラーを貼ってもらい、直してください。
- 依存パッケージを追加したときは、`app/` で `npm install` を実行してください（dev サーバーは止めなくてよい）。

## 作業のルール

- 変更は `app/` の中だけで行ってください。`catchup.sql`・`sql/`・`setup_*`・`start_dev_*` は変更しないでください。
- データは必ず Snowflake の実データを使ってください。モックや固定値で画面を作らないでください。
- SQL にユーザー入力を入れるときは、必ず `binds` を使ってください（SQL インジェクション対策）。
- 10 秒を超えそうな処理（Agent の呼び出し、重い集計）は `querySnowflakeLongRunning` を使ってください。
- `app/lib/snowflake.ts` と `app/next.config.mjs` は変更しないでください。
- グラフは `recharts` を使ってください（`components/chart-utils.tsx` に補助関数があります）。
- 画面の文言は日本語にしてください。
- Snowflake のオブジェクト（Agent・セマンティックビュー・テーブル）の作成・変更・削除はしないでください。参加者から明示的に頼まれた場合だけ、実行前に内容を説明して確認を取ってください。

## デプロイ（参加者に「デプロイして」と頼まれたら）

1. `app/` で `npm run build` が通ることを確認する
2. デプロイ先（`SNOWLIFE_HANDSON_DB.APP.SNOWLIFE_SALES_APP`）を短く示し、「はい」と返事をもらってから進む
3. `app/` で `snow app deploy -c handson` を実行する（初回は 3〜5 分ほどかかる。進み具合を参加者に伝える）
4. 表示された URL（`https://<id>.snowflakecomputing.app`）を参加者に伝える。ブラウザで開くと Snowflake のログインを求められる

詳しい手順や `app.yml` の書き方は `snowflake-apps` スキルを参照してください。

## 困ったときの確認先

- デプロイ後のログ: `CALL SYSTEM$GET_APPLICATION_SERVICE_LOGS('SNOWLIFE_HANDSON_DB.APP.SNOWLIFE_SALES_APP')`
- Agent の動作確認: `SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('SNOWLIFE_HANDSON_DB.AI.SALES_AGENT', '<JSON>')`
