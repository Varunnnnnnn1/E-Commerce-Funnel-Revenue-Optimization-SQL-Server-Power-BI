
/************************************************************************************************

					PHASE 3: TRAFFIC ANALYSIS 

*************************************************************************************************/

SELECT TOP(10)* FROM ORDERS

SELECT TOP(10)* FROM WEB_SESSIONS

/*-----------------------------------------

It should show for each utm_source:

Total sessions
Total orders
Conversion rate
Total revenue

------------------------------------------*/

SELECT 
S.UTM_SOURCE,
COUNT(S.WEBSITE_SESSION_ID) AS TOTAL_SESSIONS,
COUNT(O.ORDER_ID) AS TOTAL_ORDER,
COUNT(O.ORDER_ID) * 100.0 / COUNT(S.WEBSITE_SESSION_ID) AS CONVERSION_RATE,
SUM(O.PRICE_USD) AS TOTAL_REVENUE
FROM WEB_SESSIONS AS S
LEFT JOIN ORDERS AS O
ON S.website_session_id = O.website_session_id
GROUP BY S.utm_source
-- [NOTE] The NULL utm_source row (83,328 sessions, 7.34%) is ALL untagged traffic: organic search
--        (http_referer present, 43,411 sessions, 7.51%) plus direct type-in (no referer, 39,917
--        sessions, 7.15%). The report calls 7.34% "organic"; organic alone is 7.51%. Split it with:
--        CASE WHEN utm_source IS NULL AND http_referer IS NOT NULL THEN 'organic'
--             WHEN utm_source IS NULL THEN 'direct' ELSE utm_source END
--        (requires the 'NULL' text -> NULL conversion in P1_DATA_CLEANING step 4).


-- The marketing team will ask: "Within gsearch, which campaigns perform best?"

SELECT 
S.utm_campaign,
COUNT(S.WEBSITE_SESSION_ID) AS TOTAL_SESSIONS,
COUNT(O.ORDER_ID) AS TOTAL_ORDER,
COUNT(O.ORDER_ID) * 100.0 / COUNT(S.WEBSITE_SESSION_ID) AS CONVERSION_RATE,
SUM(O.PRICE_USD) AS TOTAL_REVENUE
FROM WEB_SESSIONS AS S
LEFT JOIN ORDERS AS O
ON S.website_session_id = O.website_session_id
WHERE utm_source = 'gsearch'
GROUP BY S.utm_campaign



/* 

"How does gsearch nonbrand perform across different devices — mobile vs desktop?"

*/

SELECT 
device_type,
COUNT(S.WEBSITE_SESSION_ID) AS TOATL_SESSIONS,
COUNT(O.ORDER_ID) AS TOTAL_ORDERS,
SUM(O.PRICE_USD) AS TOTAL_REVENUE,
COUNT(O.ORDER_ID) * 100.0 / COUNT(S.WEBSITE_SESSION_ID) AS CONVERSION_RATE
FROM WEB_SESSIONS AS S
LEFT JOIN ORDERS AS O
ON S.website_session_id = O.website_session_id
WHERE utm_source = 'gsearch' AND utm_campaign = 'nonbrand'
GROUP BY device_type


/*
FINDING HOW MUCH REVENUE GAP IN PLACE OF MOBILE CONVERSION
  DESKTOP CONVERSION - 8.22
  MOBILE CONVERSION - 3.18
  TOTAL SESSION BY MOBILE - 87551

  - FINDING IF THE CONVERSION RATE OF DESKTOP APPLIED ON MOBILE THEN HOW MUCH REVENUE 
	WE CAN GENERATE
  */
