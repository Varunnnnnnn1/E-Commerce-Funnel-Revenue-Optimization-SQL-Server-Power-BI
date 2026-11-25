
/****************************************************************************************
						Phase 5: COHORT Analysis 
*****************************************************************************************/

--SELECT * FROM ORDERS

--USE WEBANALYSIS


-- Step 1 — Find each customer's first purchase

WITH FIRST_PURCHASE AS
(
SELECT 
	USER_ID,
	MIN(CREATED_AT) AS FIRST_PURCHASE_DATE,
	FORMAT(MIN(CREATED_AT),'yyyy-MM') AS COHORT_MONTH
FROM ORDERS
GROUP BY USER_ID
) 

-- Join back to all orders

, COHORT_DATA
AS(
SELECT 
F.USER_ID,
COHORT_MONTH,
DATEDIFF(MONTH,FIRST_PURCHASE_DATE, created_at) AS MONTHS_SINCE_FIRST
FROM FIRST_PURCHASE AS F
LEFT JOIN ORDERS AS O
ON F.user_id = O.user_id
)

-- Count customers per cohort per month

, COHORT_COUNTS AS (
    SELECT
        cohort_month,
        months_since_first,
        COUNT(DISTINCT user_id) AS customers
    FROM COHORT_DATA
    GROUP BY cohort_month, months_since_first
)

-- Step 4 — Get cohort size (Month 0 count)

, COHORT_SIZE AS (
    SELECT
        cohort_month,
        customers AS cohort_size
    FROM COHORT_COUNTS
    WHERE months_since_first = 0
)

-- Step 5 — Calculate retention % and PIVOT

, RETENTION AS (
    SELECT
        C.cohort_month,
        C.months_since_first,
        ROUND(C.customers * 100.0 / S.cohort_size, 1) AS retention_pct
    FROM COHORT_COUNTS AS C
    LEFT JOIN COHORT_SIZE AS S
        ON C.cohort_month = S.cohort_month
)
-- [FIX] The original ISNULL(...,0) showed 0.0% for months that have not happened yet (e.g. M6 for the
--       Jan-2015 cohort, since data ends 19 Mar 2015). That reads as "nobody came back" when it really
--       means "not observable". Now: 0.0 only if the month is inside the data window, otherwise NULL.
--       OBS = number of whole months between the cohort month and the last order month.
, OBS AS (
    SELECT
        cohort_month,
        DATEDIFF(MONTH, CAST(CONCAT(cohort_month, '-01') AS DATE), (SELECT MAX(created_at) FROM ORDERS)) AS max_m
    FROM COHORT_SIZE
)
SELECT
    PT.COHORT_MONTH,
    CAST(ISNULL([0],0)  AS DECIMAL(5,1)) AS M0,
    CAST(CASE WHEN OBS.max_m >= 1  THEN ISNULL([1],0)  END AS DECIMAL(5,1)) AS M1,
    CAST(CASE WHEN OBS.max_m >= 2  THEN ISNULL([2],0)  END AS DECIMAL(5,1)) AS M2,
    CAST(CASE WHEN OBS.max_m >= 3  THEN ISNULL([3],0)  END AS DECIMAL(5,1)) AS M3,
    CAST(CASE WHEN OBS.max_m >= 4  THEN ISNULL([4],0)  END AS DECIMAL(5,1)) AS M4,
    CAST(CASE WHEN OBS.max_m >= 5  THEN ISNULL([5],0)  END AS DECIMAL(5,1)) AS M5,
    CAST(CASE WHEN OBS.max_m >= 6  THEN ISNULL([6],0)  END AS DECIMAL(5,1)) AS M6,
    CAST(CASE WHEN OBS.max_m >= 7  THEN ISNULL([7],0)  END AS DECIMAL(5,1)) AS M7,
    CAST(CASE WHEN OBS.max_m >= 8  THEN ISNULL([8],0)  END AS DECIMAL(5,1)) AS M8,
    CAST(CASE WHEN OBS.max_m >= 9  THEN ISNULL([9],0)  END AS DECIMAL(5,1)) AS M9,
    CAST(CASE WHEN OBS.max_m >= 10 THEN ISNULL([10],0) END AS DECIMAL(5,1)) AS M10,
    CAST(CASE WHEN OBS.max_m >= 11 THEN ISNULL([11],0) END AS DECIMAL(5,1)) AS M11,
    CAST(CASE WHEN OBS.max_m >= 12 THEN ISNULL([12],0) END AS DECIMAL(5,1)) AS M12
FROM RETENTION
PIVOT (
    SUM(retention_pct)
    FOR months_since_first IN (
        [0],[1],[2],[3],[4],[5],[6],
        [7],[8],[9],[10],[11],[12]
    )
) AS PT
JOIN OBS ON OBS.cohort_month = PT.cohort_month
ORDER BY PT.COHORT_MONTH;
-- [NOTE] DATEDIFF(MONTH, ...) counts calendar-month boundaries: an order on 31 Jan and one on 1 Feb are
--        "1 month apart". That is the usual cohort convention; just be aware of it when quoting M1.





