
/*************************************************************************************************
                               TABLE CREATION AND DATA IMPORT
**************************************************************************************************/

CREATE TABLE order_items (
    order_item_id INT PRIMARY KEY,
    created_at DATETIME,
    order_id INT,
    product_id INT,
    is_primary_item BIT,
    price_usd DECIMAL(10,2),
    cogs_usd DECIMAL(10,2)
);

SELECT * FROM order_items

BULK INSERT ORDER_ITEMS
FROM 'D:\Data Science\SQL queries\PROJECTS\factory\order_items.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n')


/***********************************************************************************************/

CREATE TABLE ORDERS (
    order_id INT PRIMARY KEY,
    created_at DATETIME,
    website_session_id INT,
    user_id INT,
    primary_product_id INT,
    items_purchased INT,
    price_usd DECIMAL(10,2),
    cogs_usd DECIMAL(10,2)
    )

    SELECT * FROM ORDERS

BULK INSERT orders
FROM 'D:\Data Science\SQL queries\PROJECTS\factory\orders.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    TABLOCK,
    CODEPAGE = '65001',
    FORMAT = 'CSV'
);


/***********************************************************************************************/

CREATE TABLE REFUNDS(
    order_item_refund_id INT,
    created_at DATETIME,
    order_item_id INT,
    order_id INT,
    refund_amount_usd DECIMAL(10,2)
    )

SELECT * FROM REFUNDS

BULK INSERT REFUNDS
    FROM 'D:\Data Science\SQL queries\PROJECTS\factory\order_item_refunds.csv'
    WITH (
        FIRSTROW = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR = '\n'
        )


/***********************************************************************************************/


CREATE TABLE PAGEVIEW(
    website_pageview_id INT,
    created_at DATETIME,
    website_session_id INT,
    pageview_url VARCHAR(255)
    )

    SELECT * FROM PAGEVIEW

    BULK INSERT pageview
    FROM 'D:\Data Science\SQL queries\PROJECTS\factory\website_pageviews.csv'
    WITH (
        FORMAT = 'CSV',
        FIRSTROW = 2,
        FIELDQUOTE = '"',
        FIELDTERMINATOR = ',',
        ROWTERMINATOR = '0x0a',
        CODEPAGE = '65001',
        TABLOCK
);

/***********************************************************************************************/

CREATE TABLE WEB_SESSIONS
    (
    website_session_id INT,
    created_at DATETIME,
    user_id INT,
    is_repeat_session INT,
    utm_source VARCHAR(255),
    utm_campaign VARCHAR(255),
    utm_content VARCHAR(255),
    device_type VARCHAR(255),
    http_referer VARCHAR(255)
    )

BULK INSERT WEB_SESSIONS
   FROM 'D:\Data Science\SQL queries\PROJECTS\factory\website_sessions.csv'
   WITH (
        FORMAT = 'CSV',
        FIRSTROW = 2,
        FIELDQUOTE = '"',
        FIELDTERMINATOR = ',',
        ROWTERMINATOR = '0x0d0a',   -- [FIX] was '0x0a'. This CSV has Windows (CRLF) line endings, so '0x0a'
                                    --       left a hidden CHAR(13) at the end of the last column on every row
                                    --       (verified on SQL Server 2022). Pageviews CSV is LF-only, so it keeps '0x0a'.
        CODEPAGE = '65001',
        TABLOCK
        )
   
   SELECT * FROM WEB_SESSIONS

-- [FIX] NOTE: missing values in website_sessions.csv are stored as the TEXT 'NULL' (83,328 rows for
-- utm_source / utm_campaign / utm_content). BULK INSERT loads them as the string 'NULL', not as real
-- NULLs, so "IS NULL" checks return 0. They are converted to real NULLs in P1_DATA_CLEANING (step 4).


/***********************************************************************************************/

-- [FIX] ADDED: the PRODUCTS table was used in Phase 4 and in cleaning, but was never created/imported here.

CREATE TABLE PRODUCTS (
    product_id INT PRIMARY KEY,
    created_at DATETIME,
    product_name VARCHAR(255)
    )

BULK INSERT PRODUCTS
   FROM 'D:\Data Science\SQL queries\PROJECTS\factory\products.csv'
   WITH (
        FORMAT = 'CSV',
        FIRSTROW = 2,
        FIELDQUOTE = '"',
        FIELDTERMINATOR = ',',
        ROWTERMINATOR = '0x0d0a',   -- [FIX] was '0x0a'. This CSV has Windows (CRLF) line endings, so '0x0a'
                                    --       left a hidden CHAR(13) at the end of the last column on every row
                                    --       (verified on SQL Server 2022). Pageviews CSV is LF-only, so it keeps '0x0a'.
        CODEPAGE = '65001',
        TABLOCK
        )

   SELECT * FROM PRODUCTS


/***********************************************************************************************/









