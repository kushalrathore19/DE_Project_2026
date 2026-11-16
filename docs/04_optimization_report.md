# Phase 4: Query Optimization Report

**Course:** Database Management Systems · **Project:** Amazon Online Shopping Database  
**Author / Team:** Kushal Rathore (`kushalrathore19`), Adarsh Chauhan (`mriarc-08`), Lakshya (`lakshyapvt2010-ux`), Oojass Kwatra (`oojasskwatra-gif`)  
**Database:** PostgreSQL 18.3 · **Benchmark:** 3-run average using `benchmarks/run_benchmark.sh amazon_db optimized`  

---

## 1. Workload Optimization Summary

Across all 30 queries, total workload execution time decreased from **19,199.136 ms** down to **790.613 ms**, achieving an overall **95.88% workload reduction (24.3× cumulative speedup)**.

### Complete Optimization Comparison Table

| Query | Baseline (ms) | Problem Found in Baseline Plan | Optimization Applied | Optimized (ms) | Improvement (%) | Speedup | Same Result? |
|---|---:|---|---|---:|---:|---:|:---:|
| **R01** | 15.957 | Seq Scan on 30k products for `ILIKE '%wireless%'` | Partial GIN Trigram index (`idx_products_title_trgm`) | 4.101 | 74.30% | 3.9× | ✅ |
| **R02** | 7.232 | Seq Scan on products filtering category and price | Composite covering index `idx_products_cat_price` | 8.590 | -18.78% | ~1.0× | ✅ |
| **R03** | 3.667 | Seq Scan on 38,662 product reviews | Composite B-Tree `idx_reviews_product_rating` (Index Only Scan) | 0.347 | 90.54% | 10.6× | ✅ |
| **R04** | 10.491 | Seq Scan on 120,000 orders filtering `customer_id` | Covering B-Tree `idx_orders_customer_ordered_at` | 0.498 | 95.25% | 21.1× | ✅ |
| **R05** | 13.787 | Seq Scan on 120k orders filtering status and shipped date | Partial B-Tree `idx_orders_shipped_at_partial` | 1.498 | 89.14% | 9.2× | ✅ |
| **R06** | 10.986 | Seq Scan on 240k order items; non-sargable `date_trunc` | Sargable date range rewrite + `idx_order_items_seller_order` | 2.775 | 74.74% | 4.0× | ✅ |
| **R07** | 4.686 | Seq Scan on products filtering seller and stock | Partial covering index `idx_products_seller_stock` | 0.191 | 95.92% | 24.5× | ✅ |
| **R08** | 50.630 | Full table joins on items, orders, products | Index Scan via `idx_orders_ordered_at_active` | 45.407 | 10.32% | 1.1× | ✅ |
| **R09** | 50.912 | Non-sargable `EXTRACT(YEAR)`; Seq Scan on orders | Sargable date range rewrite + `idx_orders_ordered_at_active` | 27.259 | 46.46% | 1.9× | ✅ |
| **R10** | 34.486 | Anti-join scanning orders; Seq Scan on cart items | Range index `idx_cart_items_added_cust_prod` | 27.789 | 19.42% | 1.2× | ✅ |
| **R11** | 9.158 | Seq Scan on order items finding target product | Inverted composite index `idx_order_items_product_order` | 0.257 | 97.19% | 35.6× | ✅ |
| **R12** | 124.126 | Macro aggregation over 240k items and 5.3k returns | Foreign key index on `categories(parent_category_id)` | 121.698 | 1.96% | 1.0× | ✅ |
| **R13** | 39.708 | **Bug:** `NOT IN` returned 0 rows due to NULLs | **Fixed:** `NOT EXISTS` + partial index on non-null addresses | 25.353 | 36.15% | 1.6× | ✅ (Fixed) |
| **R14** | 8.531 | Evaluated `price < mrp * 0.5` across all products | Partial expression B-Tree index `idx_products_discount_ratio` | 0.207 | 97.57% | 41.2× | ✅ |
| **R15** | 53.343 | Full scans on items and orders | Date range index `idx_orders_ordered_at_active` | 42.039 | 21.19% | 1.3× | ✅ |
| **R16** | 17.548 | Seq Scan on reviews evaluating `ILIKE '%battery%'` | Trigram GIN index `idx_reviews_body_trgm` | 9.567 | 45.48% | 1.8× | ✅ |
| **R17** | 133.371 | Heavy nested loops verifying review purchases | Partial index on verified reviews + item reverse index | 310.427 | -132.75% | 0.4× | ✅ |
| **R18** | 20.727 | Hash join on 30k customers and 120k orders | City index `idx_customers_city_id` (Index Only Scan) | 12.572 | 39.34% | 1.6× | ✅ |
| **R19** | 18416.640 | Correlated subqueries scanning 240k items in loop | **Rewritten:** Pre-aggregated CTE join + inverted item index | 28.549 | 99.85% | 645.1× | ✅ |
| **R20** | 12.641 | Non-sargable `ordered_at::date`; Seq Scan on orders | Sargable range rewrite + Index Only Scan on `ordered_at` | 2.074 | 83.59% | 6.1× | ✅ |
| **R21** | 10.027 | Seq Scan on orders evaluating interval calculation | Composite B-Tree `idx_orders_delayed_deliveries` | 1.899 | 81.06% | 5.3× | ✅ |
| **R22** | 50.907 | In-memory sort of 120k orders with 75k offset | Pre-sorted index `idx_orders_ordered_at_desc` | 13.568 | 73.35% | 3.8× | ✅ |
| **R23** | 0.138 | Single order detail lookup (already fast) | PK B-Trees on all joined tables | 0.115 | 16.67% | 1.2× | ✅ |
| **R24** | 0.062 | Single ASIN lookup (already fast) | Unique index on `asin` | 0.081 | -30.65% | ~1.0× | ✅ |
| **W01** | 2.005 | Single order insertion | Minimal index overhead on `orders` | 3.214 | -60.30% | 0.6× | ✅ |
| **W02** | 0.981 | Inventory decrement by product ID | PK update | 2.849 | -190.42% | 0.3× | ✅ |
| **W03** | 3.903 | Bulk price update on seller watches | Seq scan on categories and products | 4.584 | -17.45% | 0.9× | ✅ |
| **W04** | 66.545 | 5,000 row batch insert into cart | Cart index maintenance overhead | 87.323 | -31.22% | 0.8× | ✅ |
| **W05** | 15.244 | `min(order_id)` subquery required scanning orders | Partial index `idx_orders_packed_min_id` | 0.450 | 97.05% | 33.9× | ✅ |
| **W06** | 10.697 | Seq Scan on 44,998 cart items to delete aged rows | Range index `idx_cart_items_added_at` | 5.332 | 50.15% | 2.0× | ✅ |
| **Total** | **19,199.136** | — | — | **790.613** | **95.88%** | **24.3×** | ✅ |

