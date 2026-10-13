/*
================================================================================
後片付け
================================================================================
ハンズオンで作成したオブジェクトを削除します。

アカウントレベルのオブジェクトのうち、他の用途と共有している可能性があるもの
（CoWork オブジェクト・クロスリージョン推論の設定）は削除・変更しません。
================================================================================
*/

USE ROLE ACCOUNTADMIN;

-- CoWork オブジェクトから Agent を外す（Part 3 を実施していなくてもエラーで止まらないようにしています）
EXECUTE IMMEDIATE $$
BEGIN
    ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT DROP AGENT SNOWLIFE_HANDSON_DB.AI.SALES_AGENT_BASIC;
    RETURN 'SALES_AGENT_BASIC を CoWork から外しました';
EXCEPTION
    WHEN OTHER THEN RETURN 'SALES_AGENT_BASIC は CoWork に登録されていません（スキップ）';
END;
$$;

EXECUTE IMMEDIATE $$
BEGIN
    ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT DROP AGENT SNOWLIFE_HANDSON_DB.AI.SALES_AGENT;
    RETURN 'SALES_AGENT を CoWork から外しました';
EXCEPTION
    WHEN OTHER THEN RETURN 'SALES_AGENT は CoWork に登録されていません（スキップ）';
END;
$$;

-- Part 5 でデフォルトロールを戻し忘れた場合だけ ACCOUNTADMIN に戻す
EXECUTE IMMEDIATE $$
DECLARE
    current_default STRING;
BEGIN
    EXECUTE IMMEDIATE 'DESCRIBE USER "' || CURRENT_USER() || '"';
    SELECT "value" INTO :current_default
    FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    WHERE "property" = 'DEFAULT_ROLE';
    IF (current_default = 'SNOWLIFE_SALES_REP_T01') THEN
        EXECUTE IMMEDIATE 'ALTER USER "' || CURRENT_USER() || '" SET DEFAULT_ROLE = ACCOUNTADMIN';
        RETURN 'デフォルトロールを ACCOUNTADMIN に戻しました';
    END IF;
    RETURN 'デフォルトロールは変更していません（現在: ' || current_default || '）';
END;
$$;

DROP DATABASE IF EXISTS SNOWLIFE_HANDSON_DB;
DROP DATABASE IF EXISTS FINANCE_PLANNING_DB;
DROP WAREHOUSE IF EXISTS SNOWLIFE_HANDSON_WH;
DROP ROLE IF EXISTS SNOWLIFE_SALES_REP_T01;
DROP API INTEGRATION IF EXISTS git_api_integration_snowlife;

SELECT 'ハンズオン環境を削除しました' AS status;
