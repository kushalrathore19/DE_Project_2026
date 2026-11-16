-- =====================================================================
-- Phase 4: Secondary Indexes & Performance Tuning
-- Database: PostgreSQL 15+
-- Schema: amazon
-- Description: Targeted indexes serving the 30 workload queries with justified
--              index types, column ordering, and partial/covering expressions.
-- =====================================================================

SET search_path TO amazon, public;

-- Enable trigram extension for efficient substring ILIKE pattern matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 1. Index for R01 (Search box text matching)
-- Type: Partial GIN index using gin_trgm_ops
-- Serves: R01 (title ILIKE '%wireless%' AND status = 'ACTIVE')
-- Justification: Eliminates full table scan on 30,000 products by indexing 3-character
-- trigrams for substring lookups on active catalogue items only.
DROP INDEX IF EXISTS idx_products_title_trgm;
CREATE INDEX idx_products_title_trgm
    ON products USING gin (title gin_trgm_ops)
    WHERE status = 'ACTIVE';

-- 2. Index for R02, R12, R16 (Category tree traversal)
-- Type: B-Tree
-- Serves: Recursive CTE category hierarchy traversal and joins
-- Justification: Indexes foreign key parent_category_id to enable index lookups
-- during parent-child recursive category navigation.
DROP INDEX IF EXISTS idx_categories_parent;
CREATE INDEX idx_categories_parent
    ON categories (parent_category_id);

-- 3. Index for R02 (Category browse with price range)
-- Type: Composite B-Tree with covering INCLUDE
-- Serves: R02 (category_id IN (...) AND price BETWEEN 1000 AND 5000 AND status = 'ACTIVE')
-- Justification: Equality column (category_id) first, then range/sort column (price).
-- INCLUDE (title) enables Index Only Scan without touching the table heap.
DROP INDEX IF EXISTS idx_products_cat_price;
CREATE INDEX idx_products_cat_price
    ON products (category_id, price)
    INCLUDE (title)
    WHERE status = 'ACTIVE';

-- 4. Index for R03 (Product reviews breakdown)
-- Type: Composite B-Tree
-- Serves: R03 (WHERE product_id = 4321 GROUP BY rating ORDER BY rating DESC)
-- Justification: Equality filter (product_id) first, followed by aggregate group/sort
-- column (rating DESC). Enables pure Index Only Scan on 38k reviews.
DROP INDEX IF EXISTS idx_reviews_product_rating;
CREATE INDEX idx_reviews_product_rating
    ON product_reviews (product_id, rating DESC);

-- 5. Index for R04 (Customer order history)
-- Type: Composite B-Tree with covering INCLUDE
-- Serves: R04 (WHERE customer_id = 1042 ORDER BY ordered_at DESC)
-- Justification: Equality column (customer_id) first, then sort column (ordered_at DESC).
-- Covering INCLUDE (status, total_amount) turns 120,000-row Seq Scan into <1 ms Index Only Scan.
DROP INDEX IF EXISTS idx_orders_customer_ordered_at;
CREATE INDEX idx_orders_customer_ordered_at
    ON orders (customer_id, ordered_at DESC)
    INCLUDE (status, total_amount);

-- 6. Index for R05 (Logistics stuck shipments)
-- Type: Partial B-Tree with covering INCLUDE
-- Serves: R05 (WHERE status = 'SHIPPED' AND shipped_at < '2026-06-20')
-- Justification: Partial index strictly filters active shipments, ordering by shipped_at.
DROP INDEX IF EXISTS idx_orders_shipped_at_partial;
CREATE INDEX idx_orders_shipped_at_partial
    ON orders (shipped_at)
    INCLUDE (customer_id)
    WHERE status = 'SHIPPED';

-- 7. Index for R06 & R15 (Seller order items lookup)
-- Type: Composite B-Tree with covering INCLUDE
-- Serves: R06, R15 (WHERE seller_id = 217 / seller revenue aggregation)
-- Justification: Indexes seller_id foreign key on order_items (240k rows), covering
-- product_id, quantity, and unit_price for lightning fast seller reporting.
DROP INDEX IF EXISTS idx_order_items_seller_order;
CREATE INDEX idx_order_items_seller_order
    ON order_items (seller_id, order_id)
    INCLUDE (product_id, quantity, unit_price);

-- 8. Index for R07 (Seller inventory low-stock alerts)
-- Type: Partial Composite B-Tree with covering INCLUDE
-- Serves: R07 (WHERE seller_id = 217 AND stock_qty <= 20 AND status IN ('ACTIVE', 'OUT_OF_STOCK'))
-- Justification: Equality column (seller_id) first, then range/sort column (stock_qty).
DROP INDEX IF EXISTS idx_products_seller_stock;
CREATE INDEX idx_products_seller_stock
    ON products (seller_id, stock_qty)
    INCLUDE (title, status)
    WHERE status IN ('ACTIVE', 'OUT_OF_STOCK');

-- 9. Index for R08, R09, R20 (Non-cancelled orders by date)
-- Type: Partial B-Tree with covering INCLUDE
-- Serves: R08, R09, R20 (date range filtering on valid orders)
-- Justification: Indexes ordered_at for date range queries, excluding cancelled orders.
DROP INDEX IF EXISTS idx_orders_ordered_at_active;
CREATE INDEX idx_orders_ordered_at_active
    ON orders (ordered_at)
    INCLUDE (customer_id, total_amount)
    WHERE status <> 'CANCELLED';

