-- =====================================================================
-- Phase 2: Schema Definition
-- Database: PostgreSQL 15+
-- Schema: amazon
-- Description: Amazon Online Shopping Database Schema with constraints,
--              keys, and domain validations.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS amazon;
SET search_path TO amazon;

-- Drop existing tables if needed (in reverse dependency order)
DROP TABLE IF EXISTS cart_items CASCADE;
DROP TABLE IF EXISTS product_reviews CASCADE;
DROP TABLE IF EXISTS returns CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS addresses CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS sellers CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS cities CASCADE;

-- 1. Cities
CREATE TABLE cities (
    city_id INT PRIMARY KEY,
    city_name VARCHAR(100) NOT NULL UNIQUE,
    state VARCHAR(100) NOT NULL
);

-- 2. Categories (Self-referencing tree)
CREATE TABLE categories (
    category_id INT PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    parent_category_id INT REFERENCES categories(category_id) ON DELETE RESTRICT,
    is_digital BOOLEAN NOT NULL DEFAULT false
);

-- 3. Sellers
CREATE TABLE sellers (
    seller_id INT PRIMARY KEY,
    business_name VARCHAR(150) NOT NULL,
    gstin VARCHAR(15) NOT NULL UNIQUE,
    city_id INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    joined_on DATE NOT NULL,
    seller_rating NUMERIC(2, 1) NOT NULL,
    status VARCHAR(20) NOT NULL,
    CONSTRAINT chk_sellers_status CHECK (status IN ('ACTIVE', 'SUSPENDED', 'CLOSED')),
    CONSTRAINT chk_sellers_rating CHECK (seller_rating >= 1.0 AND seller_rating <= 5.0),
    CONSTRAINT chk_sellers_gstin CHECK (length(gstin) = 15)
);

-- 4. Customers
CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(15) NOT NULL UNIQUE,
    city_id INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    signup_date DATE NOT NULL,
    is_prime BOOLEAN NOT NULL DEFAULT false,
    prime_since DATE,
    CONSTRAINT chk_customers_phone CHECK (phone ~ '^[0-9]{10}$'),
    CONSTRAINT chk_customers_prime CHECK (
        (is_prime = true AND prime_since IS NOT NULL) OR 
        (is_prime = false AND prime_since IS NULL)
    )
);

-- 5. Addresses
CREATE TABLE addresses (
    address_id INT PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    label VARCHAR(20) NOT NULL,
    line1 VARCHAR(255) NOT NULL,
    city_id INT NOT NULL REFERENCES cities(city_id) ON DELETE RESTRICT,
    pincode VARCHAR(6) NOT NULL,
    is_default BOOLEAN NOT NULL DEFAULT false,
    CONSTRAINT chk_addresses_label CHECK (label IN ('HOME', 'WORK')),
    CONSTRAINT chk_addresses_pincode CHECK (pincode ~ '^[0-9]{6}$')
);

-- 6. Products
CREATE TABLE products (
    product_id INT PRIMARY KEY,
    asin VARCHAR(10) NOT NULL UNIQUE,
    seller_id INT NOT NULL REFERENCES sellers(seller_id) ON DELETE RESTRICT,
    category_id INT NOT NULL REFERENCES categories(category_id) ON DELETE RESTRICT,
    title VARCHAR(255) NOT NULL,
    brand VARCHAR(100) NOT NULL,
    mrp NUMERIC(10, 2) NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    stock_qty INT NOT NULL DEFAULT 0,
    is_prime_eligible BOOLEAN NOT NULL DEFAULT false,
    avg_rating NUMERIC(2, 1),
    review_count INT NOT NULL DEFAULT 0,
    listed_on DATE NOT NULL,
    status VARCHAR(20) NOT NULL,
    CONSTRAINT chk_products_status CHECK (status IN ('ACTIVE', 'OUT_OF_STOCK', 'INACTIVE')),
    CONSTRAINT chk_products_mrp_price CHECK (mrp > 0 AND price >= 0 AND price <= mrp),
    CONSTRAINT chk_products_stock CHECK (stock_qty >= 0),
    CONSTRAINT chk_products_asin CHECK (length(asin) = 10),
    CONSTRAINT chk_products_avg_rating CHECK (avg_rating IS NULL OR (avg_rating >= 1.0 AND avg_rating <= 5.0)),
    CONSTRAINT chk_products_review_count CHECK (review_count >= 0)
);

