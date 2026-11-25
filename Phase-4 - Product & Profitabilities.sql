/****************************************************************************************
						Phase 4: Product and Profitabilty Analysis 
*****************************************************************************************/
USE WEBANALYSIS;   -- [FIX] ';' needed before the WITH below (SQL Server error 319 otherwise)
/*
Now write the query showing for each product:

Product name
Total units sold
Total revenue
Total COGS
Total profit
Profit margin %
*/


WITH CTE1 AS (

-- [FIX] Removed O.PRICE_USD from SELECT and GROUP BY. Grouping by price splits a product into one
--       row per price point. Each product has a single price in this dataset, so the numbers do not
--       change today, but any price change would silently split the product into several rows.
SELECT 
	P.product_name,
	COUNT(ORDER_ITEM_ID) AS TOTAL_UNIT_SOLD,
	SUM(PRICE_USD) AS TOTAL_REVENUE,
	SUM(COGS_USD) AS TOTAL_COGS,
	SUM(PRICE_USD) - SUM(COGS_USD) AS TOTAL_PROFIT,
	(SUM(PRICE_USD) - SUM(COGS_USD)) / SUM(PRICE_USD) * 100.0 AS PROFIT_PERC
FROM order_items AS O
LEFT JOIN products AS P
ON P.product_id = O.product_id
GROUP BY P.product_name
) 
-- PERCENTAGE OF REVENUE BY PRODUCTS
SELECT 
	PRODUCT_NAME,
	TOTAL_UNIT_SOLD,
	SUM(TOTAL_REVENUE) OVER() AS OVERALL_REVENUE,
	TOTAL_REVENUE,
	TOTAL_REVENUE / SUM(TOTAL_REVENUE) OVER() * 100.0 AS PERCN
FROM CTE1


/****************************************************************************************
						Phase 5: REFUND Analysis 
*****************************************************************************************/

SELECT * FROM REFUNDS

/*
Now build the refund analysis.

Which tables do you need to calculate refund rate per product? 
Tell me the tables and join keys before writing the query.
-------------------------------------------------------
order_item_refunds >  order_items >  products
-------------------------------------------
Now write the query showing per product:

Total units sold
Total refunds
Refund rate %
Total refund amount lost
--------------------------------------------*/

SELECT 
P.product_name,
COUNT(O.order_item_id) AS TOTAL_UNIT,
COUNT(R.ORDER_ITEM_REFUND_ID) AS TOTAL_REFUND,
-- [FIX] COALESCE(COUNT(...),0) did nothing (COUNT never returns NULL) and would not have prevented a
--       divide-by-zero anyway. NULLIF(...,0) is the correct guard.
(COUNT(R.ORDER_ITEM_REFUND_ID) * 100.0 ) / NULLIF(COUNT(O.order_item_id),0) AS REFUND_RATE,
-- [FIX] ISNULL so a product with no refunds shows 0 instead of NULL
ISNULL(SUM(R.REFUND_AMOUNT_USD),0) AS TOTAL_REFUND_AMOUNT
FROM order_items AS O
LEFT JOIN REFUNDS AS R
ON R.order_item_id = O.order_item_id
LEFT JOIN products AS P
ON O.product_id = P.product_id
GROUP BY P.product_name



/****************************************************************************************
						Phase 4 & 5: COMBINE Analysis 
*****************************************************************************************/

/*

Product name
Gross revenue
Total refunds amount
Net revenue (gross - refunds)
Total COGS
Net profit (net revenue - COGS)
Net margin %

*/

USE WEBANALYSIS;   -- [FIX] ';' needed before the WITH below (SQL Server error 319 otherwise)

WITH CTE1 AS 
( 
SELECT
	P.product_name,
	-- [FIX] ISNULL around the refund sum: if a product had no refunds, SUM(R.REFUND_AMOUNT_USD) is NULL
	--       and NET_REVENUE / NET_PROFIT would become NULL. (All 4 products have refunds today, so the
	--       current figures are unchanged.)
	SUM(O.PRICE_USD) AS GROSS_REVENUE,
	ISNULL(SUM(R.REFUND_AMOUNT_USD),0) AS TOTAL_REFUND,
	SUM(O.PRICE_USD) - ISNULL(SUM(R.REFUND_AMOUNT_USD),0) AS NET_REVENUE,
	SUM(O.COGS_USD) AS TOTAL_COGS,
	(SUM(O.PRICE_USD) - ISNULL(SUM(R.REFUND_AMOUNT_USD),0)) - SUM(O.COGS_USD) AS NET_PROFIT
FROM order_items AS O
LEFT JOIN REFUNDS AS R
ON O.order_item_id = R.order_item_id
LEFT JOIN products AS P
ON O.product_id = P.product_id
GROUP BY P.product_name
)
-- [NOTE] NET_MAGIN_PER divides by GROSS revenue (this is what the report's 68.5% -> 62.45% Sugar Panda
--        figure uses; exact value 62.46%). Margin on NET revenue is added for reference.
SELECT 
	*,
	NET_PROFIT / GROSS_REVENUE * 100.0 AS NET_MAGIN_PER,
	NET_PROFIT / NULLIF(NET_REVENUE,0) * 100.0 AS NET_MARGIN_ON_NET_REV
	FROM CTE1