-- [FIX] The original hard-coded calculation is kept below as a comment for reference. Issues:
--   1. "SELECT 87551 *8.22 - 87551 * 3.18 AS DIFF" had no ';', so the WITH after it fails to parse.
--   2. AVG_O * (87551*8.22 - 87551*3.18) multiplied by percentages (8.22) instead of rates (0.0822),
--      so it was 100x too large.
--   3. The final version used a hard-coded $64 AOV. The actual AOV across all 32,313 orders is $59.99
--      (SUM(price_usd) / COUNT(order_id)).
--   4. Rates were rounded to 2 decimals before multiplying.
-- Result: $282,404 (rounded rates, $64)  ->  $264,537 (exact rates, actual AOV $59.99).
-- Scope / assumptions: gsearch nonbrand only, all 3 years, assumes mobile fully reaches the desktop rate,
-- and assumes mobile orders have the same AOV as all orders.
/*
SELECT 
		 87551 *8.22 - 87551 * 3.18 AS DIFF

WITH CTE AS 
(
SELECT 
COUNT(ORDER_ID) AS TOTAL_ORDER,
SUM(PRICE_USD) AS SALE,
SUM(PRICE_USD) / COUNT(ORDER_ID) AS AVG_O
FROM ORDERS ) 

SELECT AVG_O,
	AVG_O * (87551 *8.22 - 87551 * 3.18) FROM CTE


/*
Step 1: 87,551 × 0.0822 = ?
Step 2: 87,551 × 0.0318 = ?
Step 3: (Step1 result - Step2 result) = difference in orders
Step 4: difference in orders × 64 = additional revenue
*/


SELECT 
	87551 * 0.0822 AS STEP_1,
	87551 * 0.0318 AS STEP_2,
	(87551 * 0.0822) - (87551 * 0.0318) AS DIFFEREN,
	(( 87551 * 0.0822) - (87551 * 0.0318) ) * 64 AS REVENUE
*/

;WITH DEVICE_RATES AS (
SELECT 
	S.device_type,
	COUNT(S.website_session_id) AS SESSIONS,
	CAST(COUNT(O.order_id) AS FLOAT) / COUNT(S.website_session_id) AS CONV_RATE
FROM WEB_SESSIONS AS S
LEFT JOIN ORDERS AS O
ON S.website_session_id = O.website_session_id
WHERE S.utm_source = 'gsearch' AND S.utm_campaign = 'nonbrand'
GROUP BY S.device_type
),
AOV AS (
SELECT CAST(SUM(price_usd) AS FLOAT) / COUNT(order_id) AS AVG_ORDER_VALUE FROM ORDERS
)
SELECT 
	M.SESSIONS AS MOBILE_SESSIONS,                                   -- 87,551
	D.CONV_RATE AS DESKTOP_CR,                                       -- 0.0822
	M.CONV_RATE AS MOBILE_CR,                                        -- 0.0318
	M.SESSIONS * (D.CONV_RATE - M.CONV_RATE) AS EXTRA_ORDERS,        -- ~4,410
	A.AVG_ORDER_VALUE,                                               -- 59.99
	M.SESSIONS * (D.CONV_RATE - M.CONV_RATE) * A.AVG_ORDER_VALUE AS REVENUE_GAP   -- ~264,537
FROM DEVICE_RATES AS D
CROSS JOIN DEVICE_RATES AS M
CROSS JOIN AOV AS A
WHERE D.device_type = 'desktop' AND M.device_type = 'mobile';



 /********************************************************************************************
								FUNNEL ANALYSIS
-- *********************************************************************************************/

SELECT DISTINCT pageview_url FROM PAGEVIEW
SELECT * FROM PAGEVIEW

/*
---------------------------------------------------------
FUNNEL :

1. LANDER 
2. HOME
3. PRODUCTS
4. SPECIFIC PRODUCT PAGE
5. CART 
6. SHIPPING DETAILS
7. BILLING
8. THANK YOU
---------------------------------------------------------*/
USE WEBANALYSIS;   -- [FIX] ';' needed before WITH

