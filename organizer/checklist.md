# 主催者向けチェックリスト

参加者ごとのトライアルアカウントで Snowflake App Runtime（SAR）を使えるようにし、当日を迎えるまでの作業です。

## 1. 参加者に事前準備をお願いする（開催 2 週間前まで）

セットアップガイド（Google スライド）を送り、次をお願いします。

- [ ] AWS 東京（ap-northeast-1）でトライアルアカウントを作成する
- [ ] Snowsight で次の SQL を実行し、結果を返信する

```sql
SELECT CURRENT_ACCOUNT()           AS account_locator,
       CURRENT_ORGANIZATION_NAME() AS org_name,
       CURRENT_ACCOUNT_NAME()      AS account_name,
       CURRENT_REGION()            AS region;
```

- [ ] CoCo CLI・Snowflake CLI（3.29 以上）・Node.js（LTS）をインストールする

## 2. SAR を許可する（返信を受け取ったら）

- [ ] 返信をまとめる（氏名 / account_locator / org_name-account_name / region）
- [ ] region が `AWS_AP_NORTHEAST_1` であることを確認する
- [ ] prod 環境で、account_locator ごとに SAR 許可のパラメータを設定する（社内手順に従う）
- [ ] 設定したアカウントの一覧を記録する

## 3. 前日までの確認

- [ ] 主催者のリハーサル用トライアルで、ZIP の展開から `snow app deploy` まで通ることを確認する
- [ ] リポジトリの `main` が最新であることを確認する（`catchup.sql` は GitHub からデータを取り込むため）
- [ ] 当日の会場ネットワークで次に接続できることを確認する
  - `*.snowflakecomputing.com` / `app.snowflake.com`
  - `*.snowflakecomputing.app`（デプロイしたアプリ）
  - `registry.npmjs.org`（npm install）
  - `github.com`（ZIP のダウンロード）

## 4. 当日よくあるつまずき

| 症状 | 対処 |
|---|---|
| `setup_win.bat` が `[NG]` を出す | セットアップガイドの補足ページでインストール・更新 |
| PAT の生成に失敗 | パスワード・アカウント識別子の誤り。識別子は `ORG-ACCOUNT` 形式 |
| catchup.sql が失敗 | `.temp\catchup.log` の末尾を確認。AI 機能が無効、またはクロスリージョン推論が設定できていない可能性 |
| `npm install` が失敗 | 社内プロキシ。`npm config set proxy` が必要か、参加者の情報システム部門に確認 |
| `snow app deploy` が権限エラー | SAR のパラメータが未設定。手順 2 を確認 |
| localhost:3000 で Agent がエラー | dev サーバーのウィンドウのエラーを CoCo に貼って修正を依頼 |

## 5. 後片付け

- [ ] 参加者に `cleanup.sql` の実行を案内する（任意）
- [ ] トライアルは 30 日で期限が切れる。PAT も 30 日で失効する