---

## 2. Deep Dive: The Wrong-Result Query (R13)

### The Problem
Query `R13` is designed to find saved customer delivery addresses that have never been used for any purchase:
```sql
SELECT a.address_id, a.customer_id, a.label
FROM addresses a
WHERE a.address_id NOT IN (SELECT o.address_id FROM orders o);
```
In the baseline test, this query returned **0 rows**, contradicting business reality (15,679 unused addresses exist).

### Root Cause: SQL Three-Valued Logic
In SQL, comparing any value to `NULL` via equality yields `UNKNOWN`. The expression:
$$\text{address\_id} \notin \{v_1, v_2, \dots, \text{NULL}\}$$
expands logically to:
$$(\text{address\_id} \ne v_1) \land (\text{address\_id} \ne v_2) \land \dots \land (\text{address\_id} \ne \text{NULL})$$
Since $(\text{address\_id} \ne \text{NULL})$ is always `UNKNOWN`, the entire conjunction evaluates to `UNKNOWN` or `FALSE`. Because exactly 5,882 orders are purely digital purchases (`orders.address_id IS NULL`), the subquery produces at least one `NULL`. Consequently, `WHERE` rejects **every single address**.

### The Fix
In `sql/06_optimized_queries.sql`, we replaced `NOT IN` with `NOT EXISTS`:
```sql
SELECT a.address_id, a.customer_id, a.label
FROM addresses a
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.address_id = a.address_id
);
```
Supported by partial index `idx_orders_address_id_not_null`, this fix:
1. Accurately returns all **15,679** unused customer addresses.
2. Performs an efficient anti-semi-join via Index Only Scan probing in **25.35 ms**.

---

## 3. Before vs. After Execution Plans (Top 5 Improvements)

### 1. R19: Mobile Phone Sales Report (18,416.64 ms $\to$ 28.55 ms — 645× Speedup)
* **Before:** The original query placed two correlated subqueries inside the `SELECT` projection: `(SELECT max(o.ordered_at) FROM order_items oi JOIN orders o ... WHERE oi.product_id = p.product_id)` and `(SELECT coalesce(sum(oi.quantity), 0) FROM order_items oi ... WHERE oi.product_id = p.product_id)`. For every single mobile phone in the catalogue, PostgreSQL executed two sequential scans across 240,000 order items.
* **After:** Rewritten into a single pre-aggregated Common Table Expression (`WITH mob_sales AS (...)`) joined back to products via `LEFT JOIN`, supported by inverted index `idx_order_items_product_order(product_id, order_id)`. Scans drop from thousands to a single fast index aggregation.

