/*
================================================================================
スノー生命 法人営業 AI アプリ ハンズオン - 環境の一括構築（catchup.sql）
================================================================================
前回のハンズオン（snowlife-corporate-sales-handson）の Part 1〜4 の到達点を
まとめて作ります。setup_win.bat / setup_mac.command が自動で実行します。

  1. データ基盤（CRM・PDF・Cortex Search・営業職員ロール）（sql/01_setup.sql）
  2. セマンティックビュー AI.SV_SALES_ANALYTICS（sql/02_semantic_view.sql）
  3. Cortex Agent（SALES_AGENT / SALES_AGENT_BASIC）（sql/03_agents.sql）
  4. Agent の業務スキル 3 件（sql/04_skills.sql）
  5. アプリの置き場所（APP スキーマ）（sql/05_app.sql）

【前提条件】ACCOUNTADMIN ロール / AI 機能が有効なアカウント
【所要時間】約 5 分
【再実行】何度実行しても同じ状態になります

このファイルは tools/build_catchup.py で生成しています。直接編集せず、sql/ を直してください。
================================================================================
*/


-- ################################################################################
-- sql/01_setup.sql: データ基盤（CRM・PDF・Cortex Search・営業職員ロール）
-- ################################################################################

/*
================================================================================
生命保険 法人営業向け Snowflake AI ハンズオン - 環境セットアップスクリプト
================================================================================

【概要】
架空の生命保険会社「スノー生命」の法人営業データ基盤を構築します。
ご提案アーキテクチャの縮小版です。

  構造化データ   : CRM（Salesforce 相当）・既契約・活動履歴
  非構造化データ : 面談メモ・面談記録 PDF・商品パンフレット / 約款 PDF
  他部署データ   : 財務企画部の企業財務（別データベース）
  外部データ     : 求人件数（オルタナティブデータ相当）

【処理内容】
  Step 1: 環境設定（クロスリージョン推論・ウェアハウス）
  Step 2: データベース・スキーマ・ステージの作成
  Step 3: GitHub 連携（API 統合と Git リポジトリ）
  Step 4: GitHub からファイルをステージへ搬入
  Step 5: CRM・外部データのテーブル作成とロード（RAW）
  Step 6: 財務企画部データのロード（FINANCE_PLANNING_DB）
  Step 7: データマートの作成（MART）
  Step 8: 商品資料 PDF の構造化と Cortex Search の作成（AI）
  Step 9: 比較用の最小セマンティックビューの作成（AI）
  Step 10: 営業職員ロールと行アクセスポリシー（SECURITY）
  Step 11: Snowflake CoWork オブジェクトの作成

【前提条件】
  ・ACCOUNTADMIN ロールが使えること
  ・AI 機能（Cortex / CoCo / CoWork）が有効なアカウントであること

【実行方法】
  直接は実行しません。tools/build_catchup.py で catchup.sql にまとめ、
  setup_win.bat / setup_mac.command から実行されます。

【所要時間】
  約3〜5分（Step 8 の PDF 解析と Search 作成に1〜2分かかります）
================================================================================
*/


-- ============================================================================
-- Step 1: 環境設定
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- 東京リージョンなど、一部のモデルがローカルにないリージョンでも Cortex を使えるようにします
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

CREATE WAREHOUSE IF NOT EXISTS SNOWLIFE_HANDSON_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND   = 60
    AUTO_RESUME    = TRUE
    COMMENT        = '法人営業 AI ハンズオン用ウェアハウス';

USE WAREHOUSE SNOWLIFE_HANDSON_WH;

SELECT '【Step 1】環境設定が完了しました' AS status;


-- ============================================================================
-- Step 2: データベース・スキーマ・ステージの作成
-- ============================================================================

CREATE DATABASE IF NOT EXISTS SNOWLIFE_HANDSON_DB
    COMMENT = 'スノー生命（架空）法人営業データ基盤';

USE DATABASE SNOWLIFE_HANDSON_DB;

CREATE SCHEMA IF NOT EXISTS RAW      COMMENT = 'ソースシステムから取り込んだままのデータ（CRM・外部データ・面談メモ）';
CREATE SCHEMA IF NOT EXISTS MART     COMMENT = '営業分析用に整形したデータマート';
CREATE SCHEMA IF NOT EXISTS AI       COMMENT = 'セマンティックビュー・Cortex Search・Cortex Agent';
CREATE SCHEMA IF NOT EXISTS SECURITY COMMENT = '行アクセスポリシーと権限マッピング';

USE SCHEMA SNOWLIFE_HANDSON_DB.RAW;

-- CSV を受け取るステージ
CREATE OR REPLACE STAGE DATA_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT    = 'CRM・外部データの CSV';

-- PDF を受け取るステージ（AI_PARSE_DOCUMENT・AI_EXTRACT で読み込みます）
CREATE OR REPLACE STAGE DOC_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY  = (ENABLE = TRUE)
    COMMENT    = '面談記録 PDF・商品パンフレット / 約款 PDF';

-- Cortex Agent の skills を置くステージ
-- 注意: SKILL.md は各スキルフォルダの直下に置く必要があります（サブディレクトリは探索されません）
-- 再実行しても Part 4 でアップロードした SKILL.md が消えないよう、IF NOT EXISTS で作成します
CREATE STAGE IF NOT EXISTS SNOWLIFE_HANDSON_DB.AI.SKILL_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY  = (ENABLE = TRUE)
    COMMENT    = 'Cortex Agent skills（SKILL.md）';

CREATE OR REPLACE FILE FORMAT CSV_FF
    TYPE                         = CSV
    SKIP_HEADER                  = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    EMPTY_FIELD_AS_NULL          = TRUE
    ENCODING                     = 'UTF8';

SELECT '【Step 2】データベース・スキーマ・ステージの作成が完了しました' AS status;


-- ============================================================================
-- Step 3: GitHub 連携の設定
-- ============================================================================

CREATE OR REPLACE API INTEGRATION git_api_integration_snowlife
    API_PROVIDER         = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-kmotokubota/')
    ENABLED              = TRUE
    COMMENT              = '法人営業 AI ハンズオン用の GitHub API 統合';

CREATE OR REPLACE GIT REPOSITORY SNOWLIFE_HANDSON_REPO
    API_INTEGRATION = git_api_integration_snowlife
    ORIGIN          = 'https://github.com/sfc-gh-kmotokubota/snowlife-app-handson.git'
    COMMENT         = 'ハンズオン教材リポジトリ';

ALTER GIT REPOSITORY SNOWLIFE_HANDSON_REPO FETCH;

SELECT '【Step 3】GitHub 連携の設定が完了しました' AS status;


-- ============================================================================
-- Step 4: GitHub からファイルをステージへ搬入
-- ============================================================================

COPY FILES INTO @DATA_STAGE
    FROM @SNOWLIFE_HANDSON_REPO/branches/main/data/csv/;

-- サブフォルダ（product/ meeting/）の構造を保ったままコピーされます
COPY FILES INTO @DOC_STAGE
    FROM @SNOWLIFE_HANDSON_REPO/branches/main/data/docs/;
ALTER STAGE DOC_STAGE REFRESH;

-- 結果として @AI.SKILL_STAGE/skills/<スキル名>/SKILL.md の階層になります
COPY FILES INTO @SNOWLIFE_HANDSON_DB.AI.SKILL_STAGE/skills/
    FROM @SNOWLIFE_HANDSON_REPO/branches/main/skills/;
ALTER STAGE SNOWLIFE_HANDSON_DB.AI.SKILL_STAGE REFRESH;

LS @DOC_STAGE;

SELECT '【Step 4】ファイルのステージ搬入が完了しました' AS status;


-- ============================================================================
-- Step 5: CRM・外部データのテーブル作成とロード（RAW）
-- ============================================================================
-- ソースシステムの列名をそのまま取り込んでいます（STAGE_CD, AMT_EST, RANK_FLG など）。
-- 列の意味やコード値の説明はあえて付けていません。
-- Part 2 でセマンティックビューを作り、ここに業務上の意味を与えます。
-- ============================================================================

CREATE OR REPLACE TABLE SF_BRANCH (BR_CD VARCHAR(3), BR_NM VARCHAR(50));
CREATE OR REPLACE TABLE SF_USER (OWNER_ID VARCHAR(4), USR_NM VARCHAR(50), BR_CD VARCHAR(3), TITLE VARCHAR(30));
CREATE OR REPLACE TABLE MST_INDUSTRY (IND_CD VARCHAR(3), IND_NM VARCHAR(30));
CREATE OR REPLACE TABLE MST_PRODUCT (PRD_CD VARCHAR(3), PRD_NM VARCHAR(100), PRD_CAT VARCHAR(30), PRD_DESC VARCHAR(500));
CREATE OR REPLACE TABLE MST_STAGE (STAGE_CD VARCHAR(2), STAGE_NM VARCHAR(20));

CREATE OR REPLACE TABLE SF_ACCOUNT (
    ACCT_ID    VARCHAR(4),
    ACCT_NM    VARCHAR(100),
    IND_CD     VARCHAR(3),
    EMP_CNT    NUMBER(9,0),
    HQ_PREF    VARCHAR(10),
    BR_CD      VARCHAR(3),
    OWNER_ID   VARCHAR(4),
    SEC_CD     VARCHAR(4),
    HOJIN_NO   VARCHAR(13),
    LISTED_FLG VARCHAR(1)
);

CREATE OR REPLACE TABLE SF_OPPORTUNITY (
    OPP_ID   VARCHAR(5),
    ACCT_ID  VARCHAR(4),
    PRD_CD   VARCHAR(3),
    STAGE_CD VARCHAR(2),
    RANK_FLG VARCHAR(1),
    AMT_EST  NUMBER(12,0),
    CRT_DT   DATE,
    CLOSE_DT DATE,
    OWNER_ID VARCHAR(4)
);

CREATE OR REPLACE TABLE SF_ACTIVITY (
    ACT_ID   VARCHAR(8),
    ACCT_ID  VARCHAR(4),
    OWNER_ID VARCHAR(4),
    ACT_DT   DATE,
    ACT_TYP  VARCHAR(1),
    SUBJ     VARCHAR(200)
);

CREATE OR REPLACE TABLE SF_CONTRACT (
    CNT_ID   VARCHAR(5),
    ACCT_ID  VARCHAR(4),
    PRD_CD   VARCHAR(3),
    STS_CD   VARCHAR(1),
    START_DT DATE,
    END_DT   DATE,
    ANN_PREM NUMBER(14,0),
    INS_CNT  NUMBER(9,0),
    OWNER_ID VARCHAR(4)
);

CREATE OR REPLACE TABLE EXT_JOB_POSTINGS (
    HOJIN_NO    VARCHAR(13),
    POST_MONTH  DATE,
    POSTING_CNT NUMBER(9,0)
);

CREATE OR REPLACE TABLE MEETING_NOTES (
    NOTE_ID   VARCHAR(6),
    ACCT_ID   VARCHAR(4),
    ACCT_NM   VARCHAR(100),
    OWNER_ID  VARCHAR(4),
    NOTE_DT   DATE,
    TOPIC     VARCHAR(30),
    NOTE_TEXT VARCHAR
);