WITH CTE1 AS
(
SELECT 
	WEBSITE_SESSION_ID,
	MAX(CASE WHEN PAGEVIEW_URL = '/lander-1' THEN 1 ELSE 0 END) AS lander1,
	MAX(CASE WHEN PAGEVIEW_URL = '/lander-2' THEN 1 ELSE 0 END) AS lander2,
	MAX(CASE WHEN PAGEVIEW_URL = '/lander-3' THEN 1 ELSE 0 END) AS lander3,
	MAX(CASE WHEN PAGEVIEW_URL = '/lander-4' THEN 1 ELSE 0 END) AS lander4,
	MAX(CASE WHEN PAGEVIEW_URL = '/lander-5' THEN 1 ELSE 0 END) AS lander5,
	MAX(CASE WHEN PAGEVIEW_URL = '/home' THEN 1 ELSE 0 END) AS home,
	MAX(CASE WHEN PAGEVIEW_URL = '/products' THEN 1 ELSE 0 END) AS products,
	MAX(CASE WHEN PAGEVIEW_URL = '/the-original-mr-fuzzy' THEN 1 ELSE 0 END) AS the_original_mr_fuzzy,
	MAX(CASE WHEN PAGEVIEW_URL = '/the-birthday-sugar-panda' THEN 1 ELSE 0 END) AS SUGAR_PANDA,
	MAX(CASE WHEN PAGEVIEW_URL = '/the-hudson-river-mini-bear' THEN 1 ELSE 0 END) AS the_hudson_river,
	MAX(CASE WHEN PAGEVIEW_URL = '/the-forever-love-bear' THEN 1 ELSE 0 END) AS the_forever_love_bear,
	MAX(CASE WHEN PAGEVIEW_URL = '/cart' THEN 1 ELSE 0 END) AS cart,
	MAX(CASE WHEN PAGEVIEW_URL = '/shipping' THEN 1 ELSE 0 END) AS shipping,
	MAX(CASE WHEN PAGEVIEW_URL = '/billing' THEN 1 ELSE 0 END) AS billing,
	MAX(CASE WHEN PAGEVIEW_URL = '/billing-2' THEN 1 ELSE 0 END) AS billing2,
	MAX(CASE WHEN PAGEVIEW_URL = '/thank-you-for-your-order' THEN 1 ELSE 0 END) AS thankyou
FROM PAGEVIEW
GROUP BY  WEBSITE_SESSION_ID
) 
/*
-- FUNNEL ANALYSIS
, FUNNEL_ANALYSIS AS (
SELECT
	COUNT(website_session_id) AS TOTAL_SESSIONS,
	SUM(CASE WHEN lander1+lander2+lander3+lander4+lander5 >= 1 THEN 1 ELSE 0 END) AS TOTAL_LANDING,
    SUM(home)          AS reached_home,
    SUM(products)      AS reached_products,
	SUM(CASE WHEN (the_original_mr_fuzzy + SUGAR_PANDA +
							the_hudson_river + the_forever_love_bear ) >= 1 THEN 1 ELSE 0 END) AS RECHED_PRODUCT_PAGE,
    SUM(cart)          AS reached_cart,
    SUM(shipping)      AS reached_shipping,
	SUM(CASE WHEN billing+billing2 >= 1 THEN 1 ELSE 0 END) AS reached_billing,
    SUM(thankyou)      AS reached_thankyou
FROM CTE1)*/
SELECT 
	SUM(products)      AS reached_products,
	-- For mr_fuzzy specifically:
	SUM(the_original_mr_fuzzy) AS the_original_mr_fuzzy,
	SUM(CASE WHEN the_original_mr_fuzzy = 1 AND cart = 1 THEN 1 ELSE 0 END) 
    * 100.0 / NULLIF(SUM(the_original_mr_fuzzy), 0) AS mrfuzzy_to_cart_rate,

	SUM(SUGAR_PANDA) AS SUGAR_PANDA,
	SUM(CASE WHEN SUGAR_PANDA = 1 AND cart = 1 THEN 1 ELSE 0 END) 
    * 100.0 / NULLIF(SUM(SUGAR_PANDA), 0) AS SUGAR_PANDA_to_cart_rate,

	SUM(the_hudson_river) AS the_hudson_river,
	SUM(CASE WHEN the_hudson_river = 1 AND cart = 1 THEN 1 ELSE 0 END) 
    * 100.0 / NULLIF(SUM(the_hudson_river), 0) AS the_hudson_river_to_cart_rate,

	SUM(the_forever_love_bear) AS the_forever_love_bear,
	SUM(CASE WHEN the_forever_love_bear = 1 AND cart = 1 THEN 1 ELSE 0 END) 
    * 100.0 / NULLIF(SUM(the_forever_love_bear), 0) AS the_forever_love_bearto_cart_rate,

	SUM(cart) AS CART
