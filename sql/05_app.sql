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
