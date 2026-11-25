
/****************************************************************************************

					PHASE 2 - DESCRIPTIVE KPI's 

******************************************************************************************/
USE WEBANALYSIS


SELECT * FROM ORDERS
SELECT * FROM order_items
SELECT * FROM PAGEVIEW
SELECT * FROM WEB_SESSIONS
SELECT * FROM REFUNDS

/*--------------------------------------------------------------

1.Business Question
How is revenue, order volume, and average order value trending month over month across 3 years?

----------------------------------------------------------------*/
USE WEBANALYSIS


SELECT 
	DATEPART(YEAR,CREATED_AT) AS YEAR,
	DATEPART(MONTH,created_at) AS MONTH,
	SUM(PRICE_USD) AS TOTAL_REVENUE,
	COUNT(order_id) AS TOTAL_ORDERS,
	SUM(PRICE_USD) / COUNT(order_id) AS AVERAGE_ORDER
FROM ORDERS
GROUP BY 
	DATEPART(YEAR,CREATED_AT),DATEPART(MONTH,created_at)
ORDER BY 
	DATEPART(YEAR,CREATED_AT),DATEPART(MONTH,created_at);   -- [FIX] ';' needed before the next WITH



-- YEARLY TREND --------------------------------------------

with CTE
AS 
(
SELECT 
	DATEPART(YEAR,CREATED_AT) AS YEAR,
	DATEPART(MONTH,created_at) AS MONTH,
	SUM(PRICE_USD) AS TOTAL_REVENUE,
	COUNT(order_id) AS TOTAL_ORDERS,
	SUM(PRICE_USD) / COUNT(order_id) AS AVERAGE_ORDER
FROM ORDERS
GROUP BY 
	DATEPART(YEAR,CREATED_AT),DATEPART(MONTH,created_at)
)
SELECT 
	YEAR,
	SUM(TOTAL_REVENUE) AS REVENUE_YEAR,
	SUM(TOTAL_ORDERS) AS TOTAL_ORDER,
	-- [FIX] was AVG(AVERAGE_ORDER): an average of 12 monthly AOVs gives every month equal weight
	--       regardless of order volume. True yearly AOV = yearly revenue / yearly orders.
	--       Effect: 2013 AOV 52.48 -> 52.81, 2014 63.71 -> 63.80 (2012 and 2015 change by < 0.02).
	SUM(TOTAL_REVENUE) / SUM(TOTAL_ORDERS) AS AVG_YEAR_ORDER
FROM CTE
GROUP BY YEAR
ORDER BY YEAR ASC;
-- [NOTE] 2012 starts on 19 Mar and 2015 ends on 19 Mar, so both are partial years.



-- MONTHLY ---------------------------------------------

with CTE1
AS 
(
SELECT 
	DATEPART(YEAR,CREATED_AT) AS YEAR,
	DATEPART(MONTH,created_at) AS MONTH,
	SUM(PRICE_USD) AS TOTAL_REVENUE,
	COUNT(order_id) AS TOTAL_ORDERS,
	SUM(PRICE_USD) / COUNT(order_id) AS AVERAGE_ORDER
FROM ORDERS
GROUP BY 
	DATEPART(YEAR,CREATED_AT),DATEPART(MONTH,created_at)
)

SELECT 
	MONTH,
	SUM(TOTAL_REVENUE) AS REVENUE_MONTH,
	SUM(TOTAL_ORDERS) AS TOTAL_ORDER,
	-- [FIX] was AVG(AVERAGE_ORDER) (average of the yearly AOVs for that month). Use revenue / orders.
	--       Effect: e.g. January 57.27 -> 60.16, December 56.07 -> 59.06.
	SUM(TOTAL_REVENUE) / SUM(TOTAL_ORDERS) AS AVERAGE_1
FROM CTE1
GROUP BY MONTH
ORDER BY MONTH;








-- MONTH OVER MONTH