COPY INTO SF_BRANCH        FROM @DATA_STAGE/sf_branch.csv        FILE_FORMAT = (FORMAT_NAME = CSV_FF);
COPY INTO SF_USER          FROM @DATA_STAGE/sf_user.csv          FILE_FORMAT = (FORMAT_NAME = CSV_FF);
COPY INTO MST_INDUSTRY     FROM @DATA_STAGE/mst_industry.csv     FILE_FORMAT = (FORMAT_NAME = CSV_FF);
COPY INTO MST_PRODUCT      FROM @DATA_STAGE/mst_product.csv      FILE_FORMAT = (FORMAT_NAME = CSV_FF);
COPY INTO MST_STAGE        FROM @DATA_STAGE/mst_stage.csv        FILE_FORMAT = (FORMAT_NAME = CSV_FF);
COPY INTO SF_ACCOUNT       FROM @DATA_STAGE/sf_account.csv       FILE_FORMAT = (FORMAT_NAME = CSV_FF);
COPY INTO SF_OPPORTUNITY   FROM @DATA_STAGE/sf_opportunity.csv   FILE_FORMAT = (FORMAT_NAME = CSV_FF);
COPY INTO SF_ACTIVITY      FROM @DATA_STAGE/sf_activity.csv      FILE_FORMAT = (FORMAT_NAME = CSV_FF);
COPY INTO SF_CONTRACT      FROM @DATA_STAGE/sf_contract.csv      FILE_FORMAT = (FORMAT_NAME = CSV_FF);
COPY INTO EXT_JOB_POSTINGS FROM @DATA_STAGE/ext_job_postings.csv FILE_FORMAT = (FORMAT_NAME = CSV_FF);
COPY INTO MEETING_NOTES    FROM @DATA_STAGE/meeting_notes.csv    FILE_FORMAT = (FORMAT_NAME = CSV_FF);

SELECT '【Step 5】CRM・外部データのロードが完了しました' AS status;


-- ============================================================================
-- Step 6: 財務企画部データのロード（別データベース）
-- ============================================================================
-- 財務企画部が管理する企業財務データです。キーは証券コード（SEC_CD）で、
-- CRM の取引先 ID とは体系が異なります。本番ではデータ共有（Secure Data Sharing）で
-- 受け取る想定ですが、ハンズオンでは同じアカウント内の別データベースで代用します。
-- ============================================================================

CREATE DATABASE IF NOT EXISTS FINANCE_PLANNING_DB
    COMMENT = '財務企画部（架空）の企業財務データ。ハンズオンではデータ共有の代わりに別DBで再現';
CREATE SCHEMA IF NOT EXISTS FINANCE_PLANNING_DB.CORP;

CREATE OR REPLACE TABLE FINANCE_PLANNING_DB.CORP.COMPANY_PL (
    SEC_CD         VARCHAR(4),
    FISCAL_YEAR    NUMBER(4,0),
    REVENUE_MJPY   NUMBER(12,0),
    OP_PROFIT_MJPY NUMBER(12,0),
    EMP_CNT        NUMBER(9,0)
);

COPY INTO FINANCE_PLANNING_DB.CORP.COMPANY_PL
    FROM @SNOWLIFE_HANDSON_DB.RAW.DATA_STAGE/fin_company_pl.csv
    FILE_FORMAT = (FORMAT_NAME = SNOWLIFE_HANDSON_DB.RAW.CSV_FF);

SELECT '【Step 6】財務企画部データのロードが完了しました' AS status;


-- ============================================================================
-- Step 7: データマートの作成（MART）
-- ============================================================================
-- キー体系の違う他部署・外部データを、CRM の取引先 ID（ACCT_ID）で引けるように整えます。
-- ============================================================================

USE SCHEMA SNOWLIFE_HANDSON_DB.MART;

CREATE OR REPLACE VIEW V_COMPANY_FINANCIALS AS
SELECT a.ACCT_ID,
       p.FISCAL_YEAR,
       p.REVENUE_MJPY,
       p.OP_PROFIT_MJPY,
       p.EMP_CNT
FROM FINANCE_PLANNING_DB.CORP.COMPANY_PL p
JOIN SNOWLIFE_HANDSON_DB.RAW.SF_ACCOUNT a ON a.SEC_CD = p.SEC_CD;

CREATE OR REPLACE VIEW V_JOB_POSTINGS AS
SELECT a.ACCT_ID,
       j.POST_MONTH,
       j.POSTING_CNT
FROM SNOWLIFE_HANDSON_DB.RAW.EXT_JOB_POSTINGS j
JOIN SNOWLIFE_HANDSON_DB.RAW.SF_ACCOUNT a ON a.HOJIN_NO = j.HOJIN_NO;

SELECT '【Step 7】データマートの作成が完了しました' AS status;


-- ============================================================================
-- Step 8: 商品資料 PDF の構造化と Cortex Search の作成（AI）
-- ============================================================================

USE SCHEMA SNOWLIFE_HANDSON_DB.AI;

-- 8-1. 商品パンフレット・約款 PDF をテキスト化してチャンクに分割する
--      （Part 1 では面談記録 PDF で同じ処理を体験します）
CREATE OR REPLACE TABLE PRODUCT_DOC_CHUNKS AS
WITH parsed AS (
    SELECT RELATIVE_PATH,
           AI_PARSE_DOCUMENT(
               TO_FILE('@SNOWLIFE_HANDSON_DB.RAW.DOC_STAGE', RELATIVE_PATH),
               {'mode': 'LAYOUT'}
           ):content::VARCHAR AS CONTENT
    FROM DIRECTORY(@SNOWLIFE_HANDSON_DB.RAW.DOC_STAGE)
    WHERE RELATIVE_PATH LIKE 'product/%'
)
SELECT p.RELATIVE_PATH,
       c.INDEX  AS CHUNK_NO,
       c.VALUE::VARCHAR AS CHUNK_TEXT
FROM parsed p,
     LATERAL FLATTEN(INPUT => SNOWFLAKE.CORTEX.SPLIT_TEXT_RECURSIVE_CHARACTER(p.CONTENT, 'markdown', 800, 100)) c;

-- 8-2. 商品資料の検索サービス
CREATE OR REPLACE CORTEX SEARCH SERVICE PRODUCT_DOC_SEARCH
    ON CHUNK_TEXT
    ATTRIBUTES RELATIVE_PATH
    WAREHOUSE  = SNOWLIFE_HANDSON_WH
    TARGET_LAG = '1 day'
    EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
AS SELECT CHUNK_TEXT, RELATIVE_PATH, CHUNK_NO FROM PRODUCT_DOC_CHUNKS;

-- 8-3. 面談メモの検索サービス
CREATE OR REPLACE CORTEX SEARCH SERVICE MEETING_NOTE_SEARCH
    ON NOTE_TEXT
    ATTRIBUTES ACCT_NM, TOPIC
    WAREHOUSE  = SNOWLIFE_HANDSON_WH
    TARGET_LAG = '1 day'
    EMBEDDING_MODEL = 'snowflake-arctic-embed-l-v2.0'
AS SELECT NOTE_TEXT, NOTE_ID, ACCT_ID, ACCT_NM, OWNER_ID, NOTE_DT, TOPIC
   FROM SNOWLIFE_HANDSON_DB.RAW.MEETING_NOTES;

SELECT '【Step 8】PDF の構造化と Cortex Search の作成が完了しました' AS status;


-- ============================================================================
-- Step 9: 比較用の最小セマンティックビュー（AI.SV_SALES_MINIMAL）
-- ============================================================================
-- テーブル・主キー・リレーションだけを定義し、説明・同義語・指標・コード値の意味は
-- 一切付けていません。Part 3 で「意味づけのないセマンティックビュー」を使う
-- Agent と、受講者が Part 2 で作るセマンティックビューを使う Agent を比べます。
-- ============================================================================

CREATE OR REPLACE SEMANTIC VIEW SV_SALES_MINIMAL
    TABLES (
        SF_ACCOUNT     AS SNOWLIFE_HANDSON_DB.RAW.SF_ACCOUNT     PRIMARY KEY (ACCT_ID),
        SF_OPPORTUNITY AS SNOWLIFE_HANDSON_DB.RAW.SF_OPPORTUNITY PRIMARY KEY (OPP_ID),
        SF_ACTIVITY    AS SNOWLIFE_HANDSON_DB.RAW.SF_ACTIVITY    PRIMARY KEY (ACT_ID),
        SF_CONTRACT    AS SNOWLIFE_HANDSON_DB.RAW.SF_CONTRACT    PRIMARY KEY (CNT_ID),
        SF_USER        AS SNOWLIFE_HANDSON_DB.RAW.SF_USER        PRIMARY KEY (OWNER_ID),
        V_COMPANY_FINANCIALS AS SNOWLIFE_HANDSON_DB.MART.V_COMPANY_FINANCIALS PRIMARY KEY (ACCT_ID, FISCAL_YEAR),
        V_JOB_POSTINGS       AS SNOWLIFE_HANDSON_DB.MART.V_JOB_POSTINGS       PRIMARY KEY (ACCT_ID, POST_MONTH)
    )
    RELATIONSHIPS (
        OPP_TO_ACCOUNT  AS SF_OPPORTUNITY (ACCT_ID)       REFERENCES SF_ACCOUNT,
        ACT_TO_ACCOUNT  AS SF_ACTIVITY (ACCT_ID)          REFERENCES SF_ACCOUNT,
        CNT_TO_ACCOUNT  AS SF_CONTRACT (ACCT_ID)          REFERENCES SF_ACCOUNT,
        ACCT_TO_USER    AS SF_ACCOUNT (OWNER_ID)          REFERENCES SF_USER,
        FIN_TO_ACCOUNT  AS V_COMPANY_FINANCIALS (ACCT_ID) REFERENCES SF_ACCOUNT,
        JOB_TO_ACCOUNT  AS V_JOB_POSTINGS (ACCT_ID)       REFERENCES SF_ACCOUNT
    )
    FACTS (
        SF_ACCOUNT.EMP_CNT             AS EMP_CNT,
        SF_OPPORTUNITY.AMT_EST         AS AMT_EST,
        SF_CONTRACT.ANN_PREM           AS ANN_PREM,
        SF_CONTRACT.INS_CNT            AS INS_CNT,
        V_COMPANY_FINANCIALS.REVENUE_MJPY   AS REVENUE_MJPY,
        V_COMPANY_FINANCIALS.OP_PROFIT_MJPY AS OP_PROFIT_MJPY,
        V_JOB_POSTINGS.POSTING_CNT     AS POSTING_CNT
    )
    DIMENSIONS (
        SF_ACCOUNT.ACCT_ID      AS ACCT_ID,
        SF_ACCOUNT.ACCT_NM      AS ACCT_NM,
        SF_ACCOUNT.IND_CD       AS IND_CD,
        SF_ACCOUNT.HQ_PREF      AS HQ_PREF,
        SF_ACCOUNT.BR_CD        AS BR_CD,
        SF_ACCOUNT.LISTED_FLG   AS LISTED_FLG,
        SF_OPPORTUNITY.OPP_ID   AS OPP_ID,
        SF_OPPORTUNITY.OPP_PRD_CD AS PRD_CD,
        SF_OPPORTUNITY.STAGE_CD AS STAGE_CD,
        SF_OPPORTUNITY.RANK_FLG AS RANK_FLG,
        SF_OPPORTUNITY.CRT_DT   AS CRT_DT,
        SF_OPPORTUNITY.CLOSE_DT AS CLOSE_DT,
        SF_ACTIVITY.ACT_ID      AS ACT_ID,
        SF_ACTIVITY.ACT_DT      AS ACT_DT,
        SF_ACTIVITY.ACT_TYP     AS ACT_TYP,
        SF_ACTIVITY.SUBJ        AS SUBJ,
        SF_CONTRACT.CNT_ID      AS CNT_ID,
        SF_CONTRACT.CNT_PRD_CD  AS PRD_CD,
        SF_CONTRACT.STS_CD      AS STS_CD,
        SF_CONTRACT.START_DT    AS START_DT,
        SF_USER.OWNER_ID        AS OWNER_ID,
        SF_USER.USR_NM          AS USR_NM,
        V_COMPANY_FINANCIALS.FISCAL_YEAR AS FISCAL_YEAR,
        V_JOB_POSTINGS.POST_MONTH        AS POST_MONTH
    );

