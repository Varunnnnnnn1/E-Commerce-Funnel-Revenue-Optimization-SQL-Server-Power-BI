
/***********************************************************************************************
                                 DATA CLEANING
************************************************************************************************/

/*----------------------------------------------------------------------------------------------                    
                          1. ORDERS TABLE
----------------------------------------------------------------------------------------------*/
SELECT * FROM ORDERS

-- STEP 1: FINING & REMOVING DUPLICATES

SELECT *
FROM (
SELECT 
    *,
    ROW_NUMBER() OVER(PARTITION BY ORDER_ID ORDER BY ORDER_ID) AS ROW1
FROM ORDERS) AS T
WHERE ROW1 > 1

-- STEP 2: CHEAKING DATA TYPE

SELECT 
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ORDERS'


-- STEP 3: NULL VALUE ANALYSIS

-- METHOD 1


SELECT
    COUNT(CASE WHEN order_id IS NULL THEN 1  END) AS order_id_nulls,
    
    COUNT(CASE WHEN created_at IS NULL THEN 1  END) AS created_at_nulls,
    
    COUNT(CASE WHEN website_session_id IS NULL THEN 1  END) AS website_session_id_nulls,
    
    COUNT(CASE WHEN user_id IS NULL THEN 1 END) AS user_id_nulls,
    
    COUNT(CASE WHEN primary_product_id IS NULL THEN 1 END) AS primary_product_id_nulls,
    
    COUNT(CASE WHEN items_purchased IS NULL THEN 1  END) AS items_purchased_nulls,
    
    COUNT(CASE WHEN price_usd IS NULL THEN 1 END) AS price_usd_nulls,
    
    COUNT(CASE WHEN cogs_usd IS NULL THEN 1 END) AS cogs_usd_nulls

FROM orders;



-- METHOD 2

DECLARE @sql NVARCHAR(MAX) = '';

