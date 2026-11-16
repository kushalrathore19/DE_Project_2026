# Phase 3: Baseline Query Performance & Plan Analysis

**Course:** Database Management Systems · **Project:** Amazon Online Shopping Database  
**Author / Team:** Kushal Rathore (`kushalrathore19`), Adarsh Chauhan (`mriarc-08`), Lakshya (`lakshyapvt2010-ux`), Oojass Kwatra (`oojasskwatra-gif`)  
**Database:** PostgreSQL 18.3 · **Hardware:** Apple MacBook  
**Methodology:** 3 iterations per query via `EXPLAIN (ANALYZE, BUFFERS)` using `./benchmarks/run_benchmark.sh amazon_db baseline`. Writes executed within `BEGIN ... ROLLBACK`. Raw plans preserved in `benchmarks/results/baseline/`.  

---

## 1. Baseline Performance Measurements (Workload 30)

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| **R01:** Search box: active products whose title contains "wireless", best rated first | READ | 16.280 | 15.990 | 15.602 | 15.957 |
| **R02:** Category browse: everything under "Electronics" (all sub-levels) priced ₹1,000–₹5,000 | READ | 7.486 | 6.997 | 7.214 | 7.232 |
| **R03:** Product page: rating breakdown (how many 5★, 4★ …) for product 4321 | READ | 3.549 | 3.425 | 4.026 | 3.667 |
| **R04:** "Your Orders": customer 1042's orders with the number of items in each | READ | 10.608 | 11.249 | 9.617 | 10.491 |
| **R05:** Logistics: shipments in transit for more than 10 days (checked on 30 Jun 2026) | READ | 15.178 | 13.183 | 13.001 | 13.787 |
| **R06:** Seller Central: seller 217's order lines in June 2026 | READ | 12.685 | 10.955 | 9.318 | 10.986 |
| **R07:** Seller Central: seller 217's products that are low on stock | READ | 4.321 | 4.760 | 4.976 | 4.686 |
| **R08:** Merchandising: top 5 best-selling products in every sub-category, last 30 days | READ | 51.958 | 49.371 | 50.560 | 50.630 |
| **R09:** Prime team: average order value of Prime vs non-Prime customers per month in 2026 | READ | 50.376 | 51.157 | 51.202 | 50.912 |
| **R10:** Marketing: carts untouched since May 2026 whose owner has not ordered since then | READ | 34.541 | 35.067 | 33.851 | 34.486 |
| **R11:** Product page: "Frequently bought together" with product 4321 | READ | 8.965 | 8.867 | 9.642 | 9.158 |
| **R12:** Category managers: return rate per top-level category | READ | 132.203 | 122.463 | 117.711 | 124.126 |
| **R13:** Data clean-up: saved addresses that have never been used for any order | READ | 32.556 | 37.884 | 48.683 | 39.708 |
| **R14:** Deals page: active products selling at less than half of MRP, biggest discount first | READ | 8.107 | 8.810 | 8.677 | 8.531 |
| **R15:** Seller performance: top 20 sellers by revenue among sellers with at least 50 lines sold in 2026 | READ | 50.677 | 64.559 | 44.794 | 53.343 |
| **R16:** Review insights: Electronics reviews that mention the battery | READ | 17.764 | 17.224 | 17.655 | 17.548 |
| **R17:** Trust & safety: "verified purchase" reviews with no delivered order of that product by that customer | READ | 122.216 | 142.833 | 135.063 | 133.371 |
| **R18:** Customer analytics: Mumbai customers split into 4 spending tiers (2026) | READ | 21.840 | 20.479 | 19.863 | 20.727 |
| **R19:** Category report: every Mobile phone with its last sale date and units sold (all time) | READ | 18478.032 | 18184.117 | 18587.772 | 18416.640 |
| **R20:** Finance: daily sales (GMV) and running total for June 2026 | READ | 12.721 | 13.049 | 12.153 | 12.641 |
| **R21:** Logistics: deliveries in June 2026 that took more than 5 days | READ | 9.786 | 10.156 | 10.139 | 10.027 |
| **R22:** Admin: "All orders", newest first, page 3,001 (25 rows per page) | READ | 51.203 | 51.036 | 50.482 | 50.907 |
| **R23:** Order details page: one order with its lines, products and sellers | READ | 0.161 | 0.126 | 0.127 | 0.138 |
| **R24:** Product lookup by ASIN (barcode scanner in the warehouse) | READ | 0.068 | 0.057 | 0.062 | 0.062 |
| **W01:** Checkout: create a new order (header row) | WRITE | 1.832 | 2.065 | 2.118 | 2.005 |
| **W02:** Checkout: reduce stock of product 4322 after a sale | WRITE | 1.019 | 1.073 | 0.850 | 0.981 |
| **W03:** Seller Central: 10% price cut on all of seller 217's Watches | WRITE | 2.990 | 3.759 | 4.960 | 3.903 |
| **W04:** Big sale: 5,000 "add to cart" events loaded in one batch | WRITE | 71.057 | 64.915 | 63.664 | 66.545 |
| **W05:** Logistics: mark the oldest packed order as shipped | WRITE | 14.854 | 15.372 | 15.506 | 15.244 |
| **W06:** Nightly clean-up: remove cart items older than 90 days | WRITE | 10.101 | 11.009 | 10.980 | 10.697 |
| **Total (sum of all 30)** | — | — | — | — | **19,199.136 ms** |

