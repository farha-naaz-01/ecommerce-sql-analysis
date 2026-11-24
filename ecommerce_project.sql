/* =====================================================================
   E-COMMERCE SALES ANALYSIS USING SQL (PostgreSQL)

   Dataset : synthetic e-commerce data, 8 tables
             (customers, sellers, categories, products,
              orders, order_items, payments, reviews)
   Period  : Jan 2023 - Dec 2024

   Sections
     1. Create tables
     2. Row count and null checks (raw tables)
     3. Join all tables into one analysis table
     4. Data cleaning checks and the final clean table
     5. Business analysis

   NOTE: Run section by section, not the whole file at once.
   Load the CSV files after section 1, in this order:
   customers, sellers, categories, products,
   orders, order_items, payments, reviews.
   ===================================================================== */


/* =====================================================================
   1. CREATE TABLES
   ===================================================================== */
CREATE TABLE customers (customer_id INT PRIMARY KEY, customer_name VARCHAR(100), gender VARCHAR(10), city VARCHAR(50), state VARCHAR(50), region VARCHAR(20), signup_date DATE, email VARCHAR(100));
CREATE TABLE sellers (seller_id INT PRIMARY KEY, seller_name VARCHAR(50), city VARCHAR(50), state VARCHAR(50), joined_date DATE);
CREATE TABLE categories (category_id INT PRIMARY KEY, category_name VARCHAR(50), parent_group VARCHAR(30));
CREATE TABLE products (product_id INT PRIMARY KEY, product_name VARCHAR(100), category_id INT REFERENCES categories, seller_id INT REFERENCES sellers, price NUMERIC(10,2), cost_price NUMERIC(10,2));
CREATE TABLE orders (order_id INT PRIMARY KEY, customer_id INT REFERENCES customers, order_date TIMESTAMP, order_status VARCHAR(20), shipped_date DATE, delivered_date DATE, promised_date DATE);
CREATE TABLE order_items (order_item_id INT PRIMARY KEY, order_id INT REFERENCES orders, product_id INT REFERENCES products, quantity INT, discount_pct INT, unit_price NUMERIC(10,2), item_total NUMERIC(12,2), shipping_fee NUMERIC(8,2));
CREATE TABLE payments (payment_id INT PRIMARY KEY, order_id INT REFERENCES orders, payment_method VARCHAR(30), payment_amount NUMERIC(12,2), payment_status VARCHAR(20), payment_date DATE);
CREATE TABLE reviews (review_id INT PRIMARY KEY, order_id INT REFERENCES orders, customer_id INT REFERENCES customers, rating INT, review_date DATE, review_comment VARCHAR(100));


/* =====================================================================
   2. ROW COUNT AND NULL CHECKS (RAW TABLES)
   ===================================================================== */

-- 2.1 Row count: did the import work?
SELECT 'customers' AS tbl, COUNT(*) AS total_rows FROM customers UNION ALL
SELECT 'sellers',     COUNT(*) FROM sellers      UNION ALL
SELECT 'categories',  COUNT(*) FROM categories   UNION ALL
SELECT 'products',    COUNT(*) FROM products     UNION ALL
SELECT 'orders',      COUNT(*) FROM orders       UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items  UNION ALL
SELECT 'payments',    COUNT(*) FROM payments     UNION ALL
SELECT 'reviews',     COUNT(*) FROM reviews;
-- Finding: 50000 / 500 / 12 / 5000 / 120000 / 192445 / 120000 / 72304, matches the source files.

-- 2.2 Null check: customer email
SELECT COUNT(*) FILTER (WHERE email IS NULL) AS null_email
FROM customers;
-- Finding: 800 of 50000 customers have no email.
-- Action: filled with 'not_provided' in customers_clean (section 4.5).

-- 2.3 Null check: delivered_date by order status
SELECT order_status,
       COUNT(*) FILTER (WHERE delivered_date IS NULL) AS null_delivered
FROM orders
GROUP BY order_status;
-- Finding: NULLs only in Cancelled (8295) and Shipped (3668) orders. Delivered and Returned have 0.
-- Action: these NULLs are valid (not delivered yet / never shipped), so they are kept.


