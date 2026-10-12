USE northstar_supply_chain;

-- =====================================================
-- 07. ANALYTICAL VIEWS
-- =====================================================
-- Purpose:
-- Create reusable, analysis-ready SQL views for Tableau
-- and downstream analytics.
--
-- These views transform validated operational tables into
-- business-level datasets at appropriate analytical grains.
--
-- Views created:
--   1. vw_monthly_performance
--   2. vw_warehouse_performance
--   3. vw_supplier_performance
--   4. vw_product_profitability
--   5. vw_product_inventory_review
-- =====================================================


-- =====================================================
-- 1. MONTHLY PERFORMANCE VIEW
-- =====================================================
-- Grain:
-- One row per year/month.
--
-- Supports:
-- Demand trends, fulfilled sales, stockouts,
-- fulfillment rate, and stockout rate.
-- =====================================================

CREATE OR REPLACE VIEW vw_monthly_performance AS

SELECT
    d.year,
    d.month,

    MIN(i.date) AS month_start_date,

    SUM(i.demand_quantity) AS total_demand,
    SUM(i.sold_quantity) AS total_units_sold,
    SUM(i.stockout_quantity) AS total_stockout_units,

    ROUND(
        100.0 * SUM(i.sold_quantity)
        / NULLIF(SUM(i.demand_quantity), 0),
        2
    ) AS fulfillment_rate_pct,

    ROUND(
        100.0 * SUM(i.stockout_quantity)
        / NULLIF(SUM(i.demand_quantity), 0),
        2
    ) AS stockout_rate_pct

FROM inventory i

JOIN date_dim d
    ON i.date = d.date

GROUP BY
    d.year,
    d.month;


-- =====================================================
-- 2. WAREHOUSE PERFORMANCE VIEW
-- =====================================================
-- Grain:
-- One row per warehouse.
--
-- Supports:
-- Warehouse demand, fulfilled sales, stockouts,
-- fulfillment rate, and stockout-rate comparisons.
-- =====================================================

CREATE OR REPLACE VIEW vw_warehouse_performance AS

SELECT
    w.warehouse_id,
    w.warehouse_name,

    SUM(i.demand_quantity) AS total_demand,
    SUM(i.sold_quantity) AS total_units_sold,
    SUM(i.stockout_quantity) AS total_stockout_units,

    ROUND(
        100.0 * SUM(i.sold_quantity)
        / NULLIF(SUM(i.demand_quantity), 0),
        2
    ) AS fulfillment_rate_pct,

    ROUND(
        100.0 * SUM(i.stockout_quantity)
        / NULLIF(SUM(i.demand_quantity), 0),
        2
    ) AS stockout_rate_pct

FROM warehouses w

JOIN inventory i
    ON w.warehouse_id = i.warehouse_id

GROUP BY
    w.warehouse_id,
    w.warehouse_name;


-- =====================================================
-- 3. SUPPLIER PERFORMANCE VIEW
-- =====================================================

CREATE OR REPLACE VIEW vw_supplier_performance AS

WITH purchase_metrics AS (
    SELECT
        s.supplier_id,
        s.supplier_name,
        s.supplier_location,
        s.standard_lead_time_days,

        COUNT(p.purchase_id) AS total_purchase_orders,
        SUM(p.quantity) AS total_units_purchased,

        SUM(p.quantity * p.unit_cost)
            AS total_purchase_spend,

        SUM(
            CASE
                WHEN p.actual_delivery_date <= p.expected_delivery_date
                THEN 1
                ELSE 0
            END
        ) AS on_time_deliveries,

        SUM(
            CASE
                WHEN p.actual_delivery_date > p.expected_delivery_date
                THEN 1
                ELSE 0
            END
        ) AS late_deliveries,

        100.0 *
        SUM(
            CASE
                WHEN p.actual_delivery_date <= p.expected_delivery_date
                THEN 1
                ELSE 0
            END
        )
        / NULLIF(COUNT(p.purchase_id), 0)
            AS on_time_delivery_pct,

        AVG(
            DATEDIFF(
                p.actual_delivery_date,
                p.purchase_date
            )
        ) AS avg_actual_lead_time_days,

        AVG(
            CASE
                WHEN p.actual_delivery_date > p.expected_delivery_date
                THEN DATEDIFF(
                    p.actual_delivery_date,
                    p.expected_delivery_date
                )
            END
        ) AS avg_late_delivery_days

    FROM suppliers s

    JOIN purchases p
        ON s.supplier_id = p.supplier_id

    GROUP BY
        s.supplier_id,
        s.supplier_name,
        s.supplier_location,
        s.standard_lead_time_days
),