---

## 2. Scan Type Analysis & Root-Cause Diagnosis

| Query | Dominant Scan Nodes in Plan | Execution Root Cause / Performance Analysis |
|---|---|---|
| **R01** | `Seq Scan on products` | **Slow (15.96 ms):** Scans all 30,000 product rows evaluating substring `ILIKE '%wireless%'` without a trigram GIN index, followed by memory sort. |
| **R02** | `Seq Scan on categories`, `Seq Scan on products` | **Moderate (7.23 ms):** Recursive CTE resolves categories quickly, but filters 30,000 product rows sequentially on `category_id` and price range. |
| **R03** | `Seq Scan on product_reviews` | **Moderate (3.67 ms):** Performs a full sequential scan across 38,662 review rows because there is no foreign key index on `product_reviews(product_id)`. |
| **R04** | `Seq Scan on orders`, `Index Only Scan on order_items` | **Slow (10.49 ms):** Scans all 120,000 orders sequentially looking for 4 rows where `customer_id = 1042`. Order items lookup is fast via primary key. |
| **R05** | `Seq Scan on orders` | **Slow (13.79 ms):** Filters all 120,000 orders sequentially on `status = 'SHIPPED'` and `shipped_at < '2026-06-20'` without a composite index. |
| **R06** | `Seq Scan on order_items`, `Index Scan on orders` | **Slow (10.99 ms):** Full sequential scan on 240,000 order item rows to find seller 217 lines because `order_items(seller_id)` lacks an index. |
| **R07** | `Seq Scan on products` | **Fast (4.69 ms):** Seq scan over 30,000 rows filtering on `seller_id = 217`; lacks index on `products(seller_id, stock_qty)`. |
| **R08** | `Seq Scan on order_items`, `Seq Scan on orders`, `Seq Scan on products` | **Heavy (50.63 ms):** Multi-table join scanning 240,000 order lines and 120,000 orders with window rank partitioning without date filtering indexes. |
| **R09** | `Seq Scan on orders`, `Seq Scan on customers` | **Heavy (50.91 ms):** Joins 120,000 orders with 30,000 customers via hash join; evaluates `EXTRACT(YEAR FROM ordered_at)` non-sargably on every row. |
| **R10** | `Seq Scan on orders`, `Seq Scan on cart_items`, `Seq Scan on products` | **Heavy (34.49 ms):** Anti-join checks `NOT EXISTS` across 120,000 orders for each cart customer; lacks customer order date index. |
| **R11** | `Seq Scan on order_items`, `Index Scan on order_items` | **Moderate (9.16 ms):** Self-join on `order_items` finds product 4321 via sequential scan, then joins matching order lines via primary key index. |
| **R12** | `Seq Scan on order_items`, `Seq Scan on products`, `Seq Scan on categories`, `Seq Scan on returns` | **Heavy (124.13 ms):** Large 4-table join and aggregation over 240k order lines and 5.3k returns; missing composite join indexes. |
| **R13** | `Seq Scan on addresses`, `Seq Scan on orders` | **Flawed (39.71 ms):** Full sequential scan on 45,000 addresses and 120,000 orders. Returns **0 rows incorrectly** due to `NOT IN (SELECT address_id)` with `NULL`s. |
| **R14** | `Seq Scan on products` | **Moderate (8.53 ms):** Scans all 30,000 products computing arithmetic expression `price < mrp * 0.5` on the fly without an expression index. |
| **R15** | `Seq Scan on order_items`, `Seq Scan on orders`, `Seq Scan on sellers` | **Heavy (53.34 ms):** Full table scans on orders and items filtering on date range `>= '2026-01-01'` and grouping by seller revenue. |
| **R16** | `Seq Scan on product_reviews`, `Seq Scan on products`, `Seq Scan on categories` | **Moderate (17.55 ms):** Scans 38k reviews evaluating case-insensitive substring `ILIKE '%battery%'` without full-text or trigram indexing. |
| **R17** | `Seq Scan on order_items`, `Seq Scan on orders`, `Seq Scan on product_reviews` | **Heavy (133.37 ms):** Correlated anti-join subquery scanning 120,000 orders and 240,000 order items for verified customer reviews. |
| **R18** | `Seq Scan on orders`, `Seq Scan on customers` | **Moderate (20.73 ms):** Hash join on 30k customers (filtering `city_id = 2`) and 120k orders, followed by window function `NTILE(4)`. |
| **R19** | `Seq Scan on categories`, `Seq Scan on products`, `Seq Scan on order_items`, `Index Scan on orders` | **Critical Bottleneck (18,416.64 ms / 18.4 s):** Two independent correlated subqueries (`MAX(ordered_at)` and `SUM(quantity)`) execute for every mobile phone listing, repeatedly sequential-scanning 240,000 `order_items` rows. |
| **R20** | `Seq Scan on orders` | **Moderate (12.64 ms):** Scans 120,000 orders filtering on `ordered_at::date` range and grouping by day with a window running sum. |
| **R21** | `Seq Scan on orders` | **Moderate (10.03 ms):** Scans 120,000 orders checking interval calculation `delivered_at > ordered_at + interval '5 days'`. |
| **R22** | `Seq Scan on orders` | **Heavy (50.91 ms):** Full table scan on 120,000 orders, sorting all rows in memory by `ordered_at DESC`, then discarding 75,000 offset rows for 25 items. |
| **R23** | `Index Scan on orders`, `order_items`, `products`, `sellers` | **Blazing Fast (0.14 ms):** Pure index-nested loops utilizing primary key B-trees on all joined tables. |
| **R24** | `Index Scan using products_asin_key on products` | **Sub-millisecond (0.06 ms):** Instant single-row lookup leveraging the unique B-tree index created for `asin`. |
| **W01** | `(no scan)` | **Fast (2.01 ms):** Single row `INSERT` into `orders` with foreign key and constraint validation overhead. |
| **W02** | `Index Scan using products_pkey on products` | **Fast (0.98 ms):** Single-row in-place stock decrement using primary key index lookup on `product_id`. |
| **W03** | `Seq Scan on categories`, `Seq Scan on products` | **Moderate (3.90 ms):** Joins `categories` and `products` via sequential scans to update seller 217's watch prices. |
| **W04** | `(no scan)` | **Heavy Batch (66.55 ms):** Bulk insertion of 5,000 generated cart item records with conflict resolution (`ON CONFLICT DO NOTHING`). |
| **W05** | `Index Scan using orders_pkey on orders` | **Moderate (15.24 ms):** Subquery `SELECT min(order_id) FROM orders WHERE status = 'PACKED'` requires scanning orders, followed by PK update. |
| **W06** | `Seq Scan on cart_items` | **Moderate (10.70 ms):** Scans all 44,998 cart records to delete items older than 90 days. |