-- 7. Orders
CREATE TABLE orders (
    order_id INT PRIMARY KEY,
    customer_id INT NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    address_id INT REFERENCES addresses(address_id) ON DELETE RESTRICT,
    ordered_at TIMESTAMPTZ NOT NULL,
    payment_method VARCHAR(30) NOT NULL,
    total_amount NUMERIC(12, 2) NOT NULL,
    status VARCHAR(30) NOT NULL,
    shipped_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    CONSTRAINT chk_orders_status CHECK (status IN ('PLACED', 'PACKED', 'SHIPPED', 'OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED', 'RETURNED')),
    CONSTRAINT chk_orders_payment_method CHECK (payment_method IN ('CARD', 'UPI', 'NETBANKING', 'COD', 'EMI', 'GIFT_CARD')),
    CONSTRAINT chk_orders_amount CHECK (total_amount >= 0),
    CONSTRAINT chk_orders_dates CHECK (
        (shipped_at IS NULL OR shipped_at >= ordered_at) AND 
        (delivered_at IS NULL OR delivered_at >= ordered_at)
    )
);

-- 8. Order Items
CREATE TABLE order_items (
    order_id INT NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    line_no INT NOT NULL,
    product_id INT NOT NULL REFERENCES products(product_id) ON DELETE RESTRICT,
    seller_id INT NOT NULL REFERENCES sellers(seller_id) ON DELETE RESTRICT,
    quantity INT NOT NULL,
    unit_price NUMERIC(10, 2) NOT NULL,
    PRIMARY KEY (order_id, line_no),
    CONSTRAINT chk_order_items_qty CHECK (quantity > 0),
    CONSTRAINT chk_order_items_price CHECK (unit_price >= 0)
);

-- 9. Returns
CREATE TABLE returns (
    return_id INT PRIMARY KEY,
    order_id INT NOT NULL,
    line_no INT NOT NULL,
    reason VARCHAR(50) NOT NULL,
    requested_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(30) NOT NULL,
    refund_amount NUMERIC(10, 2),
    FOREIGN KEY (order_id, line_no) REFERENCES order_items(order_id, line_no) ON DELETE RESTRICT,
    CONSTRAINT uq_returns_order_line UNIQUE (order_id, line_no),
    CONSTRAINT chk_returns_reason CHECK (reason IN ('QUALITY_ISSUE', 'WRONG_ITEM', 'NOT_AS_DESCRIBED', 'SIZE_ISSUE', 'DAMAGED', 'NO_LONGER_NEEDED')),
    CONSTRAINT chk_returns_status CHECK (status IN ('REQUESTED', 'PICKED_UP', 'REFUNDED', 'REJECTED')),
    CONSTRAINT chk_returns_refund CHECK (
        (status = 'REFUNDED' AND refund_amount IS NOT NULL AND refund_amount > 0) OR 
        (status <> 'REFUNDED' AND refund_amount IS NULL)
    )
);

-- 10. Product Reviews
CREATE TABLE product_reviews (
    review_id INT PRIMARY KEY,
    product_id INT NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    customer_id INT NOT NULL REFERENCES customers(customer_id) ON DELETE RESTRICT,
    rating INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    body TEXT,
    verified_purchase BOOLEAN NOT NULL DEFAULT false,
    helpful_votes INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT chk_reviews_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT chk_reviews_helpful CHECK (helpful_votes >= 0)
);

-- 11. Cart Items
CREATE TABLE cart_items (
    customer_id INT NOT NULL REFERENCES customers(customer_id) ON DELETE CASCADE,
    product_id INT NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    quantity INT NOT NULL DEFAULT 1,
    added_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (customer_id, product_id),
    CONSTRAINT chk_cart_qty CHECK (quantity > 0)
);