SELECT @sql = STRING_AGG(
'
SELECT
    ''' + COLUMN_NAME + ''' AS column_name,
    COUNT(*) AS null_count
FROM ORDERS
WHERE ' + QUOTENAME(COLUMN_NAME) + ' IS NULL',
'
UNION ALL
')
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ORDERS';

EXEC sp_executesql @sql;


/*----------------------------------------------------------------------------------------------                    
                              1. ORDERS items
----------------------------------------------------------------------------------------------*/

-- STEP 1: CHECKING FOR DUPLICATES

SELECT * 
FROM (
    SELECT 
        *,
        ROW_NUMBER() OVER(PARTITION BY ORDER_ITEM_ID 
                ORDER BY ORDER_ITEM_ID) AS ROW_N
            FROM order_items
                 )AS ROWWISE
    WHERE ROW_N > 1

-- STEP 2: CHECKING DATA TYPE

SELECT 
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'ORDER_ITEMS'

-- STEP 3: CHECK FOR NULL VALUES

SELECT 
    COUNT(CASE WHEN order_item_id IS NULL THEN 1 END) AS ORDER_ITEM_ID,
    COUNT(CASE WHEN created_at IS NULL THEN 1 END) AS created_at,
    COUNT(CASE WHEN order_id IS NULL THEN 1 END) AS order_id,
    COUNT(CASE WHEN product_id IS NULL THEN 1 END) AS product_id,
    COUNT(CASE WHEN is_primary_item IS NULL THEN 1 END) AS is_primary_item,
    COUNT(CASE WHEN price_usd IS NULL THEN 1 END) AS price_usd,
    COUNT(CASE WHEN cogs_usd IS NULL THEN 1 END) AS cogs_usd
FROM order_items

/*----------------------------------------------------------------------------------------------                    
                          1. REFUNDS
----------------------------------------------------------------------------------------------*/

SELECT * FROM REFUNDS

-- STEP 1: FINDING DUPLICATE RECORDS
USE WEBANALYSIS;   -- [FIX] ';' needed before WITH (SQL Server error 319 otherwise)

WITH BASE
AS (
SELECT 
    *,
    ROW_NUMBER() OVER(PARTITION BY ORDER_ITEM_REFUND_ID 
                        ORDER BY ORDER_ITEM_REFUND_ID ) AS ROWN

FROM REFUNDS) SELECT * FROM BASE WHERE ROWN >1


-- STEP 2: CHECK FOR DATA TYPE

SELECT 
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'REFUNDS'


-- STEP 3: CHECK FOR NULL VALUE ANALYSIS

SELECT
    SUM(CASE WHEN ORDER_ITEM_REFUND_ID IS NULL THEN 1 ELSE 0 END) AS ORDER_ITEM_REFUND_ID,
    SUM(CASE WHEN created_at IS NULL  THEN 1 ELSE 0 END) AS created_at,
    SUM(CASE WHEN order_item_id IS NULL  THEN 1 ELSE 0 END) AS order_item_id,
    SUM(CASE WHEN order_id IS NULL  THEN 1 ELSE 0 END) AS order_id,
    SUM(CASE WHEN refund_amount_usd IS NULL  THEN 1 ELSE 0 END) AS refund_amount_usd,
    COUNT(ORDER_ITEM_REFUND_ID) AS TOTAL_ROWS
FROM REFUNDS

/*----------------------------------------------------------------------------------------------                    
                          1. WEBSITE PAGE VIEW
----------------------------------------------------------------------------------------------*/

-- STEP 1: CHECKING FOR DUPLICATE

SELECT *
    FROM (

        SELECT 
            *,
            ROW_NUMBER() OVER(PARTITION BY WEBSITE_PAGEVIEW_ID ORDER BY WEBSITE_PAGEVIEW_ID) AS ROW1
        FROM PAGEVIEW
        ) AS BASE
WHERE ROW1 >1

-- STEP 2: CHECKING FOR DATA TYPE

SELECT 
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'PAGEVIEW'


-- STEP 3: CHECK FOR NULL VALUES

SELECT 
    COUNT(CASE WHEN website_pageview_id IS NULL THEN 1 END) AS website_pageview_id,
    COUNT(CASE WHEN created_at IS NULL THEN 1 END) AS created_at,
    COUNT(CASE WHEN website_session_id IS NULL THEN 1 END) AS website_session_id,
    COUNT(CASE WHEN pageview_url IS NULL THEN 1 END) AS pageview_url
FROM PAGEVIEW


/*----------------------------------------------------------------------------------------------                    
                          1. WEBSITE SESSIONS
----------------------------------------------------------------------------------------------*/

SELECT * FROM WEB_SESSIONS

-- STEP 1: FINDING DUPLICATES

SELECT * 
FROM
(
    SELECT *,
          ROW_NUMBER() OVER(PARTITION BY WEBSITE_SESSION_ID ORDER BY WEBSITE_SESSION_ID) AS ROW1
     FROM WEB_SESSIONS) AS TA
    WHERE ROW1 > 1


-- STEP 2: CHECK FOR DATA TYPE

SELECT 
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'WEB_SESSIONS'


-- STEP 3: CHECK FOR NULL VALUES

SELECT 
    COUNT(CASE WHEN website_session_id IS NULL THEN 1 END) AS website_session_id,
    COUNT(CASE WHEN created_at IS NULL THEN 1 END) AS created_at,
    COUNT(CASE WHEN user_id IS NULL THEN 1 END) AS user_id,
    COUNT(CASE WHEN is_repeat_session IS NULL THEN 1 END) AS is_repeat_session,
    COUNT(CASE WHEN utm_source IS NULL THEN 1 END) AS utm_source,
    COUNT(CASE WHEN utm_campaign IS NULL THEN 1 END) AS utm_campaign,
    COUNT(CASE WHEN utm_content IS NULL THEN 1 END) AS utm_content,
    COUNT(CASE WHEN device_type IS NULL THEN 1 END) AS device_type,
    COUNT(CASE WHEN http_referer IS NULL THEN 1 END) AS http_referer
FROM WEB_SESSIONS

-- [FIX] ADDED STEP 4: CONVERT TEXT 'NULL' TO REAL NULL
-- The CSV stores missing values as the text 'NULL', so the IS NULL counts above return 0 for the
-- utm columns and http_referer even though 83,328 sessions have no utm_source.
-- Count them first, then convert so later IS NULL / COUNT(column) logic behaves correctly.

SELECT
    COUNT(CASE WHEN utm_source   = 'NULL' THEN 1 END) AS utm_source_text_null,
    COUNT(CASE WHEN utm_campaign = 'NULL' THEN 1 END) AS utm_campaign_text_null,
    COUNT(CASE WHEN utm_content  = 'NULL' THEN 1 END) AS utm_content_text_null,
    COUNT(CASE WHEN http_referer = 'NULL' THEN 1 END) AS http_referer_text_null
FROM WEB_SESSIONS

UPDATE WEB_SESSIONS
SET utm_source   = NULLIF(utm_source, 'NULL'),
    utm_campaign = NULLIF(utm_campaign, 'NULL'),
    utm_content  = NULLIF(utm_content, 'NULL'),
    http_referer = NULLIF(http_referer, 'NULL')

/*----------------------------------------------------------------------------------------------                    
                          1. PRODUCTS
----------------------------------------------------------------------------------------------*/
SELECT * FROM products

-- FINDING DUPLICATES
-- [FIX] The original query listed every product with a row number but never filtered,
--       so it did not actually show duplicates. Wrapped it and kept only ROWN > 1 (same as the other tables).

SELECT *
FROM (
    SELECT *,
    ROW_NUMBER() OVER(PARTITION BY PRODUCT_ID ORDER BY PRODUCT_ID) AS ROWN
    FROM products
    ) AS T
WHERE ROWN > 1

-- CHECK FOR DATA TYPE

SELECT COLUMN_NAME,DATA_TYPE
 FROM INFORMATION_SCHEMA.COLUMNS
 WHERE TABLE_NAME = 'PRODUCTS'

 -- NULL ANALYSIS

 SELECT 
 COUNT(CASE WHEN PRODUCT_ID IS NULL THEN 1 END) AS PRODUCT_ID,
 COUNT(CASE WHEN CREATED_AT IS NULL THEN 1 END) AS CREATION,
 COUNT(CASE WHEN PRODUCT_NAME IS NULL THEN 1 END) PRODUCT_NAME
 FROM products