WITH MONTHLY_REVENUE
AS(
SELECT 
	DATEPART(YEAR,created_at) AS YEARS,
	DATEPART(MONTH,created_at) AS MONTHS,
	SUM(PRICE_USD) AS SALES,
	COUNT(ORDER_ID) AS ORDERS,
	SUM(PRICE_USD) / COUNT(ORDER_ID) AS AVG_ORDER
FROM ORDERS
GROUP BY 
	DATEPART(YEAR,created_at),
	DATEPART(MONTH,created_at)
)

SELECT 
	YEARS,
	MONTHS,
	SALES,
	LAG(SALES) OVER(ORDER BY YEARS,MONTHS) AS PREVIOUS_MONTH_SALE,
	-- GROWTH RATE = (CURRENT - PREVIOUS) / PREVIOUS * 100
	ROUND((SALES - LAG(SALES) OVER(ORDER BY YEARS,MONTHS)) / LAG(SALES) 
			OVER(ORDER BY YEARS,MONTHS) *100,2) AS GROWTH_RATE
FROM MONTHLY_REVENUE
-- [NOTE] March 2012 and March 2015 are partial months (data starts/ends on the 19th), so the first
--        and last growth rates are not like-for-like.
GO   -- [FIX] CREATE VIEW must be the first statement in a batch


-- ************************************************************************************

-- MONTH OVER MONTH ANALYSIS


CREATE OR ALTER VIEW MOM AS

WITH CTE1
AS (
SELECT 
	DATEPART(YEAR,created_at) AS YEARS,
	DATEPART(MONTH,created_at) AS MONTHS,
	SUM(price_usd) AS TOTAL_SALE
FROM ORDERS
GROUP BY 
	DATEPART(YEAR,created_at),
	DATEPART(MONTH,created_at) 
)
SELECT 
*,
CASE WHEN MONTHS BETWEEN 1 AND 3 THEN 'Q1'
	 WHEN MONTHS BETWEEN 4 AND 6 THEN 'Q2'
	 WHEN MONTHS BETWEEN 7 AND 9 THEN 'Q3'
	 ELSE 'Q4'
END AS QUARTERS,
SUM(TOTAL_SALE) OVER() AS OVERALL_SALE,
SUM(TOTAL_SALE) OVER(PARTITION BY YEARS) AS TOTAL_IN_YEAR,
SUM(TOTAL_SALE) OVER(PARTITION BY YEARS,
	CASE WHEN MONTHS BETWEEN 1 AND 3 THEN 'Q1'
		 WHEN MONTHS BETWEEN 4 AND 6 THEN 'Q2'
		 WHEN MONTHS BETWEEN 7 AND 9 THEN 'Q3'
		 ELSE 'Q4'
	END ) AS TOTAL_IN_QUARTER
FROM CTE1
GO


--*********************************************************************************--

SELECT * FROM MOM   -- CREATED VIEW FOR ANALYSING


-- [NOTE] 2012 has no Q1 data before 19 Mar, so the 2012 Q4 share (57.8%) is inflated by the partial
--        year; compare 2013 vs 2014 for a like-for-like trend.
SELECT DISTINCT
	YEARS,
	QUARTERS,
	(TOTAL_IN_QUARTER/TOTAL_IN_YEAR) * 100 AS PERCENTA
FROM MOM
WHERE QUARTERS = 'Q4'


-- YEAR OVER YEAR GROWTH RATE
-- [NOTE] Because of WHERE MONTHS = 12, LAG() only sees December rows, so this is December vs the
--        previous December (correct as YoY for December). Column renamed PREVIOUS_YEAR -> PREVIOUS_YEAR_DEC.


SELECT 
YEARS,
MONTHS,
TOTAL_SALE,
TOTAL_IN_YEAR,
LAG(TOTAL_SALE) OVER(ORDER BY YEARS,MONTHS) AS PREVIOUS_YEAR_DEC,
(TOTAL_SALE - LAG(TOTAL_SALE) OVER(ORDER BY YEARS,MONTHS)) / LAG(TOTAL_SALE) OVER(ORDER BY YEARS,MONTHS) * 100 AS G_RATE
FROM MOM
WHERE MONTHS = 12 