FROM CTE1;


/*---------------------------------------------------------------------------------------------
[FIX] ADDED: MR. FUZZY +5PP PRODUCT PAGE -> CART OPPORTUNITY  (the report's "~$322,000")

The report's figure is matched by: 162,525 Mr. Fuzzy sessions x 5pp = 8,126 extra carts
x 62.07% x $64 = $322,820.  62.07% is the BILLING -> THANK-YOU rate, i.e. it assumes every extra
cart reaches billing. An extra cart still has to pass cart -> shipping (67.9%) and
shipping -> billing (80.7%), so the correct rate is CART -> ORDER = 34.03% (Mr. Fuzzy carts: 34.11%).

Corrected: 8,126 x 34.03% x $59.99 = ~$165,901.

Assumptions: the +5pp uplift is hypothetical; extra carts convert like existing carts; AOV unchanged;
the figure covers all 3 years of Mr. Fuzzy traffic (not per year).
---------------------------------------------------------------------------------------------*/

;WITH FLAGS AS (
SELECT 
	website_session_id,
	MAX(CASE WHEN pageview_url = '/the-original-mr-fuzzy' THEN 1 ELSE 0 END) AS mrfuzzy,
	MAX(CASE WHEN pageview_url = '/cart' THEN 1 ELSE 0 END) AS cart,
	MAX(CASE WHEN pageview_url = '/shipping' THEN 1 ELSE 0 END) AS shipping,
	MAX(CASE WHEN pageview_url IN ('/billing','/billing-2') THEN 1 ELSE 0 END) AS billing,
	MAX(CASE WHEN pageview_url = '/thank-you-for-your-order' THEN 1 ELSE 0 END) AS thankyou
FROM PAGEVIEW
GROUP BY website_session_id
),
RATES AS (
SELECT 
	SUM(mrfuzzy) AS MRFUZZY_SESSIONS,                                  -- 162,525
	CAST(SUM(thankyou) AS FLOAT) / SUM(cart)    AS CART_TO_ORDER,      -- 0.3403
	CAST(SUM(thankyou) AS FLOAT) / SUM(billing) AS BILLING_TO_ORDER    -- 0.6207
FROM FLAGS
),
AOV AS (
SELECT CAST(SUM(price_usd) AS FLOAT) / COUNT(order_id) AS AVG_ORDER_VALUE FROM ORDERS
)
SELECT 
	MRFUZZY_SESSIONS,
	MRFUZZY_SESSIONS * 0.05 AS EXTRA_CARTS,                                            -- 8,126
	CART_TO_ORDER,
	BILLING_TO_ORDER,
	AVG_ORDER_VALUE,
	MRFUZZY_SESSIONS * 0.05 * BILLING_TO_ORDER * 64 AS REPORT_METHOD,                  -- ~322,820
	MRFUZZY_SESSIONS * 0.05 * CART_TO_ORDER * AVG_ORDER_VALUE AS CORRECTED_OPPORTUNITY  -- ~165,901
FROM RATES
CROSS JOIN AOV;