product_supplier_count AS (
    SELECT
        product_id,
        COUNT(*) AS supplier_count

    FROM product_suppliers

    GROUP BY product_id
),

dependency_metrics AS (
    SELECT
        ps.supplier_id,

        COUNT(DISTINCT ps.product_id)
            AS total_products_supplied,

        COUNT(
            DISTINCT CASE
                WHEN ps.is_primary_supplier = TRUE
                THEN ps.product_id
            END
        ) AS primary_products,

        COUNT(
            DISTINCT CASE
                WHEN psc.supplier_count = 1
                THEN ps.product_id
            END
        ) AS sole_source_products

    FROM product_suppliers ps

    JOIN product_supplier_count psc
        ON ps.product_id = psc.product_id

    GROUP BY ps.supplier_id
)

SELECT
    pm.supplier_id,
    pm.supplier_name,
    pm.supplier_location,
    pm.standard_lead_time_days,

    pm.total_purchase_orders,
    pm.total_units_purchased,

    ROUND(
        pm.total_purchase_spend,
        2
    ) AS total_purchase_spend,

    pm.on_time_deliveries,
    pm.late_deliveries,

    ROUND(
        pm.on_time_delivery_pct,
        2
    ) AS on_time_delivery_pct,

    ROUND(
        pm.avg_actual_lead_time_days,
        2
    ) AS avg_actual_lead_time_days,

    ROUND(
        pm.avg_late_delivery_days,
        2
    ) AS avg_late_delivery_days,

    dm.total_products_supplied,
    dm.primary_products,
    dm.sole_source_products

FROM purchase_metrics pm

LEFT JOIN dependency_metrics dm
    ON pm.supplier_id = dm.supplier_id;

-- =====================================================
-- 4. PRODUCT PROFITABILITY VIEW
-- =====================================================
-- Grain:
-- One row per product.
--
-- Supports:
-- Product sales volume, estimated revenue, estimated
-- gross profit, gross margin, and category analysis.
--
-- Financial metrics use fulfilled units and standard
-- product unit cost. They are analytical estimates,
-- not accounting profitability.
-- =====================================================

CREATE OR REPLACE VIEW vw_product_profitability AS

SELECT
    p.product_id,
    p.product_name,

    c.category_id,
    c.category_name,

    p.unit_cost,
    p.selling_price,

    ROUND(
        p.selling_price - p.unit_cost,
        2
    ) AS gross_profit_per_unit,

    ROUND(
        100.0 *
        (p.selling_price - p.unit_cost)
        / NULLIF(p.selling_price, 0),
        2
    ) AS gross_margin_pct,

    SUM(i.sold_quantity)
        AS total_units_sold,

    ROUND(
        SUM(i.sold_quantity) * p.selling_price,
        2
    ) AS estimated_revenue,

    ROUND(
        SUM(i.sold_quantity) * p.unit_cost,
        2
    ) AS estimated_cogs,

    ROUND(
        SUM(i.sold_quantity)
        * (p.selling_price - p.unit_cost),
        2
    ) AS estimated_gross_profit

FROM products p

JOIN categories c
    ON p.category_id = c.category_id

JOIN inventory i
    ON p.product_id = i.product_id

GROUP BY
    p.product_id,
    p.product_name,
    c.category_id,
    c.category_name,
    p.unit_cost,
    p.selling_price;


-- =====================================================
-- 5. PRODUCT INVENTORY REVIEW VIEW
-- =====================================================
-- Grain:
-- One row per product.
--
-- Supports:
-- Current inventory position, recent demand, historical
-- stockouts, supplier lead time, inventory value, holding
-- cost exposure, MOQ constraints, and excess/replenishment
-- prioritization.
--
-- Quartiles are relative analytical screening measures,
-- not formal Northstar inventory policies.
-- =====================================================

CREATE OR REPLACE VIEW vw_product_inventory_review AS

WITH ending_inventory AS (
    SELECT
        product_id,
        SUM(closing_stock) AS ending_stock

    FROM inventory

    WHERE date = (
        SELECT MAX(date)
        FROM inventory
    )

    GROUP BY product_id
),

recent_daily_demand AS (
    SELECT
        date,
        product_id,
        SUM(demand_quantity) AS daily_demand

    FROM inventory

    WHERE date > DATE_SUB(
        (SELECT MAX(date) FROM inventory),
        INTERVAL 30 DAY
    )

    GROUP BY
        date,
        product_id
),

recent_demand AS (
    SELECT
        product_id,
        AVG(daily_demand) AS avg_30d_daily_demand

    FROM recent_daily_demand

    GROUP BY product_id
),