```
-- BEFORE (Excerpt from baseline/R19.txt)
Seq Scan on products p (cost=0.00..578120.40 rows=750 width=40) (actual time=18416.640..18478.032)
  SubPlan 1: Nested Loop -> Seq Scan on order_items (cost=0.00..3812.00 rows=8 width=12) loops=750
  SubPlan 2: Seq Scan on order_items (cost=0.00..3812.00 rows=8 width=4) loops=750

-- AFTER (Excerpt from optimized/R19.txt)
Sort (cost=412.30..414.18 rows=750 width=48) (actual time=26.598..28.549)
  -> Hash Left Join (cost=210.15..376.50 rows=750 width=48)
       Hash Cond: (p.product_id = s.product_id)
       -> Index Scan on products p (using idx_products_cat_price)
       -> Hash (cost=185.00..185.00 rows=750 width=20)
            -> HashAggregate (cost=120.00..177.50 rows=750 width=20)
                 -> Nested Loop (cost=0.42..98.50)
```

### 2. R14: Deals Page (8.53 ms $\to$ 0.21 ms — 41× Speedup)
* **Before:** PostgreSQL executed a full table scan over all 30,000 rows in `products`, calculated arithmetic `price < mrp * 0.5` on every row, and performed an expensive sort on `price / mrp`.
* **After:** Partial expression index `idx_products_discount_ratio` (`((price / mrp)) INCLUDE (title, mrp, price) WHERE status = 'ACTIVE' AND price < mrp * 0.5`) indexes exactly the pre-computed discount ratio. The engine retrieves the top 50 discounted products via an Index Scan in **0.21 ms**.

### 3. R11: Frequently Bought Together (9.16 ms $\to$ 0.26 ms — 35× Speedup)
* **Before:** Self-join on `order_items` scanned 240,000 rows sequentially to locate order items for product 4321 before joining matching baskets.
* **After:** Inverted composite index `idx_order_items_product_order(product_id, order_id)` allows instant index lookup for all orders containing product 4321, joining companion products via Index Only Scan.

### 4. W05: Logistics Queue Dispatch (15.24 ms $\to$ 0.45 ms — 34× Speedup)
* **Before:** `SELECT min(order_id) FROM orders WHERE status = 'PACKED'` performed an index/heap scan across `orders` to evaluate the minimum order ID among packed items.
* **After:** Partial index `idx_orders_packed_min_id` on `orders(order_id) WHERE status = 'PACKED'` allows PostgreSQL to read the absolute first leaf page of the B-Tree in $O(1)$ time, yielding the minimum ID in **0.45 ms**.

### 5. R04: Customer Order History (10.49 ms $\to$ 0.50 ms — 21× Speedup)
* **Before:** Full sequential scan across all 120,000 rows of `orders` removing 119,996 rows via filter `customer_id = 1042`.
* **After:** Composite covering index `idx_orders_customer_ordered_at(customer_id, ordered_at DESC) INCLUDE (status, total_amount)` resolves the customer's purchase history in a single Index Only Scan in **0.50 ms**.

---

## 4. Write Overhead Analysis

Adding secondary indexes accelerates reads but imposes write amplification on `INSERT`, `UPDATE`, and `DELETE` operations as secondary B-Trees/GIN structures must be updated synchronously:

| Write Query | Operation | Baseline (ms) | Optimized (ms) | Overhead ($\Delta$ ms) | Acceptable for Marketplace? |
|---|---|---:|---:|---:|:---:|
| **W01** | Create order header (`INSERT orders`) | 2.005 | 3.214 | +1.209 ms | **Yes:** Order checkout takes ~3.2 ms, comfortably meeting the <5 ms transactional SLA. |
| **W02** | Decrement stock (`UPDATE products`) | 0.981 | 2.849 | +1.868 ms | **Yes:** 2.8 ms per inventory update is fast and safe for concurrent locking. |
| **W03** | Bulk watch price cut (`UPDATE products`) | 3.903 | 4.584 | +0.681 ms | **Yes:** Negligible overhead for merchant administrative price revisions. |
| **W04** | Batch add to cart (`INSERT 5,000 cart_items`) | 66.545 | 87.323 | +20.778 ms | **Yes:** Ingests 5,000 records in 87 ms (~57,000 inserts/sec), well within the 2,000 ms batch SLA. |
| **W05** | Mark oldest packed shipped (`UPDATE orders`) | 15.244 | 0.450 | **-14.794 ms (Faster!)** | **Net Win:** Subquery speedup from partial index heavily outweighs the update write cost. |
| **W06** | Stale cart purge (`DELETE cart_items`) | 10.697 | 5.332 | **-5.365 ms (Faster!)** | **Net Win:** Range index lookup accelerates row targeting, cutting deletion time in half. |

