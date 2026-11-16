-- =====================================================================
-- Phase 2: Data Loading & Integrity Checks
-- Description: Loads seed data CSV files in dependency order using \copy
-- =====================================================================

SET search_path TO amazon;

-- 1. Cities
\copy cities FROM 'seed_data/cities.csv' WITH (FORMAT csv, HEADER true)

-- 2. Categories
\copy categories FROM 'seed_data/categories.csv' WITH (FORMAT csv, HEADER true)

-- 3. Sellers
\copy sellers FROM 'seed_data/sellers.csv' WITH (FORMAT csv, HEADER true)

-- 4. Customers
\copy customers FROM 'seed_data/customers.csv' WITH (FORMAT csv, HEADER true)

-- 5. Addresses
\copy addresses FROM 'seed_data/addresses.csv' WITH (FORMAT csv, HEADER true)

-- 6. Products
\copy products FROM 'seed_data/products.csv' WITH (FORMAT csv, HEADER true)

-- 7. Orders
\copy orders FROM 'seed_data/orders.csv' WITH (FORMAT csv, HEADER true)

-- 8. Order Items
\copy order_items FROM 'seed_data/order_items.csv' WITH (FORMAT csv, HEADER true)

-- 9. Returns
\copy returns FROM 'seed_data/returns.csv' WITH (FORMAT csv, HEADER true)

-- 10. Product Reviews
\copy product_reviews FROM 'seed_data/product_reviews.csv' WITH (FORMAT csv, HEADER true)

-- 11. Cart Items
\copy cart_items FROM 'seed_data/cart_items.csv' WITH (FORMAT csv, HEADER true)

-- Update planner statistics
ANALYZE;

-- =====================================================================
-- Integrity Verification Queries
-- =====================================================================

-- Check 1: Row count verification across all tables
SELECT 'cities' AS table_name, count(*) AS actual_rows, 10 AS expected_rows FROM cities
UNION ALL SELECT 'categories', count(*), 40 FROM categories
UNION ALL SELECT 'sellers', count(*), 1500 FROM sellers
UNION ALL SELECT 'customers', count(*), 30000 FROM customers
UNION ALL SELECT 'addresses', count(*), 45000 FROM addresses
UNION ALL SELECT 'products', count(*), 30000 FROM products
UNION ALL SELECT 'orders', count(*), 120000 FROM orders
UNION ALL SELECT 'order_items', count(*), 240000 FROM order_items
UNION ALL SELECT 'returns', count(*), 5374 FROM returns
UNION ALL SELECT 'product_reviews', count(*), 38662 FROM product_reviews
UNION ALL SELECT 'cart_items', count(*), 44998 FROM cart_items;

-- Check 2: Verify order_items.seller_id always matches products.seller_id
SELECT count(*) AS mismatched_sellers
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
WHERE oi.seller_id <> p.seller_id;

-- Check 3: Verify orders without address_id contain only digital products
SELECT count(*) AS non_digital_orders_without_address
FROM orders o
JOIN order_items oi ON oi.order_id = o.order_id
JOIN products p ON p.product_id = oi.product_id
JOIN categories c ON c.category_id = p.category_id
WHERE o.address_id IS NULL AND c.is_digital = false;

-- Check 4: Verify calculated order item totals match orders.total_amount
SELECT count(*) AS total_amount_mismatches
FROM (
    SELECT o.order_id, o.total_amount, sum(oi.quantity * oi.unit_price) AS calc_total
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    GROUP BY o.order_id, o.total_amount
) t
WHERE abs(t.total_amount - t.calc_total) > 0.01;