primary_supplier AS (
    SELECT
        ps.product_id,
        ps.supplier_id,
        s.supplier_name,
        s.standard_lead_time_days

    FROM product_suppliers ps

    JOIN suppliers s
        ON ps.supplier_id = s.supplier_id

    WHERE ps.is_primary_supplier = TRUE
),

product_stockout AS (
    SELECT
        product_id,

        SUM(demand_quantity) AS total_demand,
        SUM(sold_quantity) AS total_units_sold,
        SUM(stockout_quantity) AS total_stockout_units,

        100.0 * SUM(stockout_quantity)
        / NULLIF(SUM(demand_quantity), 0)
            AS historical_stockout_rate_pct

    FROM inventory

    GROUP BY product_id
),

stockout_ranked AS (
    SELECT
        *,

        NTILE(4) OVER (
            ORDER BY historical_stockout_rate_pct
        ) AS stockout_quartile

    FROM product_stockout

    WHERE total_demand > 0
),

product_metrics AS (
    SELECT
        p.product_id,
        p.product_name,
        p.category_id,

        p.unit_cost,
        p.selling_price,
        p.holding_cost_per_unit,
        p.moq,

        ei.ending_stock,

        rd.avg_30d_daily_demand,

        ps.supplier_id,
        ps.supplier_name,
        ps.standard_lead_time_days,

        sr.total_demand,
        sr.total_units_sold,
        sr.total_stockout_units,
        sr.historical_stockout_rate_pct,
        sr.stockout_quartile,

        ei.ending_stock
        / NULLIF(rd.avg_30d_daily_demand, 0)
            AS recent_inventory_days,

        (
            ei.ending_stock
            / NULLIF(rd.avg_30d_daily_demand, 0)
        )
        / NULLIF(ps.standard_lead_time_days, 0)
            AS coverage_to_lead_time_ratio,

        p.moq
        / NULLIF(rd.avg_30d_daily_demand, 0)
            AS moq_demand_days,

        ei.ending_stock * p.unit_cost
            AS ending_inventory_value,

        ei.ending_stock * p.holding_cost_per_unit
            AS ending_holding_cost

    FROM products p

    JOIN ending_inventory ei
        ON p.product_id = ei.product_id

    JOIN recent_demand rd
        ON p.product_id = rd.product_id

    JOIN primary_supplier ps
        ON p.product_id = ps.product_id

    JOIN stockout_ranked sr
        ON p.product_id = sr.product_id
),

coverage_ranked AS (
    SELECT
        product_id,

        NTILE(4) OVER (
            ORDER BY coverage_to_lead_time_ratio
        ) AS coverage_quartile

    FROM product_metrics

    WHERE avg_30d_daily_demand > 0
),

final_metrics AS (
    SELECT
        pm.*,
        cr.coverage_quartile

    FROM product_metrics pm

    LEFT JOIN coverage_ranked cr
        ON pm.product_id = cr.product_id
)

SELECT
    fm.product_id,
    fm.product_name,

    c.category_name,

    fm.ending_stock,

    ROUND(
        fm.avg_30d_daily_demand,
        2
    ) AS avg_30d_daily_demand,

    ROUND(
        fm.recent_inventory_days,
        2
    ) AS recent_inventory_days,

    fm.supplier_id,
    fm.supplier_name,
    fm.standard_lead_time_days,

    ROUND(
        fm.coverage_to_lead_time_ratio,
        2
    ) AS coverage_to_lead_time_ratio,

    fm.coverage_quartile,

    ROUND(
        fm.historical_stockout_rate_pct,
        2
    ) AS historical_stockout_rate_pct,

    fm.stockout_quartile,

    fm.moq,

    ROUND(
        fm.moq_demand_days,
        2
    ) AS moq_demand_days,

    ROUND(
        fm.ending_inventory_value,
        2
    ) AS ending_inventory_value,

    ROUND(
        fm.ending_holding_cost,
        2
    ) AS ending_holding_cost,

    CASE
        WHEN fm.avg_30d_daily_demand = 0
             AND fm.ending_stock > 0
        THEN 'Zero-Demand Review'

        WHEN fm.coverage_to_lead_time_ratio < 1
             AND fm.stockout_quartile = 4
        THEN 'High Replenishment Review'

        WHEN fm.coverage_to_lead_time_ratio < 1
        THEN 'Replenishment Review'

        WHEN fm.coverage_quartile = 4
             AND fm.stockout_quartile = 4
        THEN 'High Excess + Historical Stockout Review'

        WHEN fm.coverage_quartile = 4
        THEN 'High Excess Review'

        WHEN fm.coverage_quartile = 3
        THEN 'Elevated Excess Review'

        ELSE 'Lower Relative Priority'

    END AS review_category

FROM final_metrics fm

JOIN categories c
    ON fm.category_id = c.category_id;