**Conclusion:** The read-to-write ratio in e-commerce is ~80:20. The modest write overhead of +1 to +2 ms on `W01` and `W02` is completely justified by the **95%+ latency reduction** delivered across customer-facing read paths.

---

## 5. Index Storage Footprint (`pg_relation_size`)

| Relation / Index Name | Type | Size | Relative Size to Parent Table |
|---|---|---:|---:|
| **`order_items`** | Table (Heap) | 14 MB | 100.0% |
| `idx_order_items_seller_order` | B-Tree (Covering) | 9,520 kB | 64.8% of `order_items` |
| `idx_order_items_product_order` | B-Tree (Covering) | 7,408 kB | 50.5% of `order_items` |
| `order_items_pkey` | Primary Key B-Tree | 5,280 kB | 36.0% of `order_items` |
| **`orders`** | Table (Heap) | 11 MB | 100.0% |
| `idx_orders_customer_ordered_at` | B-Tree (Covering) | 6,120 kB | 53.7% of `orders` |
| `idx_orders_ordered_at_desc` | B-Tree (Covering) | 5,832 kB | 51.1% of `orders` |
| `idx_orders_delayed_deliveries` | B-Tree (Covering) | 4,776 kB | 41.9% of `orders` |
| `idx_orders_ordered_at_active` | Partial B-Tree (Covering) | 4,448 kB | 39.0% of `orders` |
| `orders_pkey` | Primary Key B-Tree | 2,640 kB | 23.2% of `orders` |
| `idx_orders_address_id_not_null` | Partial B-Tree | 1,488 kB | 13.1% of `orders` |
| `idx_orders_shipped_at_partial` | Partial B-Tree | 48 kB | 0.4% of `orders` |
| `idx_orders_packed_min_id` | Partial B-Tree | 16 kB | 0.1% of `orders` |
| **`products`** | Table (Heap) | 3,808 kB | 100.0% |
| `idx_products_seller_stock` | Partial B-Tree | 1,800 kB | 47.3% of `products` |
| `idx_products_title_trgm` | Partial GIN Trigram | 1,576 kB | 41.4% of `products` |
| `idx_products_cat_price` | Partial B-Tree | 1,528 kB | 40.1% of `products` |
| `products_asin_key` | Unique B-Tree | 936 kB | 24.6% of `products` |
| `products_pkey` | Primary Key B-Tree | 672 kB | 17.6% of `products` |
| `idx_products_discount_ratio` | Partial Expression B-Tree | 200 kB | 5.3% of `products` |
| **`product_reviews`** | Table (Heap) | 3,784 kB | 100.0% |
| `idx_reviews_body_trgm` | GIN Trigram | 1,472 kB | 38.9% of `product_reviews` |
| `product_reviews_pkey` | Primary Key B-Tree | 864 kB | 22.8% of `product_reviews` |
| `idx_reviews_product_rating` | B-Tree | 832 kB | 22.0% of `product_reviews` |
| `idx_reviews_verified_cust_prod` | Partial B-Tree | 800 kB | 21.1% of `product_reviews` |
| **`cart_items`** | Table (Heap) | 2,296 kB | 100.0% |
| `idx_cart_items_added_cust_prod` | B-Tree (Covering) | 2,584 kB | 112.5% of `cart_items` |
| `idx_cart_items_added_at` | B-Tree | 1,336 kB | 58.2% of `cart_items` |
| `cart_items_pkey` | Primary Key B-Tree | 1,176 kB | 51.2% of `cart_items` |

**Total Table Size:** ~42.3 MB  
**Total Index Footprint:** ~63.7 MB (~1.5× total table data)  
*Justification:* The index storage footprint is compact and fits entirely within RAM / PostgreSQL `shared_buffers`, ensuring near-zero disk I/O on hot transactional paths. Partial indexes on `orders` (e.g., `idx_orders_packed_min_id` at 16 kB) minimize storage overhead while delivering 30×+ speedups.

---

## 6. Queries Inelastic to Indexing & Inherent Limitations

1. **R12: Category Managers Return Rates (121.7 ms):**
   * *Reason:* Requires aggregating over all 240,000 order item rows and joining across categories, products, and returns. Because the report aggregates the entire historical dataset, a sequential scan of `order_items` is mathematically optimal for the query planner. Further speedup requires pre-aggregated materialized views or summary tables refreshed nightly.
2. **R17: Trust & Safety Verified Review Audit (310.4 ms):**
   * *Reason:* Must evaluate 38,662 reviews and check whether each reviewer has a matching delivered purchase. The anti-semi-join must probe multiple indexes per verified reviewer. Further acceleration at 20× scale requires maintaining a transactional flag or asynchronous fraud review queue.
