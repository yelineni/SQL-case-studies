-- Customer retention case study: schema (SQL Server / T-SQL)
-- Dataset: Olist Brazilian E-Commerce (Kaggle)
-- Needs two CSVs: olist_customers_dataset.csv, olist_orders_dataset.csv
-- Load the CSVs with SSMS: right-click the database > Tasks > Import Flat File,
-- or use BULK INSERT after creating the tables below.

IF DB_ID('Brazilian') IS NULL CREATE DATABASE Brazilian;
GO
USE Brazilian;
GO

DROP TABLE IF EXISTS olist_orders_dataset;      -- child first (foreign key)
DROP TABLE IF EXISTS olist_customers_dataset;

CREATE TABLE olist_customers_dataset (
    customer_id              VARCHAR(32)  NOT NULL PRIMARY KEY,  -- one per ORDER, not per person
    customer_unique_id       VARCHAR(32)  NOT NULL,              -- the real customer identity
    customer_zip_code_prefix VARCHAR(10)  NULL,
    customer_city            VARCHAR(100) NULL,
    customer_state           VARCHAR(5)   NULL
);

CREATE TABLE olist_orders_dataset (
    order_id                       VARCHAR(32) NOT NULL PRIMARY KEY,
    customer_id                    VARCHAR(32) NOT NULL
        REFERENCES olist_customers_dataset(customer_id),
    order_status                   VARCHAR(20) NOT NULL,
    order_purchase_timestamp       DATETIME2   NOT NULL,
    order_approved_at              DATETIME2   NULL,
    order_delivered_carrier_date   DATETIME2   NULL,
    order_delivered_customer_date  DATETIME2   NULL,
    order_estimated_delivery_date  DATETIME2   NULL
);

CREATE INDEX idx_orders_customer  ON olist_orders_dataset(customer_id);
CREATE INDEX idx_customers_unique ON olist_customers_dataset(customer_unique_id);
GO
