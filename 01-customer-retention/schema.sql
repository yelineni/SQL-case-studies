-- Schema for customer retention case study
-- PostgreSQL dialect

-- Customers table: one row per user
CREATE TABLE IF NOT EXISTS customers (
  customer_id BIGSERIAL PRIMARY KEY,
  email TEXT,
  signup_date DATE NOT NULL,
  country VARCHAR(100),
  signup_channel VARCHAR(50),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Subscriptions: tracks recurring plans per customer
CREATE TABLE IF NOT EXISTS subscriptions (
  subscription_id BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
  plan VARCHAR(50) NOT NULL,
  start_date DATE NOT NULL,
  end_date DATE,
  status VARCHAR(20) NOT NULL CHECK (status IN ('active','cancelled','past_due','trial','paused')),
  price NUMERIC(10,2),
  billing_period VARCHAR(20),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Transactions / payments table
CREATE TABLE IF NOT EXISTS transactions (
  transaction_id BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
  subscription_id BIGINT REFERENCES subscriptions(subscription_id) ON DELETE SET NULL,
  amount NUMERIC(12,2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'USD',
  transaction_date TIMESTAMP WITH TIME ZONE NOT NULL,
  payment_method VARCHAR(50),
  success BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Churn events: explicit cancellation or involuntary churn
CREATE TABLE IF NOT EXISTS churn_events (
  churn_id BIGSERIAL PRIMARY KEY,
  customer_id BIGINT NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
  churn_date DATE NOT NULL,
  reason TEXT,
  involuntary BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Optional: product table if multiple SKUs exist
CREATE TABLE IF NOT EXISTS products (
  product_id BIGSERIAL PRIMARY KEY,
  sku TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  price NUMERIC(10,2) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Indexes to speed up cohort/retention queries
CREATE INDEX IF NOT EXISTS idx_customers_signup_date ON customers(signup_date);
CREATE INDEX IF NOT EXISTS idx_subscriptions_customer_start ON subscriptions(customer_id, start_date);
CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_churn_customer_date ON churn_events(customer_id, churn_date);

-- Views to help with retention/cohort analysis

-- Cohort: assign each customer to a monthly signup cohort (YYYY-MM)
CREATE OR REPLACE VIEW customer_monthly_cohort AS
SELECT
  customer_id,
  to_char(date_trunc('month', signup_date), 'YYYY-MM') AS cohort_month,
  signup_date
FROM customers;

-- Monthly active indicator for customers (did they have any active subscription or transaction in a month)
CREATE OR REPLACE VIEW monthly_activity AS
SELECT
  c.customer_id,
  to_char(date_trunc('month', d.activity_month), 'YYYY-MM') AS activity_month,
  d.activity_month AS month_start,
  CASE WHEN EXISTS (
    SELECT 1 FROM transactions t
    WHERE t.customer_id = c.customer_id
      AND date_trunc('month', t.transaction_date) = date_trunc('month', d.activity_month)
  ) OR EXISTS (
    SELECT 1 FROM subscriptions s
    WHERE s.customer_id = c.customer_id
      AND (s.start_date <= d.activity_month::date)
      AND (s.end_date IS NULL OR s.end_date >= d.activity_month::date)
  ) THEN 1 ELSE 0 END AS active
FROM customers c
CROSS JOIN LATERAL (
  SELECT generate_series(
    date_trunc('month', c.signup_date)::timestamp,
    date_trunc('month', now())::timestamp,
    interval '1 month'
  ) AS activity_month
) d;

-- Cohort retention view: for each signup cohort and month N, percent retained
CREATE OR REPLACE VIEW cohort_retention AS
WITH cohorts AS (
  SELECT customer_id, to_char(date_trunc('month', signup_date), 'YYYY-MM') AS cohort_month, date_trunc('month', signup_date) AS cohort_start
  FROM customers
),
activity AS (
  SELECT
    m.customer_id,
    to_char(date_trunc('month', m.month_start), 'YYYY-MM') AS month,
    date_trunc('month', m.month_start) AS month_start,
    m.active
  FROM monthly_activity m
)
SELECT
  c.cohort_month,
  to_char(a.month_start, 'YYYY-MM') AS activity_month,
  date_part('month', age(a.month_start, c.cohort_start))::int AS months_after_signup,
  COUNT(DISTINCT c.customer_id) FILTER (WHERE a.active = 1) AS retained_customers,
  COUNT(DISTINCT c.customer_id) AS cohort_size,
  ROUND( (COUNT(DISTINCT c.customer_id) FILTER (WHERE a.active = 1))::numeric
         / NULLIF(COUNT(DISTINCT c.customer_id),0) * 100, 2) AS retention_pct
FROM cohorts c
JOIN activity a
  ON a.customer_id = c.customer_id
WHERE a.month_start >= c.cohort_start
GROUP BY c.cohort_month, a.month_start
ORDER BY c.cohort_month, months_after_signup;

-- Helpful utility: latest_subscription per customer
CREATE OR REPLACE VIEW latest_subscription AS
SELECT DISTINCT ON (customer_id)
  subscription_id, customer_id, plan, start_date, end_date, status
FROM subscriptions
ORDER BY customer_id, start_date DESC;

-- End of schema
