/*
=========================================================
NORTHSTAR SUPPLY CHAIN INTELLIGENCE
02 - DATA QUALITY CHECKS
=========================================================

Purpose:
Validate the integrity and consistency of the Northstar
dataset before performing business analysis.

Checks include:
- Row counts
- Duplicate keys
- Missing values
- Referential integrity
- Invalid numeric values
- Inventory reconciliation
- Stockout reconciliation
- Purchase and delivery consistency
=========================================================
*/

USE northstar_supply_chain;

-- =====================================================
-- CHECK 1: ROW COUNTS
-- Establish the size of each table after data loading.
-- =====================================================

SELECT 'categories' AS table_name, COUNT(*) AS row_count
FROM categories

UNION ALL

SELECT 'products', COUNT(*)
FROM products

UNION ALL

SELECT 'suppliers', COUNT(*)
FROM suppliers

UNION ALL

SELECT 'warehouses', COUNT(*)
FROM warehouses

UNION ALL

SELECT 'date_dim', COUNT(*)
FROM date_dim

UNION ALL

SELECT 'product_suppliers', COUNT(*)
FROM product_suppliers

UNION ALL

SELECT 'sales', COUNT(*)
FROM sales

UNION ALL

SELECT 'purchases', COUNT(*)
FROM purchases

UNION ALL

SELECT 'inventory', COUNT(*)
FROM inventory;

-- =====================================================
-- CHECK 2: DUPLICATE PRIMARY KEYS
-- Expected result: 0 rows for each query.
-- =====================================================

-- Sales
SELECT
    sale_id,
    COUNT(*) AS duplicate_count
FROM sales
GROUP BY sale_id
HAVING COUNT(*) > 1;

-- Inventory
SELECT
    product_id,
    date,
    warehouse_id,
    COUNT(*) AS duplicate_count
FROM inventory
GROUP BY product_id,
        date,
        warehouse_id
HAVING COUNT(*) > 1;

-- =====================================================
-- CHECK 3: NULL VALUE CHECK
-- Check critical product fields for missing values.
-- Expected result: 0 NULL values across all fields.
-- Result: No NULL values found.
-- =====================================================

SELECT
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS missing_product_id,
    SUM(CASE WHEN product_name IS NULL THEN 1 ELSE 0 END) AS missing_product_name,
    SUM(CASE WHEN category_id IS NULL THEN 1 ELSE 0 END) AS missing_category_id,
    SUM(CASE WHEN unit_cost IS NULL THEN 1 ELSE 0 END) AS missing_unit_cost,
    SUM(CASE WHEN selling_price IS NULL THEN 1 ELSE 0 END) AS missing_selling_price,
    SUM(CASE WHEN holding_cost_per_unit IS NULL THEN 1 ELSE 0 END) AS missing_holding_cost,
    SUM(CASE WHEN moq IS NULL THEN 1 ELSE 0 END) AS missing_moq
FROM products;

-- =====================================================
-- CHECK 4: REFERENTIAL INTEGRITY
-- Check for sales records referencing products that
-- do not exist in the product master table.
-- Expected result: 0 invalid references.
-- Result: 0 invalid product references found.
-- =====================================================

SELECT
    COUNT(*) AS invalid_product_references
FROM sales s
LEFT JOIN products p
    ON s.product_id = p.product_id
WHERE p.product_id IS NULL;

-- For suppliers as well 
SELECT
    COUNT(*) AS invalid_supplier_references
FROM purchases p
LEFT JOIN suppliers s
    ON s.supplier_id = p.supplier_id
WHERE s.supplier_id IS NULL;

-- =====================================================
-- CHECK 5: INVALID NUMERIC VALUES
-- Check product fields for logically invalid values.
-- Expected result: 0 invalid records.
-- Result: 0 invalid product values found.
-- =====================================================
SELECT
    COUNT(*) AS invalid_product_values
FROM products
WHERE
    unit_cost <= 0
    OR selling_price <= 0
    OR holding_cost_per_unit < 0
    OR moq <= 0;

    -- =====================================================
-- CHECK 6: INVENTORY RECONCILIATION
-- Validate that closing stock reconciles with inventory
-- movements for every product-warehouse-date record.
-- Expected result: 0 reconciliation errors.
-- Result: 0 inventory reconciliation errors found.
-- =====================================================

SELECT
    COUNT(*) AS inventory_reconciliation_errors
FROM inventory
WHERE closing_stock <> opening_stock + received_quantity - sold_quantity;

-- =====================================================
-- CHECK 7: STOCKOUT RECONCILIATION
-- Validate that stockout quantity equals the difference
-- between customer demand and fulfilled sales.
-- Expected result: 0 reconciliation errors.
-- Result: 0 stockout reconciliation errors found.
-- =====================================================

SELECT
    COUNT(*) AS stockout_reconciliation_errors
FROM inventory
WHERE stockout_quantity <> demand_quantity - sold_quantity;

-- =====================================================
-- CHECK 8: PURCHASE DATE CONSISTENCY
-- Validate that expected and actual delivery dates
-- do not occur before the purchase date.
-- Expected result: 0 invalid purchase dates.
-- Result: 0 invalid purchase dates found.
-- =====================================================

SELECT
    COUNT(*) AS invalid_purchase_dates
FROM purchases
WHERE actual_delivery_date < purchase_date
   OR expected_delivery_date < purchase_date;

-- =====================================================
-- CHECK 9: PRODUCT-SUPPLIER RELATIONSHIP
-- Validate that every product-supplier combination used
-- in purchases exists in the product_suppliers table.
-- Expected result: 0 invalid relationships.
-- Result: 0 invalid product-supplier pairs found.
-- =====================================================

SELECT
    COUNT(*) AS invalid_product_supplier_pairs
FROM purchases p
LEFT JOIN product_suppliers ps
    ON p.supplier_id = ps.supplier_id
    AND p.product_id = ps.product_id
WHERE ps.product_id IS NULL;

-- =====================================================
-- CHECK 10. PRIMARY SUPPLIER VALIDATION
-- Verify that every product has exactly one primary
-- supplier assigned.
-- =====================================================

SELECT
    product_id,
    SUM(is_primary_supplier) AS primary_supplier_count
FROM product_suppliers
GROUP BY product_id
HAVING SUM(is_primary_supplier) <> 1;

-- Expected result: 0 rows
