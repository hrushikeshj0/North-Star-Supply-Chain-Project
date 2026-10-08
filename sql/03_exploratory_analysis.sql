/*
=========================================================
NORTHSTAR SUPPLY CHAIN INTELLIGENCE
03 - EXPLORATORY ANALYSIS
=========================================================

Purpose:
Explore sales, demand, inventory, purchasing, and supplier
activity to understand overall business performance and
identify patterns requiring deeper analysis.
=========================================================
*/

USE northstar_supply_chain;

-- =====================================================
-- 1. OVERALL DEMAND AND SALES SUMMARY
-- Establish overall demand, fulfilled sales, and
-- stockout performance across the analysis period.
-- =====================================================

SELECT
    SUM(demand_quantity) AS total_demand,
    SUM(sold_quantity) AS total_units_sold,
    SUM(stockout_quantity) AS total_stockout_units,
    ROUND(
        100.0 * SUM(sold_quantity) / SUM(demand_quantity),
        2
    ) AS fulfillment_rate_pct,
    ROUND(
        100.0 * SUM(stockout_quantity) / SUM(demand_quantity),
        2
    ) AS stockout_rate_pct
FROM inventory;

-- Result:
-- Total Demand: 986,213 units
-- Units Sold: 757,362 units
-- Stockout Units: 228,851 units
-- Fulfillment Rate: 76.79%
-- Stockout Rate: 23.21%

-- =====================================================
-- 2. WAREHOUSE FULFILLMENT PERFORMANCE
-- Compare demand fulfillment and stockout rates across
-- Northstar distribution centers.
-- =====================================================

SELECT w.warehouse_name,
    SUM(i.demand_quantity) AS total_demand,
    SUM(i.sold_quantity) AS total_units_sold,
    SUM(i.stockout_quantity) AS total_stockout_units,
    ROUND(
        100.0 * SUM(i.sold_quantity) / SUM(i.demand_quantity),
        2
    ) AS fulfillment_rate_pct,
    ROUND(
        100.0 * SUM(i.stockout_quantity) / SUM(i.demand_quantity),
        2
    ) AS stockout_rate_pct
FROM inventory i
JOIN warehouses w
    ON i.warehouse_id=w.warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name
ORDER BY stockout_rate_pct DESC;

-- Key observation:
-- San Francisco had the highest stockout rate (26.03%)
-- despite having the lowest total demand.
-- Los Angeles had the lowest stockout rate (20.48%)
-- despite having the highest total demand.
-- Further analysis is required to determine the drivers.

-- =====================================================
-- 3. MONTHLY DEMAND AND STOCKOUT TREND
-- Analyze monthly demand, fulfilled sales, and stockout
-- performance to identify changes over time.
-- =====================================================

SELECT
    d.year,
    d.month,
    SUM(i.demand_quantity) AS total_demand,
    SUM(i.sold_quantity) AS total_units_sold,
    SUM(i.stockout_quantity) AS total_stockout_units,
    ROUND(
        100.0 * SUM(i.sold_quantity) / SUM(i.demand_quantity),
        2
    ) AS fulfillment_rate_pct,
    ROUND(
        100.0 * SUM(i.stockout_quantity) / SUM(i.demand_quantity),
        2
    ) AS stockout_rate_pct
FROM inventory i
JOIN date_dim d
    ON i.date = d.date
GROUP BY
    d.year,
    d.month,
    MONTH(i.date)
ORDER BY
    d.year,
    MONTH(i.date);

-- Key observation:
-- Stockout rate peaked at 56.62% in February 2025 and
-- declined progressively through the remainder of the year.
-- December had the highest monthly demand (90,074 units)
-- while maintaining a relatively low 11.96% stockout rate.
--
-- Note:
-- Because the dataset is synthetic, the early stockout
-- spike may partly reflect starting inventory and
-- replenishment timing in the simulation.

-- =====================================================
-- 4. PRODUCT-LEVEL STOCKOUT PERFORMANCE
-- Identify products experiencing the highest stockout
-- rates and quantify their unmet customer demand.
-- =====================================================

SELECT
    p.product_id,
    p.product_name,
    SUM(i.demand_quantity) AS total_demand,
    SUM(i.sold_quantity) AS total_units_sold,
    SUM(i.stockout_quantity) AS total_stockout_units,
    ROUND(
        100.0 * SUM(i.sold_quantity) / SUM(i.demand_quantity),
        2
    ) AS fulfillment_rate_pct,
    ROUND(
        100.0 * SUM(i.stockout_quantity) / SUM(i.demand_quantity),
        2
    ) AS stockout_rate_pct
FROM inventory i
JOIN products p
    ON i.product_id = p.product_id
GROUP BY
    p.product_id,
    p.product_name
ORDER BY stockout_rate_pct DESC
LIMIT 10;

-- Key observation:
-- P104 recorded the highest stockout rate at 41.70%.
-- However, products such as P102 and P093 generated
-- substantially more unmet units despite lower stockout
-- rates, showing that both stockout severity and absolute
-- business impact should be considered.

-- =====================================================
-- 5. SLOW-MOVING PRODUCTS
-- Identify products with the lowest fulfilled sales
-- volume during the analysis period.
-- =====================================================

SELECT
    p.product_id,
    p.product_name,
    SUM(i.sold_quantity) AS total_units_sold
FROM products p
JOIN inventory i
    ON p.product_id = i.product_id
GROUP BY
    p.product_id,
    p.product_name
ORDER BY total_units_sold ASC
LIMIT 10;

-- Key observation:
-- P072 recorded only 14 fulfilled units during the
-- analysis period, followed by P111 with 153 units.
-- Low sales volume alone does not confirm excess
-- inventory; current stock levels must also be considered.