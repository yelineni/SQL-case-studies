-- =====================================================================
-- Customer retention & monthly cohort analysis (SQL Server / T-SQL)
-- Database: Brazilian
-- Tables:   olist_orders_dataset, olist_customers_dataset
-- =====================================================================
USE Brazilian;
GO

-- ---------------------------------------------------------------------
-- PART 0: DATA QUALITY CHECKS (run these before trusting anything)
-- ---------------------------------------------------------------------

-- 0.1 Why we need customer_unique_id: orders vs. customer_id vs. real people
SELECT
    COUNT(*)                             AS orders,
    COUNT(DISTINCT o.customer_id)        AS distinct_customer_ids,     -- ~ equals orders
    COUNT(DISTINCT c.customer_unique_id) AS distinct_real_customers
FROM olist_orders_dataset o
JOIN olist_customers_dataset c ON c.customer_id = o.customer_id;

-- 0.2 Orphan keys: orders without a matching customer (expect 0)
SELECT COUNT(*) AS orphan_orders
FROM olist_orders_dataset o
LEFT JOIN olist_customers_dataset c ON c.customer_id = o.customer_id
WHERE c.customer_id IS NULL;

-- 0.3 Which statuses exist? Decide what counts as a real purchase.
SELECT order_status, COUNT(*) AS n
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY n DESC;

-- 0.4 Monthly order volume: reveals sparse start / partial end months
SELECT
    DATEFROMPARTS(YEAR(order_purchase_timestamp), MONTH(order_purchase_timestamp), 1) AS order_month,
    COUNT(*) AS orders
FROM olist_orders_dataset
GROUP BY DATEFROMPARTS(YEAR(order_purchase_timestamp), MONTH(order_purchase_timestamp), 1)
ORDER BY order_month;
-- Finding to document: the earliest months have very few orders and the
-- final month is incomplete. Cohorts from those months distort the matrix,
-- so the analysis window below excludes them.

-- ---------------------------------------------------------------------
-- PART 1: COHORT RETENTION MATRIX (long format)
-- ---------------------------------------------------------------------
-- Definitions (state these in the README too):
--   * Customer      = customer_unique_id
--   * Valid order   = status not 'canceled' or 'unavailable'
--   * Cohort month  = month of the customer's first valid order
--   * Retained in month N = customer placed >= 1 valid order N months after
--                           their cohort month (N = 0 is the acquisition month)

WITH valid_orders AS (
    SELECT
        c.customer_unique_id,
        DATEFROMPARTS(YEAR(o.order_purchase_timestamp),
                      MONTH(o.order_purchase_timestamp), 1) AS order_month
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),
customer_months AS (
    -- One row per customer per active month (dedupes multiple orders in a month)
    SELECT DISTINCT customer_unique_id, order_month
    FROM valid_orders
),
cohorts AS (
    SELECT
        customer_unique_id,
        order_month,
        MIN(order_month) OVER (PARTITION BY customer_unique_id) AS cohort_month
    FROM customer_months
),
indexed AS (
    -- Both dates are first-of-month, so DATEDIFF(MONTH) is exact here.
    -- Computed in its own CTE because T-SQL can't GROUP BY a column alias.
    SELECT
        customer_unique_id,
        cohort_month,
        DATEDIFF(MONTH, cohort_month, order_month) AS month_index
    FROM cohorts
),
cohort_activity AS (
    SELECT
        cohort_month,
        month_index,
        COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM indexed
    GROUP BY cohort_month, month_index
),
cohort_size AS (
    SELECT cohort_month, active_customers AS cohort_customers
    FROM cohort_activity
    WHERE month_index = 0
)
SELECT
    a.cohort_month,
    s.cohort_customers,
    a.month_index,
    a.active_customers,
    ROUND(100.0 * a.active_customers / s.cohort_customers, 2) AS retention_pct
FROM cohort_activity a
JOIN cohort_size s ON s.cohort_month = a.cohort_month
WHERE a.cohort_month BETWEEN '2017-01-01' AND '2018-06-01'   -- see Part 0.4
  AND a.month_index <= 6
ORDER BY a.cohort_month, a.month_index;

-- ---------------------------------------------------------------------
-- PART 2: PIVOTED MATRIX (one row per cohort, easy to screenshot)
-- ---------------------------------------------------------------------
WITH customer_months AS (
    SELECT DISTINCT
        c.customer_unique_id,
        DATEFROMPARTS(YEAR(o.order_purchase_timestamp),
                      MONTH(o.order_purchase_timestamp), 1) AS order_month
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
),
cohorts AS (
    SELECT
        customer_unique_id,
        order_month,
        MIN(order_month) OVER (PARTITION BY customer_unique_id) AS cohort_month
    FROM customer_months
),
indexed AS (
    SELECT
        cohort_month,
        customer_unique_id,
        DATEDIFF(MONTH, cohort_month, order_month) AS month_index
    FROM cohorts
)
SELECT
    cohort_month,
    COUNT(DISTINCT CASE WHEN month_index = 0 THEN customer_unique_id END) AS m0_customers,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_index = 1 THEN customer_unique_id END)
          / NULLIF(COUNT(DISTINCT CASE WHEN month_index = 0 THEN customer_unique_id END), 0), 2) AS m1_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_index = 2 THEN customer_unique_id END)
          / NULLIF(COUNT(DISTINCT CASE WHEN month_index = 0 THEN customer_unique_id END), 0), 2) AS m2_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_index = 3 THEN customer_unique_id END)
          / NULLIF(COUNT(DISTINCT CASE WHEN month_index = 0 THEN customer_unique_id END), 0), 2) AS m3_pct,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN month_index = 6 THEN customer_unique_id END)
          / NULLIF(COUNT(DISTINCT CASE WHEN month_index = 0 THEN customer_unique_id END), 0), 2) AS m6_pct
FROM indexed
WHERE cohort_month BETWEEN '2017-01-01' AND '2018-06-01'
GROUP BY cohort_month
ORDER BY cohort_month;

-- ---------------------------------------------------------------------
-- PART 3: SANITY CHECK - overall repeat-purchase rate
-- ---------------------------------------------------------------------
-- The cohort numbers should be consistent with this headline figure.
WITH per_customer AS (
    SELECT c.customer_unique_id, COUNT(*) AS order_count
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*)                                          AS customers,
    SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END)  AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct
FROM per_customer;