---

## 3. Key Bottlenecks Identified for Phase 4 Optimization

1. **The R19 Correlated Subquery Disaster (18.4 seconds):**
   * Correlated subqueries inside the `SELECT` projection force $2 \times N$ sequential scans over 240,000 rows in `order_items`. Converting to a single `LEFT JOIN` with `GROUP BY` and indexing `order_items(product_id, quantity)` will reduce this from 18,400 ms to <10 ms (>1,800× speedup).
2. **Missing Secondary Indexes on Foreign Keys:**
   * PostgreSQL automatically creates indexes for `PRIMARY KEY` and `UNIQUE` constraints, but **never for foreign keys**. Queries joining `orders.customer_id` (`R04`), `order_items.seller_id` (`R06`), `product_reviews.product_id` (`R03`), and `cart_items(customer_id)` (`R10`) degrade to full table scans.
3. **The R13 SQL NULL Bug:**
   * `NOT IN (SELECT address_id FROM orders)` evaluates to `UNKNOWN` because 5,882 orders have `address_id IS NULL`. Rewriting to `NOT EXISTS (SELECT 1 FROM orders o WHERE o.address_id = a.address_id)` or adding `WHERE address_id IS NOT NULL` will fix correctness and accelerate performance.
4. **Deep Pagination Overhead (R22):**
   * `OFFSET 75000 LIMIT 25` forces sorting and scanning 75,025 rows. Keyset pagination (`WHERE ordered_at < $last_seen_date ORDER BY ordered_at DESC LIMIT 25`) with a B-tree index on `orders(ordered_at DESC)` will enable instant execution.
5. **Full Text & Pattern Matching (R01, R16):**
   * `ILIKE '%wireless%'` and `ILIKE '%battery%'` inspect every byte across 30k products and 38k reviews. Adding the `pg_trgm` extension and GIN trigram indexes will enable index scans on arbitrary substring searches.

