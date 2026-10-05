/*
=========================================================
NORTHSTAR SUPPLY CHAIN INTELLIGENCE
01 - DATABASE SCHEMA CREATION
=========================================================

Purpose:
Creates the relational database schema used for the
Northstar Supply Chain analytics project.

Tables:
- categories
- products
- suppliers
- warehouses
- date_dim
- product_suppliers
- sales
- purchases
- inventory
=========================================================
*/

CREATE DATABASE IF NOT EXISTS northstar_supply_chain;

USE northstar_supply_chain;

-- =====================================================
-- 1. CATEGORIES
-- =====================================================

CREATE TABLE IF NOT EXISTS categories (
    category_id VARCHAR(10) NOT NULL,
    category_name VARCHAR(100) NOT NULL,
    PRIMARY KEY (category_id)
);


-- =====================================================
-- 2. SUPPLIERS
-- =====================================================

CREATE TABLE IF NOT EXISTS suppliers (
    supplier_id VARCHAR(10) NOT NULL,
    supplier_name VARCHAR(100) NOT NULL,
    supplier_location VARCHAR(100) NOT NULL,
    standard_lead_time_days INT NOT NULL,
    PRIMARY KEY (supplier_id)
);


-- =====================================================
-- 3. WAREHOUSES
-- =====================================================

CREATE TABLE IF NOT EXISTS warehouses (
    warehouse_id VARCHAR(10) NOT NULL,
    warehouse_name VARCHAR(100) NOT NULL,
    PRIMARY KEY (warehouse_id)
);


-- =====================================================
-- 4. DATE DIMENSION
-- =====================================================

CREATE TABLE IF NOT EXISTS date_dim (
    date DATE NOT NULL,
    month VARCHAR(20) NOT NULL,
    quarter VARCHAR(10) NOT NULL,
    year INT NOT NULL,
    PRIMARY KEY (date)
);


-- =====================================================
-- 5. PRODUCTS
-- =====================================================

CREATE TABLE IF NOT EXISTS products (
    product_id VARCHAR(10) NOT NULL,
    product_name VARCHAR(100) NOT NULL,
    category_id VARCHAR(10) NOT NULL,
    unit_cost DECIMAL(10,2) NOT NULL,
    selling_price DECIMAL(10,2) NOT NULL,
    holding_cost_per_unit DECIMAL(10,2) NOT NULL,
    moq INT NOT NULL,

    PRIMARY KEY (product_id),

    CONSTRAINT fk_products_category
        FOREIGN KEY (category_id)
        REFERENCES categories(category_id)
);


-- =====================================================
-- 6. PRODUCT-SUPPLIER BRIDGE
-- =====================================================

CREATE TABLE IF NOT EXISTS product_suppliers (
    product_id VARCHAR(10) NOT NULL,
    supplier_id VARCHAR(10) NOT NULL,
    is_primary_supplier BOOLEAN NOT NULL,
    supplier_unit_cost DECIMAL(10,2) NOT NULL,

    PRIMARY KEY (product_id, supplier_id),

    CONSTRAINT fk_ps_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id),

    CONSTRAINT fk_ps_supplier
        FOREIGN KEY (supplier_id)
        REFERENCES suppliers(supplier_id)
);


-- =====================================================
-- 7. SALES
-- =====================================================

CREATE TABLE IF NOT EXISTS sales (
    sale_id VARCHAR(20) NOT NULL,
    product_id VARCHAR(10) NOT NULL,
    sale_date DATE NOT NULL,
    quantity INT NOT NULL,

    PRIMARY KEY (sale_id),

    CONSTRAINT fk_sales_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id),

    CONSTRAINT fk_sales_date
        FOREIGN KEY (sale_date)
        REFERENCES date_dim(date)
);


-- =====================================================
-- 8. PURCHASES
-- =====================================================

CREATE TABLE IF NOT EXISTS purchases (
    purchase_id VARCHAR(20) NOT NULL,
    product_id VARCHAR(10) NOT NULL,
    supplier_id VARCHAR(10) NOT NULL,
    purchase_date DATE NOT NULL,
    quantity INT NOT NULL,
    unit_cost DECIMAL(10,2) NOT NULL,
    expected_delivery_date DATE NOT NULL,
    actual_delivery_date DATE NOT NULL,
    warehouse_id VARCHAR(10) NOT NULL,

    PRIMARY KEY (purchase_id),

    CONSTRAINT fk_purchases_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id),

    CONSTRAINT fk_purchases_supplier
        FOREIGN KEY (supplier_id)
        REFERENCES suppliers(supplier_id),

    CONSTRAINT fk_purchases_purchase_date
        FOREIGN KEY (purchase_date)
        REFERENCES date_dim(date),

    CONSTRAINT fk_purchases_expected_date
        FOREIGN KEY (expected_delivery_date)
        REFERENCES date_dim(date),

    CONSTRAINT fk_purchases_actual_date
        FOREIGN KEY (actual_delivery_date)
        REFERENCES date_dim(date),

    CONSTRAINT fk_purchases_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES warehouses(warehouse_id)
);


-- =====================================================
-- 9. INVENTORY
-- =====================================================

CREATE TABLE IF NOT EXISTS inventory (
    date DATE NOT NULL,
    product_id VARCHAR(10) NOT NULL,
    warehouse_id VARCHAR(10) NOT NULL,
    opening_stock INT NOT NULL,
    received_quantity INT NOT NULL,
    demand_quantity INT NOT NULL,
    sold_quantity INT NOT NULL,
    stockout_quantity INT NOT NULL,
    closing_stock INT NOT NULL,

    PRIMARY KEY (date, product_id, warehouse_id),

    CONSTRAINT fk_inventory_date
        FOREIGN KEY (date)
        REFERENCES date_dim(date),

    CONSTRAINT fk_inventory_product
        FOREIGN KEY (product_id)
        REFERENCES products(product_id),

    CONSTRAINT fk_inventory_warehouse
        FOREIGN KEY (warehouse_id)
        REFERENCES warehouses(warehouse_id)
);