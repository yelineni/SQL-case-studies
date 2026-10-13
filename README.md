# Customer Retention & Cohort Analysis

**Database:** SQL Server (T-SQL) | **Dataset:** [Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)

## Business question
Of the customers we acquire each month, how many come back, and when? Is retention improving across cohorts?

## Approach
1. Audited the data first (`analysis.sql`, Part 0).
2. Defined a customer as `customer_unique_id`, because `customer_id` is generated per order and would make every customer look new.
3. Excluded canceled/unavailable orders and trimmed the sparse first months and the incomplete last month.
4. Assigned each customer to the cohort of their first valid order, computed months since acquisition, and divided by cohort size.
5. Cross-checked the matrix against the overall repeat-purchase rate (Part 3).

## Key SQL techniques
`DATEFROMPARTS`, `MIN() OVER (PARTITION BY ...)`, `DATEDIFF`, conditional `COUNT(DISTINCT CASE ...)`, `NULLIF` to avoid divide-by-zero, layered CTEs.

## Assumptions and limitations
- Retention is "ordered again in month N", not "ordered every month".
- Calendar-month cohorts mean a customer acquired on the 31st and one acquired on the 1st land in the same cohort despite different time windows.
- Revenue retention is not covered here (a natural extension using `order_items`).

## Findings
_Fill in after running. Example structure:_
- Overall repeat rate: **X%**
- Month-1 retention averages **X%**, month-6 **X%**
- Notable cohort differences: ...

## Recommendation
_What would you do with this? E.g. target post-purchase campaigns at the 30-60 day window where return probability is highest._

## Reproduce
1. Create the tables with `schema.sql` and load the two CSVs (SSMS: Tasks > Import Flat File).
2. Run `analysis.sql` one part at a time.