SELECT '【Step 9】比較用の最小セマンティックビューの作成が完了しました' AS status;


-- ============================================================================
-- Step 10: 営業職員ロールと行アクセスポリシー（SECURITY）
-- ============================================================================
-- 東京第一法人営業部（T01）の営業職員ロールを作り、担当支社の取引先だけが
-- 見えるようにします。Part 5 で CoWork から確認します。
--
-- ポリシーは CURRENT_ROLE() で判定します。CoWork と Cortex Agent はユーザーの
-- デフォルトロールでセッションを開始するため、デフォルトロールを営業職員ロールに
-- 切り替えると、その権限で回答が返るようになります。
-- ============================================================================

USE SCHEMA SNOWLIFE_HANDSON_DB.SECURITY;

CREATE ROLE IF NOT EXISTS SNOWLIFE_SALES_REP_T01
    COMMENT = 'スノー生命 東京第一法人営業部の営業職員ロール（ハンズオン用）';

-- ロールと支社の対応表
CREATE OR REPLACE TABLE ROLE_BRANCH_MAP (ROLE_NAME VARCHAR, BR_CD VARCHAR(3));
INSERT INTO ROLE_BRANCH_MAP VALUES ('SNOWLIFE_SALES_REP_T01', 'T01');

-- 取引先と支社の対応表（ポリシーの中から参照するため、保護対象とは別に持つ）
CREATE OR REPLACE TABLE ACCT_BRANCH_MAP AS
SELECT ACCT_ID, BR_CD FROM SNOWLIFE_HANDSON_DB.RAW.SF_ACCOUNT;

CREATE OR REPLACE ROW ACCESS POLICY RAP_BY_BRANCH
AS (P_ACCT_ID VARCHAR) RETURNS BOOLEAN ->
    -- 営業職員ロール以外（ACCOUNTADMIN など本部側）はすべて見える
    NOT EXISTS (SELECT 1 FROM SNOWLIFE_HANDSON_DB.SECURITY.ROLE_BRANCH_MAP r
                WHERE r.ROLE_NAME = CURRENT_ROLE())
    -- 営業職員ロールは担当支社の取引先だけ見える
    OR EXISTS (SELECT 1
               FROM SNOWLIFE_HANDSON_DB.SECURITY.ACCT_BRANCH_MAP a
               JOIN SNOWLIFE_HANDSON_DB.SECURITY.ROLE_BRANCH_MAP r ON a.BR_CD = r.BR_CD
               WHERE a.ACCT_ID = P_ACCT_ID
                 AND r.ROLE_NAME = CURRENT_ROLE());

ALTER TABLE SNOWLIFE_HANDSON_DB.RAW.SF_ACCOUNT     ADD ROW ACCESS POLICY RAP_BY_BRANCH ON (ACCT_ID);
ALTER TABLE SNOWLIFE_HANDSON_DB.RAW.SF_OPPORTUNITY ADD ROW ACCESS POLICY RAP_BY_BRANCH ON (ACCT_ID);
ALTER TABLE SNOWLIFE_HANDSON_DB.RAW.SF_ACTIVITY    ADD ROW ACCESS POLICY RAP_BY_BRANCH ON (ACCT_ID);
ALTER TABLE SNOWLIFE_HANDSON_DB.RAW.SF_CONTRACT    ADD ROW ACCESS POLICY RAP_BY_BRANCH ON (ACCT_ID);

-- 営業職員ロールに必要な権限
GRANT USAGE ON WAREHOUSE SNOWLIFE_HANDSON_WH TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT USAGE ON DATABASE SNOWLIFE_HANDSON_DB TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT USAGE ON SCHEMA SNOWLIFE_HANDSON_DB.RAW  TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT USAGE ON SCHEMA SNOWLIFE_HANDSON_DB.MART TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT USAGE ON SCHEMA SNOWLIFE_HANDSON_DB.AI   TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT SELECT ON ALL TABLES IN SCHEMA SNOWLIFE_HANDSON_DB.RAW TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT SELECT ON ALL VIEWS  IN SCHEMA SNOWLIFE_HANDSON_DB.MART TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT SELECT ON FUTURE SEMANTIC VIEWS IN SCHEMA SNOWLIFE_HANDSON_DB.AI TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT USAGE  ON FUTURE AGENTS IN SCHEMA SNOWLIFE_HANDSON_DB.AI TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT SELECT ON SEMANTIC VIEW SNOWLIFE_HANDSON_DB.AI.SV_SALES_MINIMAL TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT USAGE ON CORTEX SEARCH SERVICE SNOWLIFE_HANDSON_DB.AI.PRODUCT_DOC_SEARCH  TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT USAGE ON CORTEX SEARCH SERVICE SNOWLIFE_HANDSON_DB.AI.MEETING_NOTE_SEARCH TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT READ ON STAGE SNOWLIFE_HANDSON_DB.RAW.DOC_STAGE   TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT READ ON STAGE SNOWLIFE_HANDSON_DB.AI.SKILL_STAGE  TO ROLE SNOWLIFE_SALES_REP_T01;
-- MART のビューは FINANCE_PLANNING_DB を参照するため、そちらの参照権限も付与します
GRANT USAGE ON DATABASE FINANCE_PLANNING_DB TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT USAGE ON SCHEMA FINANCE_PLANNING_DB.CORP TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT SELECT ON ALL TABLES IN SCHEMA FINANCE_PLANNING_DB.CORP TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_AGENT_USER TO ROLE SNOWLIFE_SALES_REP_T01;

-- 受講者自身がこのロールを使えるようにします（Part 5 で使用）
EXECUTE IMMEDIATE $$
BEGIN
    EXECUTE IMMEDIATE 'GRANT ROLE SNOWLIFE_SALES_REP_T01 TO USER "' || CURRENT_USER() || '"';
    RETURN 'SNOWLIFE_SALES_REP_T01 を ' || CURRENT_USER() || ' に付与しました';
END;
$$;

SELECT '【Step 10】営業職員ロールと行アクセスポリシーの設定が完了しました' AS status;


-- ============================================================================
-- Step 11: Snowflake CoWork オブジェクトの作成
-- ============================================================================
-- CoWork オブジェクトがあるアカウントでは、Agent をこのオブジェクトに追加しないと
-- CoWork に表示されません（Part 3 で追加します）。
-- ============================================================================

CREATE SNOWFLAKE INTELLIGENCE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;
GRANT USAGE ON SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT TO ROLE SNOWLIFE_SALES_REP_T01;

SELECT '【Step 11】Snowflake CoWork オブジェクトの作成が完了しました' AS status;


-- ============================================================================
-- 件数確認
-- ============================================================================

USE SCHEMA SNOWLIFE_HANDSON_DB.RAW;

SELECT 'SF_ACCOUNT'       AS "テーブル", COUNT(*) AS "件数", '取引先（顧客企業）'   AS "内容" FROM SF_ACCOUNT
UNION ALL SELECT 'SF_OPPORTUNITY',   COUNT(*), '商談（見込み）'                    FROM SF_OPPORTUNITY
UNION ALL SELECT 'SF_ACTIVITY',      COUNT(*), '活動履歴'                          FROM SF_ACTIVITY
UNION ALL SELECT 'SF_CONTRACT',      COUNT(*), '既契約'                            FROM SF_CONTRACT
UNION ALL SELECT 'MEETING_NOTES',    COUNT(*), '面談メモ'                          FROM MEETING_NOTES
UNION ALL SELECT 'EXT_JOB_POSTINGS', COUNT(*), '求人件数（外部データ）'            FROM EXT_JOB_POSTINGS
UNION ALL SELECT 'COMPANY_PL',       COUNT(*), '企業財務（財務企画部）'            FROM FINANCE_PLANNING_DB.CORP.COMPANY_PL
UNION ALL SELECT 'PRODUCT_DOC_CHUNKS', COUNT(*), '商品資料チャンク'                FROM SNOWLIFE_HANDSON_DB.AI.PRODUCT_DOC_CHUNKS
ORDER BY 1;


-- ============================================================================
-- セットアップ完了
-- ============================================================================

SELECT '【基盤】データ・Cortex Search・営業職員ロールの作成が完了しました' AS status;


-- ################################################################################
-- sql/02_semantic_view.sql: セマンティックビュー AI.SV_SALES_ANALYTICS
-- ################################################################################

