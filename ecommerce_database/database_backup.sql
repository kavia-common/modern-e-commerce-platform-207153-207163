--
-- PostgreSQL schema + seed data for modern e-commerce platform
-- Aligned with container startup defaults:
--   DB_NAME=myapp, DB_USER=appuser, DB_PORT=5000
--
-- NOTE:
-- - This file is intended to be used with restore_db.sh (psql < database_backup.sql).
-- - It includes schema creation and seed data.
-- - Password hashes here are placeholders; application layer should store proper hashes.
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Tables
--

DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS cart_items CASCADE;
DROP TABLE IF EXISTS carts CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS users CASCADE;

CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    full_name TEXT,
    role TEXT NOT NULL DEFAULT 'customer' CHECK (role IN ('customer', 'admin')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_role ON users(role);

CREATE TABLE products (
    id BIGSERIAL PRIMARY KEY,
    sku TEXT UNIQUE,
    name TEXT NOT NULL,
    description TEXT,
    price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
    currency TEXT NOT NULL DEFAULT 'USD',
    image_url TEXT,
    stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_products_active ON products(is_active);
CREATE INDEX idx_products_name_search
ON products
USING gin (to_tsvector('english', coalesce(name,'') || ' ' || coalesce(description,'')));

CREATE TABLE carts (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'converted', 'abandoned')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(user_id, status) DEFERRABLE INITIALLY IMMEDIATE
);

CREATE INDEX idx_carts_user_id ON carts(user_id);

CREATE TABLE cart_items (
    id BIGSERIAL PRIMARY KEY,
    cart_id BIGINT NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(cart_id, product_id)
);

CREATE INDEX idx_cart_items_cart_id ON cart_items(cart_id);

CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','shipped','delivered','cancelled','refunded')),
    subtotal_cents INTEGER NOT NULL CHECK (subtotal_cents >= 0),
    tax_cents INTEGER NOT NULL DEFAULT 0 CHECK (tax_cents >= 0),
    shipping_cents INTEGER NOT NULL DEFAULT 0 CHECK (shipping_cents >= 0),
    total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
    currency TEXT NOT NULL DEFAULT 'USD',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_orders_user_created_at ON orders(user_id, created_at DESC);

CREATE TABLE order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0),
    line_total_cents INTEGER NOT NULL CHECK (line_total_cents >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(order_id, product_id)
);

CREATE INDEX idx_order_items_order_id ON order_items(order_id);

--
-- Seed data
--

INSERT INTO users (email, password_hash, full_name, role)
VALUES
  ('admin@example.com', 'changeme', 'Admin User', 'admin'),
  ('customer@example.com', 'changeme', 'Customer One', 'customer');

INSERT INTO products (sku, name, description, price_cents, currency, image_url, stock_quantity, is_active)
VALUES
  ('RETRO-TSHIRT-001','Retro Logo T-Shirt','Soft cotton tee with a vintage logo print.',2499,'USD',NULL,100,TRUE),
  ('NEON-MUG-002','Neon Grid Mug','Ceramic mug with neon grid pattern for late-night coding.',1599,'USD',NULL,200,TRUE),
  ('VHS-TOTE-003','VHS Tape Tote Bag','Canvas tote bag inspired by classic VHS tapes.',1299,'USD',NULL,150,TRUE);

-- Active cart for the sample customer
INSERT INTO carts (user_id, status)
SELECT id, 'active' FROM users WHERE email='customer@example.com';

-- Cart items for the sample customer
INSERT INTO cart_items (cart_id, product_id, quantity, unit_price_cents)
SELECT c.id, p.id, 2, p.price_cents
FROM carts c
JOIN users u ON u.id = c.user_id
JOIN products p ON p.sku = 'RETRO-TSHIRT-001'
WHERE u.email='customer@example.com' AND c.status='active';

INSERT INTO cart_items (cart_id, product_id, quantity, unit_price_cents)
SELECT c.id, p.id, 1, p.price_cents
FROM carts c
JOIN users u ON u.id = c.user_id
JOIN products p ON p.sku = 'NEON-MUG-002'
WHERE u.email='customer@example.com' AND c.status='active';

-- Sample paid order + one item
INSERT INTO orders (user_id, status, subtotal_cents, tax_cents, shipping_cents, total_cents, currency)
SELECT u.id, 'paid', 0, 0, 0, 0, 'USD'
FROM users u
WHERE u.email='customer@example.com';

INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents, line_total_cents)
SELECT o.id, p.id, 1, p.price_cents, p.price_cents
FROM orders o
JOIN users u ON u.id = o.user_id
JOIN products p ON p.sku = 'VHS-TOTE-003'
WHERE u.email='customer@example.com'
ORDER BY o.id DESC
LIMIT 1;

-- Recompute totals from seeded order_items
UPDATE orders o
SET subtotal_cents = s.subtotal,
    total_cents = s.subtotal + o.tax_cents + o.shipping_cents
FROM (
  SELECT order_id, SUM(line_total_cents) AS subtotal
  FROM order_items
  GROUP BY order_id
) s
WHERE o.id = s.order_id;
