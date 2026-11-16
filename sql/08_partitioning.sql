-- =====================================================================
-- Phase 5: Range Partitioning DDL & Partition Pruning Demonstration
-- Database: PostgreSQL 15+
-- Schema: amazon
-- Description: Declarative RANGE partitioning on orders by ordered_at.
--              Includes quarterly partition definitions, data migration,
--              local partition indexes, and partition pruning verification.
-- =====================================================================

SET search_path TO amazon, public;

-- Drop previous partitioned table if exists
DROP TABLE IF EXISTS orders_partitioned CASCADE;

-- 1. Create Partitioned Orders Table
-- Technical Note on Primary Key:
-- In PostgreSQL declarative partitioning, any UNIQUE or PRIMARY KEY constraint
-- on a partitioned table MUST include all partition key columns. Therefore, the
-- primary key is defined as a composite key: (order_id, ordered_at).
CREATE TABLE orders_partitioned (
    order_id INT NOT NULL,
    customer_id INT NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    address_id INT REFERENCES addresses(address_id) ON DELETE RESTRICT,
    ordered_at TIMESTAMPTZ NOT NULL,
    payment_method VARCHAR(30) NOT NULL,
    total_amount NUMERIC(12, 2) NOT NULL,
    status VARCHAR(30) NOT NULL,
    shipped_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    PRIMARY KEY (order_id, ordered_at),
    CONSTRAINT chk_orders_part_status CHECK (status IN ('PLACED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED', 'RETURNED')),
    CONSTRAINT chk_orders_part_payment CHECK (payment_method IN ('CARD', 'UPI', 'NETBANKING', 'COD', 'EMI', 'GIFT_CARD')),
    CONSTRAINT chk_orders_part_amount CHECK (total_amount >= 0),
    CONSTRAINT chk_orders_part_dates CHECK (
        (shipped_at IS NULL OR shipped_at >= ordered_at) AND 
        (delivered_at IS NULL OR delivered_at >= ordered_at)
    )
) PARTITION BY RANGE (ordered_at);

-- 2. Define Quarterly Child Partitions
-- Historical Partitions (2025)
CREATE TABLE orders_2025_q1 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+05:30') TO ('2025-04-01 00:00:00+05:30');

CREATE TABLE orders_2025_q2 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+05:30') TO ('2025-07-01 00:00:00+05:30');

CREATE TABLE orders_2025_q3 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+05:30') TO ('2025-10-01 00:00:00+05:30');

CREATE TABLE orders_2025_q4 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+05:30') TO ('2026-01-01 00:00:00+05:30');

-- Active / Recent Partitions (2026)
CREATE TABLE orders_2026_q1 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+05:30') TO ('2026-04-01 00:00:00+05:30');

CREATE TABLE orders_2026_q2 PARTITION OF orders_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');

-- Future Partition Catch-All
CREATE TABLE orders_future PARTITION OF orders_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+05:30') TO (MAXVALUE);

-- 3. Local Partition Indexes
-- In PostgreSQL 11+, defining an index on the partitioned parent automatically creates
-- matching local indexes on all current and future child partitions.
CREATE INDEX idx_orders_part_customer
    ON orders_partitioned (customer_id, ordered_at DESC)
    INCLUDE (status, total_amount);

CREATE INDEX idx_orders_part_ordered_at_desc
    ON orders_partitioned (ordered_at DESC)
    INCLUDE (customer_id, status, total_amount);

CREATE INDEX idx_orders_part_status_packed
    ON orders_partitioned (order_id)
    WHERE status = 'PACKED';

-- 4. Data Migration from Monolithic Orders Table
INSERT INTO orders_partitioned
SELECT * FROM orders;

-- 5. Analyze to update planner statistics
ANALYZE orders_partitioned;

-- 6. Demonstration of Partition Pruning
-- This query targets June 2026. The planner prunes all partitions except orders_2026_q2.
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) AS june_orders, round(avg(total_amount), 2) AS avg_gmv
FROM orders_partitioned
WHERE ordered_at >= '2026-06-01 00:00:00+05:30' AND ordered_at < '2026-07-01 00:00:00+05:30'
  AND status <> 'CANCELLED';