/*
================================================================================
Part 2 答え合わせ: セマンティックビュー AI.SV_SALES_ANALYTICS を作成する
================================================================================
Semantic Studio での作成が間に合わなかった場合に実行してください。
内容は answers/part2_semantic_view.yaml と同じです（tools/build_answers.py で生成）。

Semantic Studio で使う場合は、YAML ファイルの中身を .sv.yaml に貼り付けて Deploy しても
同じ結果になります。
================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWLIFE_HANDSON_WH;

-- 1. 作成前に検証だけ行う（第3引数 TRUE）
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
    'SNOWLIFE_HANDSON_DB.AI',
    $$name: SV_SALES_ANALYTICS
description: >-
  スノー生命 法人営業の分析用セマンティックビュー。取引先（顧客企業）、商談（見込み）、活動履歴（訪問・面談）、
  既契約、営業担当、財務企画部の企業財務、外部の求人件数をつないで、見込み金額・受注・訪問状況・既契約保険料・
  顧客企業の業績変化を分析できる。法人営業職員と営業企画部が、訪問先の優先順位付けや提案準備に使う。

tables:
  # ------------------------------------------------------------------
  - name: ACCOUNTS
    description: 取引先（顧客企業）マスタ。1行が1社。担当支社と担当営業を持つ。
    synonyms: [取引先, 顧客, 顧客企業, 法人顧客, 企業]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: SF_ACCOUNT}
    primary_key: {columns: [ACCT_ID]}
    dimensions:
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
        description: 取引先ID（A001 形式）
      - name: ACCOUNT_NAME
        expr: ACCT_NM
        data_type: VARCHAR
        description: 取引先名（正式名称。「(株)」を含む）。部分一致で検索すること。
        synonyms: [企業名, 会社名, 顧客名, 取引先名]
        sample_values: [KDDI(株), トヨタ自動車(株), 伊藤忠商事(株)]
      - name: INDUSTRY
        expr: CASE IND_CD WHEN 'MFG' THEN '製造業' WHEN 'TRD' THEN '商社' WHEN 'ITC' THEN '情報通信業' WHEN 'FIN' THEN '金融業' WHEN 'ENE' THEN '電気・ガス業' WHEN 'RTL' THEN '小売業' WHEN 'CON' THEN '建設業' WHEN 'TRN' THEN '運輸業' WHEN 'RES' THEN '不動産業' END
        data_type: VARCHAR
        description: 業種（日本語名）
        synonyms: [業種, 業界]
        sample_values: [製造業, 商社, 情報通信業, 金融業, 運輸業]
      - name: HQ_PREFECTURE
        expr: HQ_PREF
        data_type: VARCHAR
        description: 本社所在地の都道府県
        synonyms: [本社所在地, 都道府県]
      - name: BRANCH_NAME
        expr: CASE BR_CD WHEN 'T01' THEN '東京第一法人営業部' WHEN 'T02' THEN '東京第二法人営業部' WHEN 'K01' THEN '関西法人営業部' WHEN 'C01' THEN '中部法人営業部' END
        data_type: VARCHAR
        description: 取引先を担当する支社（法人営業部）の名称
        synonyms: [支社, 担当支社, 営業部, 部店]
        sample_values: [東京第一法人営業部, 東京第二法人営業部, 関西法人営業部, 中部法人営業部]
      - name: OWNER_ID
        expr: OWNER_ID
        data_type: VARCHAR
        description: 担当営業のID
      - name: IS_LISTED
        expr: LISTED_FLG = '1'
        data_type: BOOLEAN
        description: 上場企業なら TRUE
        synonyms: [上場, 上場企業]
    facts:
      - name: EMPLOYEE_COUNT
        expr: EMP_CNT
        data_type: NUMBER
        description: 従業員数（連結、人）
        synonyms: [従業員数, 社員数, 従業員規模]
    metrics:
      - name: ACCOUNT_COUNT
        expr: COUNT(DISTINCT ACCT_ID)
        description: 取引先の社数
        synonyms: [社数, 企業数, 顧客数]

  # ------------------------------------------------------------------
  - name: OPPORTUNITIES
    description: >-
      商談（見込み）。1行が1つの商談。見込み金額は年換算保険料の見込み。
      進行中の商談は商談ステージが「受注」「失注」以外のもの。
    synonyms: [商談, 見込み, 案件, パイプライン]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: SF_OPPORTUNITY}
    primary_key: {columns: [OPP_ID]}
    dimensions:
      - name: OPP_ID
        expr: OPP_ID
        data_type: VARCHAR
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
      - name: OPP_PRODUCT_CODE
        expr: PRD_CD
        data_type: VARCHAR
        description: 商談の対象商品コード（PRODUCTS と結合）
      - name: STAGE_NAME
        expr: CASE STAGE_CD WHEN '10' THEN '初回提案' WHEN '20' THEN 'ニーズ確認' WHEN '30' THEN '提案中' WHEN '40' THEN '最終交渉' WHEN '90' THEN '受注' WHEN '99' THEN '失注' END
        data_type: VARCHAR
        description: 商談ステージ。受注 = 成約、失注 = 不成立。
        synonyms: [商談ステージ, 進捗, ステータス]
        sample_values: [初回提案, ニーズ確認, 提案中, 最終交渉, 受注, 失注]
      - name: IS_OPEN
        expr: STAGE_CD NOT IN ('90', '99')
        data_type: BOOLEAN
        description: 進行中（未クローズ）の商談なら TRUE。受注・失注は FALSE。
        synonyms: [進行中, 未クローズ, オープン]
      - name: PROSPECT_RANK
        expr: RANK_FLG
        data_type: VARCHAR
        description: 見込みランク。S（確度最高）> A > B > C の順。「Aランク」は RANK_FLG = 'A'。
        synonyms: [見込みランク, ランク, 確度]
        sample_values: [S, A, B, C]
      - name: OPP_OWNER_ID
        expr: OWNER_ID
        data_type: VARCHAR
    time_dimensions:
      - name: CREATED_DATE
        expr: CRT_DT
        data_type: DATE
        description: 商談の作成日
      - name: CLOSE_DATE
        expr: CLOSE_DT
        data_type: DATE
        description: 完了日。受注・失注の商談では実際の完了日、進行中の商談では完了予定日。
        synonyms: [完了予定日, 受注日, 成約日]
      - name: CLOSE_FISCAL_YEAR
        expr: CASE WHEN MONTH(CLOSE_DT) >= 4 THEN YEAR(CLOSE_DT) ELSE YEAR(CLOSE_DT) - 1 END
        data_type: NUMBER
        description: 完了日の年度（4月始まり）。2026年度 = 2026-04-01〜2027-03-31。
        synonyms: [年度, 完了年度]
    facts:
      - name: EXPECTED_PREMIUM_JPY
        expr: AMT_EST * 1000
        data_type: NUMBER
        description: 見込み金額（年換算保険料、円）。元データは千円単位のため 1000 倍している。
        synonyms: [見込み金額, 見込み保険料, 商談金額]
    metrics:
      - name: TOTAL_EXPECTED_PREMIUM_JPY
        expr: SUM(AMT_EST * 1000)
        description: 見込み金額の合計（円）
        synonyms: [見込み金額合計, パイプライン金額]
      - name: OPPORTUNITY_COUNT
        expr: COUNT(DISTINCT OPP_ID)
        description: 商談の件数
        synonyms: [商談件数, 見込み件数, 案件数]
    filters:
      - name: OPEN_OPPORTUNITIES
        expr: STAGE_CD NOT IN ('90', '99')
        description: 進行中（受注・失注以外）の商談
        synonyms: [進行中の商談]
      - name: WON_OPPORTUNITIES
        expr: STAGE_CD = '90'
        description: 受注した商談
        synonyms: [受注案件, 成約案件]

  # ------------------------------------------------------------------
  - name: ACTIVITIES
    description: 活動履歴。1行が1回の訪問・オンライン面談・電話。
    synonyms: [活動, 訪問履歴, 面談履歴, コンタクト]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: SF_ACTIVITY}
    primary_key: {columns: [ACT_ID]}
    dimensions:
      - name: ACT_ID
        expr: ACT_ID
        data_type: VARCHAR
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
      - name: ACT_OWNER_ID
        expr: OWNER_ID
        data_type: VARCHAR
      - name: ACTIVITY_TYPE
        expr: CASE ACT_TYP WHEN 'V' THEN '訪問' WHEN 'O' THEN 'オンライン面談' WHEN 'T' THEN '電話' END
        data_type: VARCHAR
        description: 活動種別。「訪問」は対面での訪問のみ（オンライン面談・電話は含まない）。
        synonyms: [活動種別, 接点種別]
        sample_values: [訪問, オンライン面談, 電話]
      - name: SUBJECT
        expr: SUBJ
        data_type: VARCHAR
        description: 活動の件名
    time_dimensions:
      - name: ACTIVITY_DATE
        expr: ACT_DT
        data_type: DATE
        description: 活動日
        synonyms: [訪問日, 面談日]
      - name: ACTIVITY_FISCAL_YEAR
        expr: CASE WHEN MONTH(ACT_DT) >= 4 THEN YEAR(ACT_DT) ELSE YEAR(ACT_DT) - 1 END
        data_type: NUMBER
        description: 活動日の年度（4月始まり）
    metrics:
      - name: ACTIVITY_COUNT
        expr: COUNT(DISTINCT ACT_ID)
        description: 活動件数（全種別）
      - name: VISIT_COUNT
        expr: COUNT(DISTINCT CASE WHEN ACT_TYP = 'V' THEN ACT_ID END)
        description: 訪問件数（対面の訪問のみ）
        synonyms: [訪問件数, 訪問回数]
      - name: LAST_VISIT_DATE
        expr: MAX(CASE WHEN ACT_TYP = 'V' THEN ACT_DT END)
        description: 最終訪問日（対面の訪問のみ）
        synonyms: [最終訪問日, 直近の訪問日]

  # ------------------------------------------------------------------
  - name: CONTRACTS
    description: 既契約（保有契約）。1行が1契約。年間保険料は円単位。有効な契約は契約状態が「有効」のもの。
    synonyms: [既契約, 保有契約, 契約]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: SF_CONTRACT}
    primary_key: {columns: [CNT_ID]}
    dimensions:
      - name: CNT_ID
        expr: CNT_ID
        data_type: VARCHAR
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
      - name: CONTRACT_PRODUCT_CODE
        expr: PRD_CD
        data_type: VARCHAR
        description: 契約商品コード（PRODUCTS と結合）
      - name: CONTRACT_STATUS
        expr: CASE STS_CD WHEN '1' THEN '有効' WHEN '9' THEN '解約' END
        data_type: VARCHAR
        description: 契約状態。有効 = 現在保有中、解約 = 解約済み。
        synonyms: [契約状態, ステータス]
        sample_values: [有効, 解約]
    time_dimensions:
      - name: CONTRACT_START_DATE
        expr: START_DT
        data_type: DATE
        description: 契約開始日
    facts:
      - name: ANNUAL_PREMIUM_JPY
        expr: ANN_PREM
        data_type: NUMBER
        description: 年間保険料（円）
        synonyms: [年間保険料, 保険料]
      - name: INSURED_COUNT
        expr: INS_CNT
        data_type: NUMBER
        description: 被保険者数（人）
        synonyms: [加入者数, 被保険者数]
    metrics:
      - name: ACTIVE_ANNUAL_PREMIUM_JPY
        expr: SUM(CASE WHEN STS_CD = '1' THEN ANN_PREM END)
        description: 有効な既契約の年間保険料合計（円）
        synonyms: [保有保険料, 既契約保険料]
      - name: ACTIVE_CONTRACT_COUNT
        expr: COUNT(DISTINCT CASE WHEN STS_CD = '1' THEN CNT_ID END)
        description: 有効な既契約の件数

  # ------------------------------------------------------------------
  - name: PRODUCTS
    description: 商品マスタ（保険商品と非保険サービス）
    synonyms: [商品, 保険商品]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: MST_PRODUCT}
    primary_key: {columns: [PRD_CD]}
    dimensions:
      - name: PRD_CD
        expr: PRD_CD
        data_type: VARCHAR
      - name: PRODUCT_NAME
        expr: PRD_NM
        data_type: VARCHAR
        description: 商品名
        synonyms: [商品名]
        sample_values: [総合福祉団体定期保険, 団体長期障害所得補償保険（GLTD）, 確定拠出年金（企業型DC）運営管理]
      - name: PRODUCT_CATEGORY
        expr: PRD_CAT
        data_type: VARCHAR
        description: 商品分類
        sample_values: [団体保障, 企業年金, 経営者保障, 非保険サービス]

  # ------------------------------------------------------------------
  - name: SALES_REPS
    description: 営業担当者
    synonyms: [営業担当, 担当者, 営業職員]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: SF_USER}
    primary_key: {columns: [OWNER_ID]}
    dimensions:
      - name: OWNER_ID
        expr: OWNER_ID
        data_type: VARCHAR
      - name: SALES_REP_NAME
        expr: USR_NM
        data_type: VARCHAR
        description: 営業担当者の氏名
        synonyms: [担当者名, 営業担当者名]

  # ------------------------------------------------------------------
  - name: FINANCIALS
    description: 財務企画部が管理する顧客企業の年度別業績（単位は百万円）。
    synonyms: [財務, 業績, 決算]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: MART, table: V_COMPANY_FINANCIALS}
    primary_key: {columns: [ACCT_ID, FISCAL_YEAR]}
    dimensions:
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
      - name: FISCAL_YEAR
        expr: FISCAL_YEAR
        data_type: NUMBER
        description: 顧客企業の決算年度（2023〜2025）
        synonyms: [決算年度]
    facts:
      - name: REVENUE_MJPY
        expr: REVENUE_MJPY
        data_type: NUMBER
        description: 売上高（百万円）
        synonyms: [売上高, 売上]
      - name: OPERATING_PROFIT_MJPY
        expr: OP_PROFIT_MJPY
        data_type: NUMBER
        description: 営業利益（百万円）
        synonyms: [営業利益]

  # ------------------------------------------------------------------
  - name: JOB_POSTINGS
    description: 外部データ。顧客企業の月次の求人掲載件数。採用強化の兆候をつかむために使う。
    synonyms: [求人, 求人件数, 採用動向]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: MART, table: V_JOB_POSTINGS}
    primary_key: {columns: [ACCT_ID, POST_MONTH]}
    dimensions:
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
    time_dimensions:
      - name: POST_MONTH
        expr: POST_MONTH
        data_type: DATE
        description: 求人を集計した月（月初日）
        synonyms: [掲載月]
    facts:
      - name: POSTING_COUNT
        expr: POSTING_CNT
        data_type: NUMBER
        description: 月間の求人掲載件数
        synonyms: [求人件数, 求人数]

relationships:
  - name: OPPORTUNITIES_TO_ACCOUNTS
    left_table: OPPORTUNITIES
    right_table: ACCOUNTS
    relationship_columns: [{left_column: ACCT_ID, right_column: ACCT_ID}]
  - name: ACTIVITIES_TO_ACCOUNTS
    left_table: ACTIVITIES
    right_table: ACCOUNTS
    relationship_columns: [{left_column: ACCT_ID, right_column: ACCT_ID}]
  - name: CONTRACTS_TO_ACCOUNTS
    left_table: CONTRACTS
    right_table: ACCOUNTS
    relationship_columns: [{left_column: ACCT_ID, right_column: ACCT_ID}]
  - name: FINANCIALS_TO_ACCOUNTS
    left_table: FINANCIALS
    right_table: ACCOUNTS
    relationship_columns: [{left_column: ACCT_ID, right_column: ACCT_ID}]
  - name: JOB_POSTINGS_TO_ACCOUNTS
    left_table: JOB_POSTINGS
    right_table: ACCOUNTS
    relationship_columns: [{left_column: ACCT_ID, right_column: ACCT_ID}]
  - name: ACCOUNTS_TO_SALES_REPS
    left_table: ACCOUNTS
    right_table: SALES_REPS
    relationship_columns: [{left_column: OWNER_ID, right_column: OWNER_ID}]
  - name: OPPORTUNITIES_TO_PRODUCTS
    left_table: OPPORTUNITIES
    right_table: PRODUCTS
    relationship_columns: [{left_column: OPP_PRODUCT_CODE, right_column: PRD_CD}]
  - name: CONTRACTS_TO_PRODUCTS
    left_table: CONTRACTS
    right_table: PRODUCTS
    relationship_columns: [{left_column: CONTRACT_PRODUCT_CODE, right_column: PRD_CD}]

module_custom_instructions:
  sql_generation: >-
    年度は4月始まりとする（例: 2026年度上期 = 2026-04-01〜2026-09-30）。
    金額は円単位で返す。見込み金額は EXPECTED_PREMIUM_JPY（AMT_EST * 1000）を使い、AMT_EST をそのまま金額として扱わない。
    「訪問」は ACTIVITY_TYPE = '訪問' のみを指し、オンライン面談や電話を含めない。
    取引先を一覧にするときは取引先名（ACCOUNT_NAME）を必ず含める。

verified_queries:
  - name: open_pipeline_by_rank
    question: 進行中の商談の見込みランク別の件数と見込み金額合計を教えて
    use_as_onboarding_question: true
    sql: |
      SELECT PROSPECT_RANK,
             COUNT(DISTINCT OPP_ID) AS OPPORTUNITY_COUNT,
             SUM(EXPECTED_PREMIUM_JPY) AS TOTAL_EXPECTED_PREMIUM_JPY
      FROM __OPPORTUNITIES
      WHERE IS_OPEN
      GROUP BY PROSPECT_RANK
      ORDER BY PROSPECT_RANK
  - name: visits_by_rep_fy2026_h1
    question: 2026年度上期の営業担当別の訪問件数を多い順に教えて
    use_as_onboarding_question: true
    sql: |
      SELECT r.SALES_REP_NAME,
             COUNT(DISTINCT a.ACT_ID) AS VISIT_COUNT
      FROM __ACTIVITIES a
      JOIN __ACCOUNTS acc ON a.ACCT_ID = acc.ACCT_ID
      JOIN __SALES_REPS r ON acc.OWNER_ID = r.OWNER_ID
      WHERE a.ACTIVITY_TYPE = '訪問'
        AND a.ACTIVITY_DATE BETWEEN '2026-04-01' AND '2026-09-30'
      GROUP BY r.SALES_REP_NAME
      ORDER BY VISIT_COUNT DESC
$$,
    TRUE
);

-- 2. 作成する
CALL SYSTEM$CREATE_SEMANTIC_VIEW_FROM_YAML(
    'SNOWLIFE_HANDSON_DB.AI',
    $$name: SV_SALES_ANALYTICS
description: >-
  スノー生命 法人営業の分析用セマンティックビュー。取引先（顧客企業）、商談（見込み）、活動履歴（訪問・面談）、
  既契約、営業担当、財務企画部の企業財務、外部の求人件数をつないで、見込み金額・受注・訪問状況・既契約保険料・
  顧客企業の業績変化を分析できる。法人営業職員と営業企画部が、訪問先の優先順位付けや提案準備に使う。

tables:
  # ------------------------------------------------------------------
  - name: ACCOUNTS
    description: 取引先（顧客企業）マスタ。1行が1社。担当支社と担当営業を持つ。
    synonyms: [取引先, 顧客, 顧客企業, 法人顧客, 企業]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: SF_ACCOUNT}
    primary_key: {columns: [ACCT_ID]}
    dimensions:
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
        description: 取引先ID（A001 形式）
      - name: ACCOUNT_NAME
        expr: ACCT_NM
        data_type: VARCHAR
        description: 取引先名（正式名称。「(株)」を含む）。部分一致で検索すること。
        synonyms: [企業名, 会社名, 顧客名, 取引先名]
        sample_values: [KDDI(株), トヨタ自動車(株), 伊藤忠商事(株)]
      - name: INDUSTRY
        expr: CASE IND_CD WHEN 'MFG' THEN '製造業' WHEN 'TRD' THEN '商社' WHEN 'ITC' THEN '情報通信業' WHEN 'FIN' THEN '金融業' WHEN 'ENE' THEN '電気・ガス業' WHEN 'RTL' THEN '小売業' WHEN 'CON' THEN '建設業' WHEN 'TRN' THEN '運輸業' WHEN 'RES' THEN '不動産業' END
        data_type: VARCHAR
        description: 業種（日本語名）
        synonyms: [業種, 業界]
        sample_values: [製造業, 商社, 情報通信業, 金融業, 運輸業]
      - name: HQ_PREFECTURE
        expr: HQ_PREF
        data_type: VARCHAR
        description: 本社所在地の都道府県
        synonyms: [本社所在地, 都道府県]
      - name: BRANCH_NAME
        expr: CASE BR_CD WHEN 'T01' THEN '東京第一法人営業部' WHEN 'T02' THEN '東京第二法人営業部' WHEN 'K01' THEN '関西法人営業部' WHEN 'C01' THEN '中部法人営業部' END
        data_type: VARCHAR
        description: 取引先を担当する支社（法人営業部）の名称
        synonyms: [支社, 担当支社, 営業部, 部店]
        sample_values: [東京第一法人営業部, 東京第二法人営業部, 関西法人営業部, 中部法人営業部]
      - name: OWNER_ID
        expr: OWNER_ID
        data_type: VARCHAR
        description: 担当営業のID
      - name: IS_LISTED
        expr: LISTED_FLG = '1'
        data_type: BOOLEAN
        description: 上場企業なら TRUE
        synonyms: [上場, 上場企業]
    facts:
      - name: EMPLOYEE_COUNT
        expr: EMP_CNT
        data_type: NUMBER
        description: 従業員数（連結、人）
        synonyms: [従業員数, 社員数, 従業員規模]
    metrics:
      - name: ACCOUNT_COUNT
        expr: COUNT(DISTINCT ACCT_ID)
        description: 取引先の社数
        synonyms: [社数, 企業数, 顧客数]

  # ------------------------------------------------------------------
  - name: OPPORTUNITIES
    description: >-
      商談（見込み）。1行が1つの商談。見込み金額は年換算保険料の見込み。
      進行中の商談は商談ステージが「受注」「失注」以外のもの。
    synonyms: [商談, 見込み, 案件, パイプライン]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: SF_OPPORTUNITY}
    primary_key: {columns: [OPP_ID]}
    dimensions:
      - name: OPP_ID
        expr: OPP_ID
        data_type: VARCHAR
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
      - name: OPP_PRODUCT_CODE
        expr: PRD_CD
        data_type: VARCHAR
        description: 商談の対象商品コード（PRODUCTS と結合）
      - name: STAGE_NAME
        expr: CASE STAGE_CD WHEN '10' THEN '初回提案' WHEN '20' THEN 'ニーズ確認' WHEN '30' THEN '提案中' WHEN '40' THEN '最終交渉' WHEN '90' THEN '受注' WHEN '99' THEN '失注' END
        data_type: VARCHAR
        description: 商談ステージ。受注 = 成約、失注 = 不成立。
        synonyms: [商談ステージ, 進捗, ステータス]
        sample_values: [初回提案, ニーズ確認, 提案中, 最終交渉, 受注, 失注]
      - name: IS_OPEN
        expr: STAGE_CD NOT IN ('90', '99')
        data_type: BOOLEAN
        description: 進行中（未クローズ）の商談なら TRUE。受注・失注は FALSE。
        synonyms: [進行中, 未クローズ, オープン]
      - name: PROSPECT_RANK
        expr: RANK_FLG
        data_type: VARCHAR
        description: 見込みランク。S（確度最高）> A > B > C の順。「Aランク」は RANK_FLG = 'A'。
        synonyms: [見込みランク, ランク, 確度]
        sample_values: [S, A, B, C]
      - name: OPP_OWNER_ID
        expr: OWNER_ID
        data_type: VARCHAR
    time_dimensions:
      - name: CREATED_DATE
        expr: CRT_DT
        data_type: DATE
        description: 商談の作成日
      - name: CLOSE_DATE
        expr: CLOSE_DT
        data_type: DATE
        description: 完了日。受注・失注の商談では実際の完了日、進行中の商談では完了予定日。
        synonyms: [完了予定日, 受注日, 成約日]
      - name: CLOSE_FISCAL_YEAR
        expr: CASE WHEN MONTH(CLOSE_DT) >= 4 THEN YEAR(CLOSE_DT) ELSE YEAR(CLOSE_DT) - 1 END
        data_type: NUMBER
        description: 完了日の年度（4月始まり）。2026年度 = 2026-04-01〜2027-03-31。
        synonyms: [年度, 完了年度]
    facts:
      - name: EXPECTED_PREMIUM_JPY
        expr: AMT_EST * 1000
        data_type: NUMBER
        description: 見込み金額（年換算保険料、円）。元データは千円単位のため 1000 倍している。
        synonyms: [見込み金額, 見込み保険料, 商談金額]
    metrics:
      - name: TOTAL_EXPECTED_PREMIUM_JPY
        expr: SUM(AMT_EST * 1000)
        description: 見込み金額の合計（円）
        synonyms: [見込み金額合計, パイプライン金額]
      - name: OPPORTUNITY_COUNT
        expr: COUNT(DISTINCT OPP_ID)
        description: 商談の件数
        synonyms: [商談件数, 見込み件数, 案件数]
    filters:
      - name: OPEN_OPPORTUNITIES
        expr: STAGE_CD NOT IN ('90', '99')
        description: 進行中（受注・失注以外）の商談
        synonyms: [進行中の商談]
      - name: WON_OPPORTUNITIES
        expr: STAGE_CD = '90'
        description: 受注した商談
        synonyms: [受注案件, 成約案件]

  # ------------------------------------------------------------------
  - name: ACTIVITIES
    description: 活動履歴。1行が1回の訪問・オンライン面談・電話。
    synonyms: [活動, 訪問履歴, 面談履歴, コンタクト]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: SF_ACTIVITY}
    primary_key: {columns: [ACT_ID]}
    dimensions:
      - name: ACT_ID
        expr: ACT_ID
        data_type: VARCHAR
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
      - name: ACT_OWNER_ID
        expr: OWNER_ID
        data_type: VARCHAR
      - name: ACTIVITY_TYPE
        expr: CASE ACT_TYP WHEN 'V' THEN '訪問' WHEN 'O' THEN 'オンライン面談' WHEN 'T' THEN '電話' END
        data_type: VARCHAR
        description: 活動種別。「訪問」は対面での訪問のみ（オンライン面談・電話は含まない）。
        synonyms: [活動種別, 接点種別]
        sample_values: [訪問, オンライン面談, 電話]
      - name: SUBJECT
        expr: SUBJ
        data_type: VARCHAR
        description: 活動の件名
    time_dimensions:
      - name: ACTIVITY_DATE
        expr: ACT_DT
        data_type: DATE
        description: 活動日
        synonyms: [訪問日, 面談日]
      - name: ACTIVITY_FISCAL_YEAR
        expr: CASE WHEN MONTH(ACT_DT) >= 4 THEN YEAR(ACT_DT) ELSE YEAR(ACT_DT) - 1 END
        data_type: NUMBER
        description: 活動日の年度（4月始まり）
    metrics:
      - name: ACTIVITY_COUNT
        expr: COUNT(DISTINCT ACT_ID)
        description: 活動件数（全種別）
      - name: VISIT_COUNT
        expr: COUNT(DISTINCT CASE WHEN ACT_TYP = 'V' THEN ACT_ID END)
        description: 訪問件数（対面の訪問のみ）
        synonyms: [訪問件数, 訪問回数]
      - name: LAST_VISIT_DATE
        expr: MAX(CASE WHEN ACT_TYP = 'V' THEN ACT_DT END)
        description: 最終訪問日（対面の訪問のみ）
        synonyms: [最終訪問日, 直近の訪問日]

  # ------------------------------------------------------------------
  - name: CONTRACTS
    description: 既契約（保有契約）。1行が1契約。年間保険料は円単位。有効な契約は契約状態が「有効」のもの。
    synonyms: [既契約, 保有契約, 契約]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: SF_CONTRACT}
    primary_key: {columns: [CNT_ID]}
    dimensions:
      - name: CNT_ID
        expr: CNT_ID
        data_type: VARCHAR
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
      - name: CONTRACT_PRODUCT_CODE
        expr: PRD_CD
        data_type: VARCHAR
        description: 契約商品コード（PRODUCTS と結合）
      - name: CONTRACT_STATUS
        expr: CASE STS_CD WHEN '1' THEN '有効' WHEN '9' THEN '解約' END
        data_type: VARCHAR
        description: 契約状態。有効 = 現在保有中、解約 = 解約済み。
        synonyms: [契約状態, ステータス]
        sample_values: [有効, 解約]
    time_dimensions:
      - name: CONTRACT_START_DATE
        expr: START_DT
        data_type: DATE
        description: 契約開始日
    facts:
      - name: ANNUAL_PREMIUM_JPY
        expr: ANN_PREM
        data_type: NUMBER
        description: 年間保険料（円）
        synonyms: [年間保険料, 保険料]
      - name: INSURED_COUNT
        expr: INS_CNT
        data_type: NUMBER
        description: 被保険者数（人）
        synonyms: [加入者数, 被保険者数]
    metrics:
      - name: ACTIVE_ANNUAL_PREMIUM_JPY
        expr: SUM(CASE WHEN STS_CD = '1' THEN ANN_PREM END)
        description: 有効な既契約の年間保険料合計（円）
        synonyms: [保有保険料, 既契約保険料]
      - name: ACTIVE_CONTRACT_COUNT
        expr: COUNT(DISTINCT CASE WHEN STS_CD = '1' THEN CNT_ID END)
        description: 有効な既契約の件数

  # ------------------------------------------------------------------
  - name: PRODUCTS
    description: 商品マスタ（保険商品と非保険サービス）
    synonyms: [商品, 保険商品]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: MST_PRODUCT}
    primary_key: {columns: [PRD_CD]}
    dimensions:
      - name: PRD_CD
        expr: PRD_CD
        data_type: VARCHAR
      - name: PRODUCT_NAME
        expr: PRD_NM
        data_type: VARCHAR
        description: 商品名
        synonyms: [商品名]
        sample_values: [総合福祉団体定期保険, 団体長期障害所得補償保険（GLTD）, 確定拠出年金（企業型DC）運営管理]
      - name: PRODUCT_CATEGORY
        expr: PRD_CAT
        data_type: VARCHAR
        description: 商品分類
        sample_values: [団体保障, 企業年金, 経営者保障, 非保険サービス]

  # ------------------------------------------------------------------
  - name: SALES_REPS
    description: 営業担当者
    synonyms: [営業担当, 担当者, 営業職員]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: RAW, table: SF_USER}
    primary_key: {columns: [OWNER_ID]}
    dimensions:
      - name: OWNER_ID
        expr: OWNER_ID
        data_type: VARCHAR
      - name: SALES_REP_NAME
        expr: USR_NM
        data_type: VARCHAR
        description: 営業担当者の氏名
        synonyms: [担当者名, 営業担当者名]

  # ------------------------------------------------------------------
  - name: FINANCIALS
    description: 財務企画部が管理する顧客企業の年度別業績（単位は百万円）。
    synonyms: [財務, 業績, 決算]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: MART, table: V_COMPANY_FINANCIALS}
    primary_key: {columns: [ACCT_ID, FISCAL_YEAR]}
    dimensions:
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
      - name: FISCAL_YEAR
        expr: FISCAL_YEAR
        data_type: NUMBER
        description: 顧客企業の決算年度（2023〜2025）
        synonyms: [決算年度]
    facts:
      - name: REVENUE_MJPY
        expr: REVENUE_MJPY
        data_type: NUMBER
        description: 売上高（百万円）
        synonyms: [売上高, 売上]
      - name: OPERATING_PROFIT_MJPY
        expr: OP_PROFIT_MJPY
        data_type: NUMBER
        description: 営業利益（百万円）
        synonyms: [営業利益]

  # ------------------------------------------------------------------
  - name: JOB_POSTINGS
    description: 外部データ。顧客企業の月次の求人掲載件数。採用強化の兆候をつかむために使う。
    synonyms: [求人, 求人件数, 採用動向]
    base_table: {database: SNOWLIFE_HANDSON_DB, schema: MART, table: V_JOB_POSTINGS}
    primary_key: {columns: [ACCT_ID, POST_MONTH]}
    dimensions:
      - name: ACCT_ID
        expr: ACCT_ID
        data_type: VARCHAR
    time_dimensions:
      - name: POST_MONTH
        expr: POST_MONTH
        data_type: DATE
        description: 求人を集計した月（月初日）
        synonyms: [掲載月]
    facts:
      - name: POSTING_COUNT
        expr: POSTING_CNT
        data_type: NUMBER
        description: 月間の求人掲載件数
        synonyms: [求人件数, 求人数]

relationships:
  - name: OPPORTUNITIES_TO_ACCOUNTS
    left_table: OPPORTUNITIES
    right_table: ACCOUNTS
    relationship_columns: [{left_column: ACCT_ID, right_column: ACCT_ID}]
  - name: ACTIVITIES_TO_ACCOUNTS
    left_table: ACTIVITIES
    right_table: ACCOUNTS
    relationship_columns: [{left_column: ACCT_ID, right_column: ACCT_ID}]
  - name: CONTRACTS_TO_ACCOUNTS
    left_table: CONTRACTS
    right_table: ACCOUNTS
    relationship_columns: [{left_column: ACCT_ID, right_column: ACCT_ID}]
  - name: FINANCIALS_TO_ACCOUNTS
    left_table: FINANCIALS
    right_table: ACCOUNTS
    relationship_columns: [{left_column: ACCT_ID, right_column: ACCT_ID}]
  - name: JOB_POSTINGS_TO_ACCOUNTS
    left_table: JOB_POSTINGS
    right_table: ACCOUNTS
    relationship_columns: [{left_column: ACCT_ID, right_column: ACCT_ID}]
  - name: ACCOUNTS_TO_SALES_REPS
    left_table: ACCOUNTS
    right_table: SALES_REPS
    relationship_columns: [{left_column: OWNER_ID, right_column: OWNER_ID}]
  - name: OPPORTUNITIES_TO_PRODUCTS
    left_table: OPPORTUNITIES
    right_table: PRODUCTS
    relationship_columns: [{left_column: OPP_PRODUCT_CODE, right_column: PRD_CD}]
  - name: CONTRACTS_TO_PRODUCTS
    left_table: CONTRACTS
    right_table: PRODUCTS
    relationship_columns: [{left_column: CONTRACT_PRODUCT_CODE, right_column: PRD_CD}]

module_custom_instructions:
  sql_generation: >-
    年度は4月始まりとする（例: 2026年度上期 = 2026-04-01〜2026-09-30）。
    金額は円単位で返す。見込み金額は EXPECTED_PREMIUM_JPY（AMT_EST * 1000）を使い、AMT_EST をそのまま金額として扱わない。
    「訪問」は ACTIVITY_TYPE = '訪問' のみを指し、オンライン面談や電話を含めない。
    取引先を一覧にするときは取引先名（ACCOUNT_NAME）を必ず含める。

verified_queries:
  - name: open_pipeline_by_rank
    question: 進行中の商談の見込みランク別の件数と見込み金額合計を教えて
    use_as_onboarding_question: true
    sql: |
      SELECT PROSPECT_RANK,
             COUNT(DISTINCT OPP_ID) AS OPPORTUNITY_COUNT,
             SUM(EXPECTED_PREMIUM_JPY) AS TOTAL_EXPECTED_PREMIUM_JPY
      FROM __OPPORTUNITIES
      WHERE IS_OPEN
      GROUP BY PROSPECT_RANK
      ORDER BY PROSPECT_RANK
  - name: visits_by_rep_fy2026_h1
    question: 2026年度上期の営業担当別の訪問件数を多い順に教えて
    use_as_onboarding_question: true
    sql: |
      SELECT r.SALES_REP_NAME,
             COUNT(DISTINCT a.ACT_ID) AS VISIT_COUNT
      FROM __ACTIVITIES a
      JOIN __ACCOUNTS acc ON a.ACCT_ID = acc.ACCT_ID
      JOIN __SALES_REPS r ON acc.OWNER_ID = r.OWNER_ID
      WHERE a.ACTIVITY_TYPE = '訪問'
        AND a.ACTIVITY_DATE BETWEEN '2026-04-01' AND '2026-09-30'
      GROUP BY r.SALES_REP_NAME
      ORDER BY VISIT_COUNT DESC
$$
);

-- 3. 営業職員ロールにも参照させる
GRANT SELECT ON SEMANTIC VIEW SNOWLIFE_HANDSON_DB.AI.SV_SALES_ANALYTICS TO ROLE SNOWLIFE_SALES_REP_T01;

-- 4. 確認
SHOW SEMANTIC METRICS IN SNOWLIFE_HANDSON_DB.AI.SV_SALES_ANALYTICS;


-- ################################################################################
-- sql/03_agents.sql: Cortex Agent（SALES_AGENT / SALES_AGENT_BASIC）
-- ################################################################################

/*
================================================================================
Part 3 答え合わせ: Cortex Agent A / B の作成
================================================================================
Agent A（SALES_AGENT_BASIC）と Agent B（SALES_AGENT）は、ツール構成も指示文も同じです。
違いは Cortex Analyst ツールが参照するセマンティックビューだけです。

  Agent A: AI.SV_SALES_MINIMAL    … テーブルと主キー・リレーションのみ（setup.sql で作成）
  Agent B: AI.SV_SALES_ANALYTICS  … 説明・同義語・指標・検証済みクエリ付き（Part 2 で作成）

Part 2 を終えていない場合は、先に answers/part2_semantic_view.sql を実行してください。
================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWLIFE_HANDSON_WH;
USE SCHEMA SNOWLIFE_HANDSON_DB.AI;


-- ----------------------------------------------------------------------------
-- Agent A: 意味づけのないセマンティックビューを使う Agent
-- ----------------------------------------------------------------------------
CREATE OR REPLACE AGENT SALES_AGENT_BASIC
    COMMENT = '比較用。意味づけのない最小セマンティックビューを使う法人営業 Agent'
    PROFILE = '{"display_name": "法人営業アシスタント（A: 意味づけなし）"}'
    FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: |
    【回答の形】
    - 日本語で答える。最初の1〜2文で結論（数値・企業名など）を書き、その後に内訳や根拠を書く。
    - 一覧や比較は表で示す。11件以上になる場合は上位10件を示し、全体の件数を添える。
    - 数値には必ず単位（円・件・名・%）を付ける。金額は「4億2,718万2,000円」のように桁区切りと万・億を使って読みやすく書く。
    - 数値で答えた場合は、最後に「集計条件:」として対象期間・対象支社・商談の状態などの条件を1行で書く。
    - 面談メモや商品資料を使った場合は、どの企業の何月何日の面談か、どの資料のどの記述かが分かるように示す。

    【表現の注意】
    - 保険の募集に関わる内容では、「必ず」「確実に」「絶対に」「損をしない」などの断定的な表現を使わない。
    - 税務上の取扱いに触れる場合は、「一般的な取扱いであり、個別の判断は税理士等の専門家にご確認ください」と添える。
    - 被保険者個人の健康状態や病歴に関する情報は回答に含めない。
  orchestration: |
    あなたはスノー生命保険 法人営業部門のアシスタントです。利用者は法人営業職員と営業企画部の担当者で、取引先・商談・既契約・面談・商品について質問します。

    【ツールの使い分け】
    1. 件数・金額・一覧・ランキング・推移など、数値で答える質問は sales_analytics を使う。
    2. 面談で先方が話した内容、課題・関心事、宿題・次回アクションは meeting_notes_search を使う。
    3. 商品の特長・引受条件・保障内容・約款の規定は product_docs_search を使う。
    4. 「〇〇社の状況を教えて」のように複数の観点が必要な質問は、sales_analytics で商談・既契約を確認したうえで、meeting_notes_search で面談の内容を補う。商品の提案に触れる場合は product_docs_search で根拠を確認する。

    【質問の読み取り方】
    - 企業名が略称の場合（例: トヨタ、パナ）は、取引先名にその語を含む企業として扱う。候補が複数あるときは、どの企業か確認する。
    - 期間の指定がない場合は全期間を対象にし、そのことを回答に書く。
    - 解釈によって答えが大きく変わる質問は、推測で進めずに確認の質問を1つ返す。

    【守ること】
    - ツールで得た結果だけをもとに答える。データにないことは推測で補わず「データなし」と書く。
    - ツールの結果の数値を、自分の判断で換算・補正しない。

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "sales_analytics"
      description: "法人営業の取引先・商談・活動履歴・既契約・企業財務・求人件数を SQL で集計するツール。件数・金額・一覧・ランキングの質問に使う。"
  - tool_spec:
      type: "cortex_search"
      name: "meeting_notes_search"
      description: "営業職員が記録した面談メモを検索するツール。先方が何を話したか、課題・関心事・次回アクションを調べるときに使う。"
  - tool_spec:
      type: "cortex_search"
      name: "product_docs_search"
      description: "スノー生命の商品パンフレット・約款を検索するツール。商品の特長・引受条件・約款の規定を調べるときに使う。"

tool_resources:
  sales_analytics:
    semantic_view: "SNOWLIFE_HANDSON_DB.AI.SV_SALES_MINIMAL"
    execution_environment:
      type: "warehouse"
      warehouse: "SNOWLIFE_HANDSON_WH"
  meeting_notes_search:
    search_service: "SNOWLIFE_HANDSON_DB.AI.MEETING_NOTE_SEARCH"
    max_results: 5
    id_column: "NOTE_ID"
    title_column: "ACCT_NM"
  product_docs_search:
    search_service: "SNOWLIFE_HANDSON_DB.AI.PRODUCT_DOC_SEARCH"
    max_results: 5
    id_column: "RELATIVE_PATH"
    title_column: "RELATIVE_PATH"
    stage_path: "@SNOWLIFE_HANDSON_DB.RAW.DOC_STAGE"
    relative_path_column: "RELATIVE_PATH"
$$;


-- ----------------------------------------------------------------------------
-- Agent B: 受講者が作ったセマンティックビューを使う Agent
-- ----------------------------------------------------------------------------
CREATE OR REPLACE AGENT SALES_AGENT
    COMMENT = 'スノー生命 法人営業アシスタント'
    PROFILE = '{"display_name": "法人営業アシスタント（B: 意味づけあり）"}'
    FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: |
    【回答の形】
    - 日本語で答える。最初の1〜2文で結論（数値・企業名など）を書き、その後に内訳や根拠を書く。
    - 一覧や比較は表で示す。11件以上になる場合は上位10件を示し、全体の件数を添える。
    - 数値には必ず単位（円・件・名・%）を付ける。金額は「4億2,718万2,000円」のように桁区切りと万・億を使って読みやすく書く。
    - 数値で答えた場合は、最後に「集計条件:」として対象期間・対象支社・商談の状態などの条件を1行で書く。
    - 面談メモや商品資料を使った場合は、どの企業の何月何日の面談か、どの資料のどの記述かが分かるように示す。

    【表現の注意】
    - 保険の募集に関わる内容では、「必ず」「確実に」「絶対に」「損をしない」などの断定的な表現を使わない。
    - 税務上の取扱いに触れる場合は、「一般的な取扱いであり、個別の判断は税理士等の専門家にご確認ください」と添える。
    - 被保険者個人の健康状態や病歴に関する情報は回答に含めない。
  orchestration: |
    あなたはスノー生命保険 法人営業部門のアシスタントです。利用者は法人営業職員と営業企画部の担当者で、取引先・商談・既契約・面談・商品について質問します。

    【ツールの使い分け】
    1. 件数・金額・一覧・ランキング・推移など、数値で答える質問は sales_analytics を使う。
    2. 面談で先方が話した内容、課題・関心事、宿題・次回アクションは meeting_notes_search を使う。
    3. 商品の特長・引受条件・保障内容・約款の規定は product_docs_search を使う。
    4. 「〇〇社の状況を教えて」のように複数の観点が必要な質問は、sales_analytics で商談・既契約を確認したうえで、meeting_notes_search で面談の内容を補う。商品の提案に触れる場合は product_docs_search で根拠を確認する。

    【質問の読み取り方】
    - 企業名が略称の場合（例: トヨタ、パナ）は、取引先名にその語を含む企業として扱う。候補が複数あるときは、どの企業か確認する。
    - 期間の指定がない場合は全期間を対象にし、そのことを回答に書く。
    - 解釈によって答えが大きく変わる質問は、推測で進めずに確認の質問を1つ返す。

    【守ること】
    - ツールで得た結果だけをもとに答える。データにないことは推測で補わず「データなし」と書く。
    - ツールの結果の数値を、自分の判断で換算・補正しない。

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "sales_analytics"
      description: "法人営業の取引先・商談・活動履歴・既契約・企業財務・求人件数を SQL で集計するツール。件数・金額・一覧・ランキングの質問に使う。"
  - tool_spec:
      type: "cortex_search"
      name: "meeting_notes_search"
      description: "営業職員が記録した面談メモを検索するツール。先方が何を話したか、課題・関心事・次回アクションを調べるときに使う。"
  - tool_spec:
      type: "cortex_search"
      name: "product_docs_search"
      description: "スノー生命の商品パンフレット・約款を検索するツール。商品の特長・引受条件・約款の規定を調べるときに使う。"

tool_resources:
  sales_analytics:
    semantic_view: "SNOWLIFE_HANDSON_DB.AI.SV_SALES_ANALYTICS"
    execution_environment:
      type: "warehouse"
      warehouse: "SNOWLIFE_HANDSON_WH"
  meeting_notes_search:
    search_service: "SNOWLIFE_HANDSON_DB.AI.MEETING_NOTE_SEARCH"
    max_results: 5
    id_column: "NOTE_ID"
    title_column: "ACCT_NM"
  product_docs_search:
    search_service: "SNOWLIFE_HANDSON_DB.AI.PRODUCT_DOC_SEARCH"
    max_results: 5
    id_column: "RELATIVE_PATH"
    title_column: "RELATIVE_PATH"
    stage_path: "@SNOWLIFE_HANDSON_DB.RAW.DOC_STAGE"
    relative_path_column: "RELATIVE_PATH"
$$;


-- ----------------------------------------------------------------------------
-- CoWork に表示する
-- ----------------------------------------------------------------------------
-- CoWork オブジェクトがあるアカウントでは、追加しないと CoWork に表示されません。
-- 再実行した場合（追加済みの場合）もエラーで止まらないようにしています。
EXECUTE IMMEDIATE $$
BEGIN
    ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT SNOWLIFE_HANDSON_DB.AI.SALES_AGENT_BASIC;
    RETURN 'SALES_AGENT_BASIC を CoWork に追加しました';
EXCEPTION
    WHEN OTHER THEN RETURN 'SALES_AGENT_BASIC は追加済みです（' || SQLERRM || '）';
END;
$$;

EXECUTE IMMEDIATE $$
BEGIN
    ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT SNOWLIFE_HANDSON_DB.AI.SALES_AGENT;
    RETURN 'SALES_AGENT を CoWork に追加しました';
EXCEPTION
    WHEN OTHER THEN RETURN 'SALES_AGENT は追加済みです（' || SQLERRM || '）';
END;
$$;

-- 営業職員ロールにも使わせる（setup.sql の FUTURE GRANT で付与済みですが、念のため明示します）
GRANT USAGE ON AGENT SNOWLIFE_HANDSON_DB.AI.SALES_AGENT_BASIC TO ROLE SNOWLIFE_SALES_REP_T01;
GRANT USAGE ON AGENT SNOWLIFE_HANDSON_DB.AI.SALES_AGENT       TO ROLE SNOWLIFE_SALES_REP_T01;

SHOW AGENTS IN SCHEMA SNOWLIFE_HANDSON_DB.AI;


-- ################################################################################
-- sql/04_skills.sql: Agent の業務スキル 3 件
-- ################################################################################

/*
================================================================================
Part 4 答え合わせ: 業務スキルを Agent B（SALES_AGENT）に登録する
================================================================================
Snowsight の Agent 画面（Skills タブ » Add Skill）で登録できなかった場合に実行してください。

  1. SKILL.md を SKILL_STAGE に置く（自分で書いたものが置けていない場合は見本をコピー）
  2. Agent の仕様に skills を追加する
  3. 登録されたことを確認する
================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWLIFE_HANDSON_WH;
USE SCHEMA SNOWLIFE_HANDSON_DB.AI;


-- ----------------------------------------------------------------------------
-- 1. SKILL.md をステージに置く
-- ----------------------------------------------------------------------------
-- 自分で書いた pre-visit-briefing/SKILL.md をアップロード済みなら、このブロックは飛ばしてください。
-- 見本（answers/skills/pre-visit-briefing/SKILL.md）を GitHub からコピーします。
ALTER GIT REPOSITORY SNOWLIFE_HANDSON_DB.RAW.SNOWLIFE_HANDSON_REPO FETCH;

COPY FILES INTO @SKILL_STAGE/skills/pre-visit-briefing/
    FROM @SNOWLIFE_HANDSON_DB.RAW.SNOWLIFE_HANDSON_REPO/branches/main/answers/skills/pre-visit-briefing/;

-- SKILL.md が skills/<スキル名>/SKILL.md の階層にあることを確認する
LS @SKILL_STAGE/ PATTERN = '.*SKILL\.md';


-- ----------------------------------------------------------------------------
-- 2. Agent の仕様に skills を追加する
-- ----------------------------------------------------------------------------
-- 注意: ALTER AGENT ... SET SPECIFICATION は仕様全体を置き換えます。
--       既存のツール設定もすべて書き直す必要があります。
ALTER AGENT SALES_AGENT MODIFY LIVE VERSION SET SPECIFICATION =
$$
models:
  orchestration: auto

instructions:
  response: |
    【回答の形】
    - 日本語で答える。最初の1〜2文で結論（数値・企業名など）を書き、その後に内訳や根拠を書く。
    - 一覧や比較は表で示す。11件以上になる場合は上位10件を示し、全体の件数を添える。
    - 数値には必ず単位（円・件・名・%）を付ける。金額は「4億2,718万2,000円」のように桁区切りと万・億を使って読みやすく書く。
    - 数値で答えた場合は、最後に「集計条件:」として対象期間・対象支社・商談の状態などの条件を1行で書く。
    - 面談メモや商品資料を使った場合は、どの企業の何月何日の面談か、どの資料のどの記述かが分かるように示す。

    【表現の注意】
    - 保険の募集に関わる内容では、「必ず」「確実に」「絶対に」「損をしない」などの断定的な表現を使わない。
    - 税務上の取扱いに触れる場合は、「一般的な取扱いであり、個別の判断は税理士等の専門家にご確認ください」と添える。
    - 被保険者個人の健康状態や病歴に関する情報は回答に含めない。
  orchestration: |
    あなたはスノー生命保険 法人営業部門のアシスタントです。利用者は法人営業職員と営業企画部の担当者で、取引先・商談・既契約・面談・商品について質問します。

    【ツールの使い分け】
    1. 件数・金額・一覧・ランキング・推移など、数値で答える質問は sales_analytics を使う。
    2. 面談で先方が話した内容、課題・関心事、宿題・次回アクションは meeting_notes_search を使う。
    3. 商品の特長・引受条件・保障内容・約款の規定は product_docs_search を使う。
    4. 「〇〇社の状況を教えて」のように複数の観点が必要な質問は、sales_analytics で商談・既契約を確認したうえで、meeting_notes_search で面談の内容を補う。商品の提案に触れる場合は product_docs_search で根拠を確認する。

    【質問の読み取り方】
    - 企業名が略称の場合（例: トヨタ、パナ）は、取引先名にその語を含む企業として扱う。候補が複数あるときは、どの企業か確認する。
    - 期間の指定がない場合は全期間を対象にし、そのことを回答に書く。
    - 解釈によって答えが大きく変わる質問は、推測で進めずに確認の質問を1つ返す。

    【守ること】
    - ツールで得た結果だけをもとに答える。データにないことは推測で補わず「データなし」と書く。
    - ツールの結果の数値を、自分の判断で換算・補正しない。

    【スキルの使い方】
    - 訪問準備・提案準備・文面チェックの依頼では、対応するスキル（pre-visit-briefing / proposal-prep / compliance-check）の手順と出力フォーマットに従う。

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "sales_analytics"
      description: "法人営業の取引先・商談・活動履歴・既契約・企業財務・求人件数を SQL で集計するツール。件数・金額・一覧・ランキングの質問に使う。"
  - tool_spec:
      type: "cortex_search"
      name: "meeting_notes_search"
      description: "営業職員が記録した面談メモを検索するツール。先方が何を話したか、課題・関心事・次回アクションを調べるときに使う。"
  - tool_spec:
      type: "cortex_search"
      name: "product_docs_search"
      description: "スノー生命の商品パンフレット・約款を検索するツール。商品の特長・引受条件・約款の規定を調べるときに使う。"

tool_resources:
  sales_analytics:
    semantic_view: "SNOWLIFE_HANDSON_DB.AI.SV_SALES_ANALYTICS"
    execution_environment:
      type: "warehouse"
      warehouse: "SNOWLIFE_HANDSON_WH"
  meeting_notes_search:
    search_service: "SNOWLIFE_HANDSON_DB.AI.MEETING_NOTE_SEARCH"
    max_results: 5
    id_column: "NOTE_ID"
    title_column: "ACCT_NM"
  product_docs_search:
    search_service: "SNOWLIFE_HANDSON_DB.AI.PRODUCT_DOC_SEARCH"
    max_results: 5
    id_column: "RELATIVE_PATH"
    title_column: "RELATIVE_PATH"
    stage_path: "@SNOWLIFE_HANDSON_DB.RAW.DOC_STAGE"
    relative_path_column: "RELATIVE_PATH"

skills:
  - name: "pre-visit-briefing"
    source:
      type: "STAGE"
      path: "@SNOWLIFE_HANDSON_DB.AI.SKILL_STAGE/skills/pre-visit-briefing"
  - name: "proposal-prep"
    source:
      type: "STAGE"
      path: "@SNOWLIFE_HANDSON_DB.AI.SKILL_STAGE/skills/proposal-prep"
  - name: "compliance-check"
    source:
      type: "STAGE"
      path: "@SNOWLIFE_HANDSON_DB.AI.SKILL_STAGE/skills/compliance-check"
$$;


-- ----------------------------------------------------------------------------
-- 3. 登録されたことを確認する
-- ----------------------------------------------------------------------------
-- 出力の agent_spec に skills が3件含まれていれば成功です。
DESCRIBE AGENT SALES_AGENT;


-- ################################################################################
-- sql/05_app.sql: アプリの置き場所（APP スキーマ）
-- ################################################################################

/*
================================================================================
アプリの置き場所を用意する
================================================================================
snow app deploy は、app/app.yml の database / schema に Application Service を作ります。
ここではその置き場所（SNOWLIFE_HANDSON_DB.APP）を作ります。
================================================================================
*/

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SNOWLIFE_HANDSON_WH;

CREATE SCHEMA IF NOT EXISTS SNOWLIFE_HANDSON_DB.APP
    COMMENT = 'Snowflake App Runtime で作るアプリ（Application Service）';

SELECT '【アプリ】APP スキーマの作成が完了しました' AS status;


-- ============================================================================
-- 完了
-- ============================================================================

SELECT '
 環境の構築が完了しました
  - データ        : SNOWLIFE_HANDSON_DB（RAW / MART / AI / SECURITY / APP）
  - Cortex Agent  : SNOWLIFE_HANDSON_DB.AI.SALES_AGENT
  - アプリの置き場: SNOWLIFE_HANDSON_DB.APP
' AS "セットアップ完了";