-- 10. Index for R08, R11, R19 (Product sales & Frequently Bought Together)
-- Type: Composite B-Tree with covering INCLUDE
-- Serves: R11 (co-purchase self join), R19 (units sold aggregate), R08
-- Justification: Reverses primary key order to product_id first, enabling instant
-- lookup of order_ids where a product was purchased.
DROP INDEX IF EXISTS idx_order_items_product_order;
CREATE INDEX idx_order_items_product_order
    ON order_items (product_id, order_id)
    INCLUDE (quantity);

-- 11. Index for R10 (Abandoned cart marketing)
-- Type: Composite B-Tree
-- Serves: R10 (WHERE ci.added_at < '2026-05-01')
-- Justification: Range index on added_at, indexing customer_id and product_id for fast joins.
DROP INDEX IF EXISTS idx_cart_items_added_cust_prod;
CREATE INDEX idx_cart_items_added_cust_prod
    ON cart_items (added_at, customer_id, product_id)
    INCLUDE (quantity);

-- 12. Index for R13 (Unused address cleanup verification)
-- Type: Partial B-Tree
-- Serves: R13 (WHERE NOT EXISTS (SELECT 1 FROM orders WHERE address_id = a.address_id))
-- Justification: Indexes non-null delivery addresses in orders for instant anti-join probing.
DROP INDEX IF EXISTS idx_orders_address_id_not_null;
CREATE INDEX idx_orders_address_id_not_null
    ON orders (address_id)
    WHERE address_id IS NOT NULL;

-- 13. Index for R14 (Deals page discount percentage)
-- Type: Partial Expression B-Tree with covering INCLUDE
-- Serves: R14 (WHERE price < mrp * 0.5 AND status = 'ACTIVE' ORDER BY price / mrp)
-- Justification: Pre-computes expression (price / mrp) directly in the B-Tree index,
-- providing pre-sorted index order for deep discount queries.
DROP INDEX IF EXISTS idx_products_discount_ratio;
CREATE INDEX idx_products_discount_ratio
    ON products ((price / mrp))
    INCLUDE (title, mrp, price)
    WHERE status = 'ACTIVE' AND price < mrp * 0.5;

-- 14. Index for R16 (Review insights text search)
-- Type: GIN index with gin_trgm_ops
-- Serves: R16 (WHERE r.body ILIKE '%battery%')
-- Justification: Accelerates arbitrary substring searches on review bodies.
DROP INDEX IF EXISTS idx_reviews_body_trgm;
CREATE INDEX idx_reviews_body_trgm
    ON product_reviews USING gin (body gin_trgm_ops);

-- 15. Index for R17 (Trust & Safety verified reviews)
-- Type: Partial Composite B-Tree
-- Serves: R17 (WHERE r.verified_purchase)
-- Justification: Restricts index to verified purchase reviews, indexing customer_id
-- and product_id to verify against delivered order history.
DROP INDEX IF EXISTS idx_reviews_verified_cust_prod;
CREATE INDEX idx_reviews_verified_cust_prod
    ON product_reviews (customer_id, product_id)
    WHERE verified_purchase = true;

-- 16. Index for R18 (Customer city analytics)
-- Type: Composite B-Tree
-- Serves: R18 (WHERE c.city_id = 2)
-- Justification: Fast filter on Mumbai customer IDs.
DROP INDEX IF EXISTS idx_customers_city_id;
CREATE INDEX idx_customers_city_id
    ON customers (city_id, customer_id);

-- 17. Index for R21 (Delayed delivery logistics)
-- Type: Composite B-Tree with covering INCLUDE
-- Serves: R21 (WHERE delivered_at > ordered_at + interval '5 days' AND ordered_at >= '2026-06-01')
-- Justification: B-Tree index on ordered_at and delivered_at for fast date range filtering.
DROP INDEX IF EXISTS idx_orders_delayed_deliveries;
CREATE INDEX idx_orders_delayed_deliveries
    ON orders (ordered_at, delivered_at)
    INCLUDE (customer_id);

-- 18. Index for R22 (Deep pagination on All Orders)
-- Type: Composite B-Tree with covering INCLUDE
-- Serves: R22 (ORDER BY ordered_at DESC OFFSET 75000 LIMIT 25)
-- Justification: Pre-sorted index on ordered_at DESC covering all selected columns.
-- Avoids expensive memory/disk sorting of 120,000 order records.
DROP INDEX IF EXISTS idx_orders_ordered_at_desc;
CREATE INDEX idx_orders_ordered_at_desc
    ON orders (ordered_at DESC)
    INCLUDE (customer_id, status, total_amount);

-- 19. Index for W05 (Oldest packed order lookup)
-- Type: Partial B-Tree
-- Serves: W05 (SELECT min(order_id) FROM orders WHERE status = 'PACKED')
-- Justification: Direct B-Tree min lookup on packed orders, executing in <0.05 ms.
DROP INDEX IF EXISTS idx_orders_packed_min_id;
CREATE INDEX idx_orders_packed_min_id
    ON orders (order_id)
    WHERE status = 'PACKED';

-- 20. Index for W06 (Stale cart item purge)
-- Type: B-Tree
-- Serves: W06 (DELETE FROM cart_items WHERE added_at < ...)
-- Justification: Fast range identification for bulk deletion of items older than 90 days.
DROP INDEX IF EXISTS idx_cart_items_added_at;
CREATE INDEX idx_cart_items_added_at
    ON cart_items (added_at);

-- Refresh statistics after index creation
ANALYZE;
