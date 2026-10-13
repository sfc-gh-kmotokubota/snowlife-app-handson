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