/* =====================================================================
   3. JOIN ALL TABLES
   orders is the central table, the other tables connect through keys.
   ===================================================================== */

-- 3.1 Small join example: orders + customers + order_items
SELECT o.order_id, c.customer_name, oi.item_total
FROM orders o
JOIN customers c    ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id    = oi.order_id
LIMIT 10;
-- Note: one order can have several items, so an order_id can repeat.

-- 3.2 Full join: 8 tables into ecommerce_full (one row per order item)
DROP TABLE IF EXISTS ecommerce_full;
CREATE TABLE ecommerce_full AS
SELECT o.order_id, o.order_date, o.order_status,
       o.shipped_date, o.delivered_date, o.promised_date,
       c.customer_id, c.customer_name, c.gender, c.city, c.state, c.region,
       p.product_id, p.product_name, cat.category_name,
       s.seller_id, s.seller_name,
       oi.order_item_id, oi.quantity, oi.unit_price,
       oi.discount_pct, oi.item_total, oi.shipping_fee,
       (oi.item_total - oi.quantity * p.cost_price) AS profit,
       pay.payment_method, pay.payment_status,
       r.rating
FROM orders o
JOIN customers c    ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id    = oi.order_id
JOIN products p     ON oi.product_id = p.product_id
JOIN categories cat ON p.category_id = cat.category_id
JOIN sellers s      ON p.seller_id   = s.seller_id
JOIN payments pay   ON o.order_id    = pay.order_id
LEFT JOIN reviews r ON o.order_id    = r.order_id;
-- Note: LEFT JOIN on reviews because not every order has a review.
-- Result: 192445 rows (same as order_items, so no rows were lost or duplicated).


/* =====================================================================
   4. DATA CLEANING CHECKS ON THE JOINED TABLE
   ===================================================================== */

-- 4.1 Duplicate check (expect 0 rows)
SELECT order_item_id, COUNT(*)
FROM ecommerce_full
GROUP BY order_item_id
HAVING COUNT(*) > 1;
-- Finding: 0 duplicates.

-- 4.2 Invalid values (expect all 0)
SELECT COUNT(*) FILTER (WHERE quantity <= 0)  AS bad_qty,
       COUNT(*) FILTER (WHERE item_total < 0) AS bad_total,
       COUNT(*) FILTER (WHERE delivered_date < order_date::date) AS bad_dates,
       COUNT(*) FILTER (WHERE rating NOT BETWEEN 1 AND 5) AS bad_rating
FROM ecommerce_full;
-- Finding: all four are 0, no invalid values.

-- 4.3 Order status breakdown
SELECT order_status, COUNT(*) AS rows
FROM ecommerce_full
GROUP BY order_status
ORDER BY rows DESC;
-- Finding: Delivered 165779, Cancelled 13156, Returned 7572, Shipped 5938.
-- Action: real sales come only from Delivered orders, so the analysis uses those.

-- 4.4 Final analysis table: Delivered orders only
DROP TABLE IF EXISTS sales_clean;
CREATE TABLE sales_clean AS
SELECT *, DATE_TRUNC('month', order_date)::date AS order_month
FROM ecommerce_full
WHERE order_status = 'Delivered';
-- Result: 165779 rows. 26666 non-delivered rows were left out.

-- 4.5 Fix: fill missing emails
DROP TABLE IF EXISTS customers_clean;
CREATE TABLE customers_clean AS
SELECT customer_id,
       INITCAP(TRIM(customer_name)) AS customer_name,
       gender, city, state, region, signup_date,
       LOWER(TRIM(COALESCE(email, 'not_provided'))) AS email
FROM customers;
-- Result: 50000 rows, 800 emails set to 'not_provided'.


/* =====================================================================
   5. BUSINESS ANALYSIS (all queries run on sales_clean)
   Write one or two lines of insight under each query after running it.
   ===================================================================== */

-- 5.1 KPI summary
SELECT ROUND(SUM(item_total))                          AS total_revenue,
       ROUND(SUM(profit))                              AS total_profit,
       ROUND(100.0 * SUM(profit) / SUM(item_total), 1) AS margin_pct,
       COUNT(DISTINCT order_id)                        AS orders,
       COUNT(DISTINCT customer_id)                     AS customers,
       ROUND(SUM(item_total) / COUNT(DISTINCT order_id)) AS avg_order_value
