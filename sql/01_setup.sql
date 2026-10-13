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
