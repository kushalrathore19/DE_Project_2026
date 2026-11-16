# Phase 1: Problem Understanding & Workload Classification

**Course:** Database Management Systems · **Project:** Amazon Online Shopping Database  
**Author / Team:** Kushal Rathore (`kushalrathore19`), Adarsh Chauhan (`mriarc-08`), Lakshya (`lakshyapvt2010-ux`), Oojass Kwatra (`oojasskwatra-gif`)  
**Database:** PostgreSQL 18.3  

---

## 1. Problem Statements & Business Requirements (P1 – P9)

### P1: Search & Category Navigation Latency
* **Business Need:** High-speed product discovery and category browsing. Shoppers expect responsive text search and deep category traversal (handling parent-child hierarchies) within sub-second latencies (<250 ms) to avoid bounce and checkout abandonment.
* **Stakeholders Affected:** Shoppers / Customers, Search & Navigation Product Team.
* **Workload Group:** Customer-facing / Real-time (Interactive Search).
* **Associated Queries:** `R01`, `R02`, `R14`.

### P2: Slow Product Detail Page Rendering
* **Business Need:** Instantaneous page loads on high-traffic product listings. Aggregate star ratings, review breakdowns, and co-purchase recommendations ("Frequently Bought Together") must compute without blocking page render (<5 ms target).
* **Stakeholders Affected:** Shoppers, Retail Experience Team, Conversion Optimization Team.
* **Workload Group:** Customer-facing / Real-time.
* **Associated Queries:** `R03`, `R11`, `R24`.

### P3: "Your Orders" & Order Detail Latency
* **Business Need:** Customers and support agents require immediate access to full purchase history, order statuses, and item breakdowns. Slow queries degrade user satisfaction and increase customer support tickets.
* **Stakeholders Affected:** Shoppers, Customer Support Representatives, Mobile/Web Client Apps.
* **Workload Group:** Customer-facing / Real-time.
* **Associated Queries:** `R04`, `R23`.

### P4: Sluggish Seller Central Dashboards
* **Business Need:** Marketplace merchants depend on Seller Central to monitor daily order fulfillment, manage inventory levels to prevent stockouts, and execute pricing changes. Slow queries disrupt vendor operations.
* **Stakeholders Affected:** Third-Party Marketplace Sellers, Merchant Success Team.
* **Workload Group:** Interactive Merchant Portal (Hybrid: Real-time queries `R06`, `R07`, `W02`, `W03`; Analytical ranking `R15`).
* **Associated Queries:** `R06`, `R07`, `R15`, `W02`, `W03`.

### P5: Bottlenecks in Logistics & Dispatch Operations
* **Business Need:** Fulfillment centers require instant identification of delayed in-transit shipments (>10 days) and automated dispatch queues to transition packed orders into shipped status. Delays harm Prime SLA commitments.
* **Stakeholders Affected:** Supply Chain & Logistics Operations, Fulfillment Center Dispatchers, End Customers.
* **Workload Group:** Operational Real-time / Operations Management.
* **Associated Queries:** `R05`, `R21`, `W05`.

### P6: Flawed Address Clean-up Reporting (Data Quality Bug)
* **Business Need:** Routine maintenance jobs must identify unused customer delivery addresses for pruning. The existing report incorrectly indicates zero unused addresses due to SQL three-valued logic (`NOT IN` subquery encountering `NULL` `address_id` values from digital orders).
* **Stakeholders Affected:** Data Quality Engineers, Database Administrators, Customer Support.
* **Workload Group:** Reporting & Database Maintenance.
* **Associated Queries:** `R13`.

### P7: Prolonged Abandoned-Cart Campaigns & Purge Jobs
* **Business Need:** Marketing automation requires fast segmentation of high-value abandoned carts for recovery emails, while nightly database maintenance must delete stale cart records (>90 days) without causing locks on active shopper sessions.
* **Stakeholders Affected:** Growth & Lifecycle Marketing Team, Database Administrators.
* **Workload Group:** Batch Jobs & Analytical Marketing.
* **Associated Queries:** `R10`, `W04`, `W06`.

### P8: Review Fraud Detection & Sentiment Text Mining
* **Business Need:** Trust & Safety investigators must maintain marketplace integrity by detecting fabricated "Verified Purchase" reviews (reviews with no corresponding delivered order) and querying customer sentiment on product defect issues (e.g., battery degradation).
* **Stakeholders Affected:** Trust & Safety Team, Legal & Compliance, Brand Managers.
* **Workload Group:** Reporting & Fraud Detection Analytics.
* **Associated Queries:** `R16`, `R17`.

### P9: Financial, Prime & Category Management Scalability (20× Traffic Surge)
* **Business Need:** Leadership, Category Managers, and Finance require complex aggregation (return percentages, average order value comparisons for Prime vs. non-Prime, running Gross Merchandise Value, spending tiers, deep offset pagination) capable of scaling across 20× dataset growth without query timeouts.
* **Stakeholders Affected:** Finance Directors, Category Managers, Prime Program Leads, Executive Analytics.
* **Workload Group:** Executive Reporting & OLAP Analytics.
* **Associated Queries:** `R08`, `R09`, `R12`, `R18`, `R19`, `R20`, `R22`, `W01`.

---

## 2. Workload Classification Summary

| Class | Target Response Time | Queries Included | Primary Optimization Strategy |
|---|---|---|---|
| **Real-time / Customer-Facing** | < 5 ms | `R03`, `R04`, `R05`, `R07`, `R11`, `R23`, `R24`, `W01`, `W02`, `W03`, `W05` | Selective B-tree index lookups, covering indexes (`INCLUDE`), efficient composite PKs. |
| **Interactive Search & Seller Tools** | < 250 ms | `R01`, `R02`, `R06`, `R13`, `R14`, `R16`, `R21`, `R22` | Trigram GIN indexes (`pg_trgm`), recursive query optimization, keyset pagination. |
| **Reports & Analytics** | < 5,000 ms | `R08`, `R09`, `R10`, `R12`, `R15`, `R17`, `R18`, `R19`, `R20` | Date-range composite indexes, partial indexes, correlated subquery removal. |
| **Batch Maintenance** | < 2,000 ms | `W04`, `W06` | Minimal index overhead on high-frequency tables, partitioned bulk purges. |

---

## 3. Key Business & Technical Assumptions

1. **Transactional vs. Reporting Coexistence:** All 30 queries operate against the primary PostgreSQL engine during baseline; optimizations must maintain ACID transactional consistency without degrading write throughput excessively.
2. **Read-to-Write Skew:** As a marketplace, reads outnumber writes by ~80:20. Modest write overhead on inserts/updates is acceptable if customer-facing read latencies are dramatically cut.
3. **Digital vs. Physical Orders:** Orders containing exclusively digital items (e-books, digital gift cards) legitimately have `address_id IS NULL` and `shipped_at IS NULL` (instant electronic delivery). Constraints and reports must account for this domain rule.
4. **Data Immutability & Consistency:** Seed data reflects historical operational facts (120,000 orders). Functional dependencies (e.g., `products.review_count`, `products.avg_rating`, `orders.total_amount`) are derived caches that must match detailed tables.