FROM sales_clean;
-- Insight:

-- 5.2 Monthly revenue and profit
SELECT order_month,
       ROUND(SUM(item_total)) AS revenue,
       ROUND(SUM(profit))     AS profit,
       COUNT(DISTINCT order_id) AS orders
FROM sales_clean
GROUP BY order_month
ORDER BY order_month;
-- Insight:

-- 5.3 Month-over-month revenue growth (%)
WITH monthly AS (
  SELECT order_month, SUM(item_total) AS revenue
  FROM sales_clean
  GROUP BY order_month
)
SELECT order_month, ROUND(revenue) AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
             / LAG(revenue) OVER (ORDER BY order_month), 1) AS mom_growth_pct
FROM monthly
ORDER BY order_month;
-- Insight:

-- 5.4 Category-wise revenue, profit and margin
SELECT category_name,
       ROUND(SUM(item_total)) AS revenue,
       ROUND(SUM(profit))     AS profit,
       ROUND(100.0 * SUM(profit) / SUM(item_total), 1) AS margin_pct
FROM sales_clean
GROUP BY category_name
ORDER BY revenue DESC;
-- Insight:

-- 5.5 Region-wise sales
SELECT region,
       ROUND(SUM(item_total)) AS revenue,
       COUNT(DISTINCT customer_id) AS customers
FROM sales_clean
GROUP BY region
ORDER BY revenue DESC;
-- Insight:

-- 5.6 Top 10 customers by spend
SELECT customer_id, customer_name, city,
       COUNT(DISTINCT order_id) AS orders,
       ROUND(SUM(item_total))   AS total_spent
FROM sales_clean
GROUP BY customer_id, customer_name, city
ORDER BY total_spent DESC
LIMIT 10;
-- Insight:

-- 5.7 New vs repeat customers
WITH cust_orders AS (
  SELECT customer_id, COUNT(DISTINCT order_id) AS orders
  FROM sales_clean
  GROUP BY customer_id
)
SELECT CASE WHEN orders = 1 THEN 'New (1 order)' ELSE 'Repeat (2+ orders)' END AS customer_type,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM cust_orders
GROUP BY 1;
-- Insight:

-- 5.8 Payment method share
SELECT payment_method,
       COUNT(DISTINCT order_id) AS orders,
       ROUND(100.0 * COUNT(DISTINCT order_id) / SUM(COUNT(DISTINCT order_id)) OVER (), 1) AS pct
FROM sales_clean
GROUP BY payment_method
ORDER BY orders DESC;
-- Insight:

-- 5.9 Effect of discount on profit margin
SELECT discount_pct,
       ROUND(SUM(item_total)) AS revenue,
       ROUND(100.0 * SUM(profit) / SUM(item_total), 1) AS margin_pct
FROM sales_clean
GROUP BY discount_pct
ORDER BY discount_pct;
-- Insight:

-- 5.10 Delivery performance: average days and late %
SELECT ROUND(AVG(delivered_date - order_date::date), 1) AS avg_delivery_days,
       ROUND(100.0 * COUNT(*) FILTER (WHERE delivered_date > promised_date) / COUNT(*), 1) AS late_pct
FROM orders
WHERE order_status = 'Delivered';
-- Insight:

-- 5.11 Effect of late delivery on rating
SELECT CASE WHEN o.delivered_date > o.promised_date THEN 'Late' ELSE 'On time' END AS delivery,
       COUNT(*) AS reviews,
       ROUND(AVG(r.rating), 2) AS avg_rating
FROM orders o
JOIN reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'Delivered'
GROUP BY 1;
-- Insight:

-- 5.12 Order status share (cancellation and return rate)
SELECT order_status, COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM orders
GROUP BY order_status
ORDER BY orders DESC;
-- Insight:
-- Insight: 86.1% of orders were delivered. Cancellations (6.9%) and returns (4.0%)
-- together make up about 10.9% of orders, so roughly 1 in 9 orders does not end in a sale.
-- Another 3.1% were still in transit (Shipped).
