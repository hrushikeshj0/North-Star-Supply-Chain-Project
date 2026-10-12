/*
=========================================================
NORTHSTAR SUPPLY CHAIN INTELLIGENCE
04 - INVENTORY ANALYSIS
=========================================================

Purpose:
Evaluate product inventory health by combining demand,
sales, stockout, and inventory levels to identify
understocked, overstocked, and slow-moving products.

Analysis includes:
- Ending inventory
- Average daily demand
- Inventory days
- Inventory value
- Holding cost exposure
- Stockout performance
- Inventory health classification
=========================================================
*/

USE northstar_supply_chain;

-- =====================================================
-- 1. INVENTORY DAYS BY PRODUCT
-- Compare ending inventory with average daily demand to
-- estimate how many days of demand the current inventory
-- could support.
--
-- Method:
-- 1. Calculate ending inventory using the latest available
--    inventory date.
-- 2. Aggregate warehouse-level demand to daily product demand.
-- 3. Calculate average daily demand for each product.
-- 4. Divide ending stock by average daily demand to estimate
--    inventory days.
-- =====================================================

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

daily_product_demand AS (
    SELECT
        date,
        product_id,
        SUM(demand_quantity) AS daily_demand
    FROM inventory
    GROUP BY date, product_id
),

product_demand_summary AS (
    SELECT
        product_id,
        ROUND(AVG(daily_demand), 2) AS avg_daily_demand
    FROM daily_product_demand
    GROUP BY product_id
)

SELECT
    p.product_id,
    p.product_name,
    ei.ending_stock,
    pds.avg_daily_demand,
    ROUND(
        ei.ending_stock / NULLIF(pds.avg_daily_demand, 0),
        2
    ) AS inventory_days
FROM ending_inventory ei
JOIN product_demand_summary pds
    ON ei.product_id = pds.product_id
JOIN products p
    ON p.product_id = pds.product_id
ORDER BY inventory_days DESC
LIMIT 10;

-- Key observation:
-- Several products hold inventory far beyond their demand
-- requirements. P072 is the most extreme case, with 3,220
-- units of ending inventory against average daily demand of
-- only 0.04 units.
--
-- P074, P111, P101, and P040 also have more than 1,000 days
-- of inventory coverage, indicating potential excess
-- inventory exposure.
--
-- Note:
-- Inventory days becomes extremely large when average daily
-- demand approaches zero. These cases should be interpreted
-- as near-zero-demand/excess-inventory candidates rather
-- than treating the calculated number of days literally.

-- =====================================================
-- 2. RECENT 30-DAY DEMAND
-- Calculate average daily demand using the most recent
-- 30-day period to better represent current demand patterns.
-- =====================================================

WITH recent_daily_demand AS (
    SELECT
        date,
        product_id,
        SUM(demand_quantity) AS daily_demand
    FROM inventory
    WHERE date > DATE_SUB(
        (SELECT MAX(date) FROM inventory),
        INTERVAL 30 DAY
    )
    GROUP BY date, product_id
)

SELECT
    product_id,
    ROUND(AVG(daily_demand), 2) AS avg_30d_daily_demand
FROM recent_daily_demand
GROUP BY product_id
ORDER BY avg_30d_daily_demand DESC
LIMIT 10;

-- Key observation:
-- Recent 30-day demand differs from the full-period
-- historical average for several high-demand products.
-- For example, P013 declined from an historical average
-- of 60.16 units/day to 52.63 units/day in the most
-- recent 30-day period.
--
-- Recent demand will therefore be used alongside ending
-- inventory to provide a more current measure of
-- inventory coverage.

-- =====================================================
-- 3. RECENT INVENTORY COVERAGE
-- Compare current ending inventory with recent 30-day
-- average daily demand to estimate current days of
-- inventory coverage.
-- =====================================================
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
    GROUP BY date, product_id
),
recent_demand_summary AS (
    SELECT
        product_id,
        ROUND(AVG(daily_demand), 2) AS avg_30d_daily_demand
    FROM recent_daily_demand
    GROUP BY product_id
)
SELECT
    p.product_id,
    p.product_name,
    ei.ending_stock,
    rds.avg_30d_daily_demand,
    ROUND(
        ei.ending_stock /
        NULLIF(rds.avg_30d_daily_demand, 0),
        2
    ) AS recent_inventory_days
FROM ending_inventory ei
JOIN recent_demand_summary rds
    ON ei.product_id = rds.product_id
JOIN products p
    ON ei.product_id = p.product_id
ORDER BY recent_inventory_days DESC
LIMIT 10;

-- Key observation:
-- Recent-demand inventory coverage reveals substantial
-- excess inventory exposure among several slow-moving
-- products.
--
-- P074 and P111 each hold more than 3,000 days of
-- inventory based on their recent 30-day demand rates.
-- P101, P040, and P037 also hold more than 1,000 days
-- of recent demand coverage.
--
-- For several products, recent inventory coverage is
-- higher than historical coverage because recent demand
-- has declined, increasing the risk of excess inventory.
--
-- Note:
-- Products with zero recent demand require separate
-- treatment because inventory-days ratios are undefined
-- when average daily demand equals zero.

-- =====================================================
-- 4. PRIMARY SUPPLIER LEAD TIME
-- Identify each product's primary supplier and standard
-- replenishment lead time.
--
-- Purpose:
-- Supplier lead time provides context for inventory
-- coverage. Products with longer replenishment times may
-- require greater inventory buffers than products that
-- can be replenished quickly.
-- =====================================================

SELECT
    p.product_id,
    p.product_name,
    s.supplier_name,
    s.standard_lead_time_days
FROM products p
JOIN product_suppliers ps
    ON p.product_id = ps.product_id
JOIN suppliers s
    ON s.supplier_id = ps.supplier_id
WHERE ps.is_primary_supplier = TRUE
ORDER BY p.product_id;

-- =====================================================
-- 5. ZERO RECENT DEMAND INVENTORY ANALYSIS
-- =====================================================
-- Purpose:
-- Identify products that still hold inventory despite
-- recording no demand during the most recent 30-day period.
--
-- Business rationale:
-- Inventory-days calculations become undefined when recent
-- demand is zero because inventory cannot be divided by
-- zero demand. These products therefore require separate
-- analysis rather than being included in the standard
-- inventory-coverage calculation.
--
-- Products with zero recent demand and positive ending
-- inventory may represent potential:
-- - Dead stock
-- - Excess inventory
-- - Slow-moving inventory
-- - Unnecessary working-capital exposure
--
-- Inventory value is also calculated to determine the
-- amount of capital currently tied up in these products.
--
-- Formula:
-- Ending Inventory Value = Ending Stock * Unit Cost
-- =====================================================

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
    GROUP BY date, product_id
),

recent_demand_summary AS (
    SELECT
        product_id,
        ROUND(AVG(daily_demand), 2) AS avg_30d_daily_demand
    FROM recent_daily_demand
    GROUP BY product_id
)

SELECT
    p.product_id,
    p.product_name,
    ei.ending_stock,
    rds.avg_30d_daily_demand,
    p.unit_cost,
    ROUND(
        ei.ending_stock * p.unit_cost,
        2
    ) AS ending_inventory_value
FROM products p
JOIN ending_inventory ei
    ON p.product_id = ei.product_id
JOIN recent_demand_summary rds
    ON p.product_id = rds.product_id
WHERE rds.avg_30d_daily_demand = 0
    AND ei.ending_stock > 0
ORDER BY ending_inventory_value DESC;

-- Key observation:
-- P072 was the only product with zero average daily demand
-- during the most recent 30-day period while still holding
-- inventory.
--
-- P072:
-- Ending inventory: 3,220 units
-- Average 30-day daily demand: 0.00 units
-- Unit cost: $148.23
-- Ending inventory value: $477,300.60
--
-- Interpretation:
-- P072 represents a significant potential excess or
-- dead-stock exposure because approximately $477K of
-- inventory value remains on hand despite no recent demand.
--
-- However, zero recent demand alone is not sufficient to
-- recommend immediate inventory disposal. Additional
-- investigation should consider factors such as seasonality,
-- expected future demand, contractual requirements,
-- outstanding customer commitments, and purchasing plans
-- before corrective action is taken.

-- =====================================================
-- 6. CURRENT INVENTORY VALUE AND HOLDING-COST EXPOSURE
-- =====================================================
-- Purpose:
-- Measure the financial value of current inventory and
-- identify products creating the greatest holding-cost
-- exposure.
--
-- Business rationale:
-- Inventory quantity alone does not indicate financial
-- impact. A product with fewer units may represent greater
-- working-capital exposure if its unit cost is high.
--
-- Similarly, products with large inventory positions and
-- high holding costs may create significant carrying-cost
-- exposure even when the inventory supports active demand.
--
-- Formulas:
--
-- Ending Inventory Value =
-- Ending Stock * Unit Cost
--
-- Ending Holding Cost =
-- Ending Stock * Holding Cost Per Unit
--
-- Key observations:
-- P081 had the highest ending inventory value at
-- approximately $3.97M.
--
-- P013 had the highest current holding-cost exposure at
-- approximately $181.9K.
--
-- High inventory value or holding cost does not by itself
-- indicate excess inventory. These measures must be
-- evaluated alongside demand, inventory coverage, supplier
-- lead time, and stockout performance.
-- =====================================================


-- 6A. PRODUCTS WITH HIGHEST CURRENT INVENTORY VALUE

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
)

SELECT
    p.product_id,
    p.product_name,
    ei.ending_stock,
    p.unit_cost,
    ROUND(
        ei.ending_stock * p.unit_cost,
        2
    ) AS ending_inventory_value
FROM products p
JOIN ending_inventory ei
    ON p.product_id = ei.product_id
ORDER BY ending_inventory_value DESC
LIMIT 10;


-- 6B. PRODUCTS WITH HIGHEST HOLDING-COST EXPOSURE

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
)

SELECT
    p.product_id,
    p.product_name,
    ei.ending_stock,
    p.unit_cost,
    p.holding_cost_per_unit,
    ROUND(
        ei.ending_stock * p.unit_cost,
        2
    ) AS ending_inventory_value,
    ROUND(
        ei.ending_stock * p.holding_cost_per_unit,
        2
    ) AS ending_holding_cost
FROM products p
JOIN ending_inventory ei
    ON p.product_id = ei.product_id
ORDER BY ending_holding_cost DESC
LIMIT 10;

-- =====================================================
-- 7. CONSOLIDATED PRODUCT INVENTORY ANALYSIS
-- =====================================================
-- Purpose:
-- Combine current inventory, recent demand, financial
-- exposure, supplier lead time, and MOQ into a single
-- product-level analytical dataset.
--
-- This dataset will support later inventory-health
-- classification and replenishment recommendations.
--
-- Important:
-- No inventory-health thresholds are applied here.
-- This step creates the evidence required for subsequent
-- business analysis.
-- =====================================================


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

recent_demand_summary AS (
    SELECT
        product_id,
        ROUND(AVG(daily_demand), 2) AS avg_30d_daily_demand
    FROM recent_daily_demand
    GROUP BY product_id
),

primary_supplier AS (
    SELECT
        ps.product_id,
        s.supplier_id,
        s.supplier_name,
        s.standard_lead_time_days
    FROM product_suppliers ps
    JOIN suppliers s
        ON ps.supplier_id = s.supplier_id
    WHERE ps.is_primary_supplier = TRUE
)

SELECT
    p.product_id,
    p.product_name,

    -- Current inventory
    ei.ending_stock,

    -- Product economics
    p.unit_cost,
    p.holding_cost_per_unit,
    p.moq,

    -- Financial exposure
    ROUND(
        ei.ending_stock * p.unit_cost,
        2
    ) AS ending_inventory_value,

    ROUND(
        ei.ending_stock * p.holding_cost_per_unit,
        2
    ) AS ending_holding_cost,

    -- Recent demand
    rds.avg_30d_daily_demand,

    -- Current inventory coverage
    ROUND(
        ei.ending_stock /
        NULLIF(rds.avg_30d_daily_demand, 0),
        2
    ) AS recent_inventory_days,

    -- Primary supplier
    ps.supplier_id,
    ps.supplier_name,
    ps.standard_lead_time_days,

    -- Inventory coverage relative to replenishment time
    ROUND(
        (
            ei.ending_stock /
            NULLIF(rds.avg_30d_daily_demand, 0)
        )
        /
        NULLIF(ps.standard_lead_time_days, 0),
        2
    ) AS coverage_to_lead_time_ratio,

    -- Approximate demand coverage created by one MOQ
    ROUND(
        p.moq /
        NULLIF(rds.avg_30d_daily_demand, 0),
        2
    ) AS moq_demand_days

FROM products p

JOIN ending_inventory ei
    ON p.product_id = ei.product_id

JOIN recent_demand_summary rds
    ON p.product_id = rds.product_id

JOIN primary_supplier ps
    ON p.product_id = ps.product_id

ORDER BY p.product_id;

-- =====================================================
-- 8. RELATIVE EXCESS INVENTORY PRIORITIZATION
-- =====================================================
-- Purpose:
-- Prioritize products for excess-inventory investigation
-- using inventory coverage relative to supplier lead time.
--
-- Analytical approach:
-- Initial testing showed that nearly all active-demand
-- products held more than five times their supplier
-- lead-time coverage. Therefore, a fixed 5x threshold
-- provided little value for prioritization.
--
-- Because Northstar does not have a defined inventory
-- coverage policy in this business case, active-demand
-- products are ranked relative to the portfolio using
-- coverage quartiles.
--
-- Classification:
--
-- Zero recent demand + positive inventory
--     -> Zero-Demand Review
--
-- Coverage below supplier lead time
--     -> Replenishment Risk
--
-- Quartile 4
--     -> High Excess Review Priority
--
-- Quartile 3
--     -> Elevated Excess Review Priority
--
-- Quartiles 1 and 2
--     -> Lower Relative Excess Priority
--
-- Important:
-- These classifications represent analytical review
-- priorities rather than formal company inventory-policy
-- thresholds.
-- =====================================================


WITH ending_inventory AS (
    SELECT
        product_id,
        SUM(closing_stock) AS ending_stock
    FROM inventory
    WHERE date = (SELECT MAX(date) FROM inventory)
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

recent_demand_summary AS (
    SELECT
        product_id,
        AVG(daily_demand) AS avg_30d_daily_demand
    FROM recent_daily_demand
    GROUP BY product_id
),

product_coverage AS (
    SELECT
        p.product_id,
        ei.ending_stock,
        rds.avg_30d_daily_demand,
        s.standard_lead_time_days,

        (
            ei.ending_stock /
            NULLIF(rds.avg_30d_daily_demand, 0)
        ) /
        NULLIF(s.standard_lead_time_days, 0)
            AS coverage_to_lead_time_ratio

    FROM products p

    JOIN ending_inventory ei
        ON p.product_id = ei.product_id

    JOIN recent_demand_summary rds
        ON p.product_id = rds.product_id

    JOIN product_suppliers ps
        ON p.product_id = ps.product_id
        AND ps.is_primary_supplier = TRUE

    JOIN suppliers s
        ON ps.supplier_id = s.supplier_id
),

active_demand_ranked AS (
    SELECT
        product_id,
        coverage_to_lead_time_ratio,

        NTILE(4) OVER (
            ORDER BY coverage_to_lead_time_ratio
        ) AS coverage_quartile

    FROM product_coverage
    WHERE avg_30d_daily_demand > 0
)

SELECT
    pc.product_id,
    p.product_name,
    pc.ending_stock,

    ROUND(
        pc.avg_30d_daily_demand,
        2
    ) AS avg_30d_daily_demand,

    pc.standard_lead_time_days,

    ROUND(
        pc.coverage_to_lead_time_ratio,
        2
    ) AS coverage_to_lead_time_ratio,

    adr.coverage_quartile,

    ROUND(
        pc.ending_stock * p.unit_cost,
        2
    ) AS ending_inventory_value,

    CASE
        WHEN pc.avg_30d_daily_demand = 0
             AND pc.ending_stock > 0
            THEN 'Zero-Demand Review'

        WHEN pc.coverage_to_lead_time_ratio < 1
            THEN 'Replenishment Risk'

        WHEN adr.coverage_quartile = 4
            THEN 'High Excess Review Priority'

        WHEN adr.coverage_quartile = 3
            THEN 'Elevated Excess Review Priority'

        ELSE 'Lower Relative Excess Priority'
    END AS inventory_review_priority

FROM product_coverage pc

JOIN products p
    ON pc.product_id = p.product_id

LEFT JOIN active_demand_ranked adr
    ON pc.product_id = adr.product_id

ORDER BY
    CASE
        WHEN pc.avg_30d_daily_demand = 0
             AND pc.ending_stock > 0 THEN 1
        WHEN adr.coverage_quartile = 4 THEN 2
        WHEN adr.coverage_quartile = 3 THEN 3
        ELSE 4
    END,
    ending_inventory_value DESC;

-- Key observations:
-- 1. The ending inventory position is broadly inventory-heavy.
--    All 119 products with recent demand hold more than one
--    supplier lead-time period of inventory.
--
-- 2. A fixed 5x coverage threshold classified nearly the
--    entire portfolio as potential excess and therefore did
--    not provide useful prioritization.
--
-- 3. Relative quartiles were used instead to prioritize
--    products for investigation. Quartile 4 represents the
--    highest 25% of coverage-to-lead-time ratios among
--    active-demand products.
--
-- 4. P072 is treated separately because it has zero recent
--    demand while retaining 3,220 units and approximately
--    $477K of inventory value.
--
-- 5. High operational excess and high financial exposure
--    are not necessarily the same. For example, P074 has
--    an extremely high coverage-to-lead-time ratio, while
--    P013 represents substantially greater inventory value.
--
-- 6. Relative priority does not represent a formal company
--    inventory policy. It is an analytical screening method
--    used to identify products requiring further review.

-- =====================================================
-- 9A. HISTORICAL STOCKOUT RATE QUARTILES
-- =====================================================
-- Purpose:
-- Rank products relative to the portfolio based on
-- historical stockout rate.
--
-- Quartile 4 = highest historical stockout rates
-- Quartile 1 = lowest historical stockout rates
-- =====================================================

WITH product_stockout AS (
    SELECT
        product_id,
        SUM(demand_quantity) AS total_demand,
        SUM(stockout_quantity) AS total_stockout_units,

        ROUND(
            100.0 * SUM(stockout_quantity)
            / NULLIF(SUM(demand_quantity), 0),
            2
        ) AS stockout_rate_pct

    FROM inventory

    GROUP BY product_id
),

stockout_ranked AS (
    SELECT
        product_id,
        stockout_rate_pct,

        NTILE(4) OVER (
            ORDER BY stockout_rate_pct
        ) AS stockout_quartile

    FROM product_stockout

    WHERE total_demand > 0
)

SELECT
    product_id,
    stockout_rate_pct,
    stockout_quartile
FROM stockout_ranked
WHERE stockout_quartile = 4
ORDER BY stockout_rate_pct DESC;

-- =====================================================
-- 9B. ACTIONABLE INVENTORY REVIEW LIST
-- =====================================================
-- Purpose:
-- Create a stakeholder-facing product review list by
-- combining current inventory position, recent demand,
-- supplier lead time, historical stockout performance,
-- financial exposure, and MOQ constraints.
--
-- The output prioritizes products for investigation and
-- provides recommended review actions. These actions are
-- decision-support recommendations rather than automated
-- purchasing decisions.
--
-- Analytical logic:
--
-- 1. Zero-Demand Review
--    Products with positive ending inventory but no demand
--    during the most recent 30-day period.
--
-- 2. High Replenishment Review
--    Products whose inventory coverage is below supplier
--    lead time and which also fall in the highest historical
--    stockout quartile.
--
-- 3. Replenishment Review
--    Products whose current inventory coverage is below
--    supplier lead time.
--
-- 4. High Excess + Historical Stockout Review
--    Products in the highest current coverage quartile that
--    also fall in the highest historical stockout quartile.
--    These products require investigation because current
--    inventory is high despite significant past shortages.
--
-- 5. High Excess Review
--    Products in the highest current coverage quartile.
--
-- 6. Elevated Excess Review
--    Products in the third current coverage quartile.
--
-- 7. Lower Relative Priority
--    Remaining products. This classification is relative
--    to the portfolio and does not imply optimal inventory.
--
-- Important:
-- Coverage quartiles are relative analytical screening
-- measures because no formal company inventory-coverage
-- policy is provided in the business case.
-- =====================================================


WITH ending_inventory AS (
    SELECT
        product_id,
        SUM(closing_stock) AS ending_stock
    FROM inventory
    WHERE date = (SELECT MAX(date) FROM inventory)
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
            AS stockout_rate_pct

    FROM inventory

    GROUP BY product_id
),

stockout_ranked AS (
    SELECT
        product_id,
        stockout_rate_pct,

        NTILE(4) OVER (
            ORDER BY stockout_rate_pct
        ) AS stockout_quartile

    FROM product_stockout

    WHERE total_demand > 0
),

product_metrics AS (
    SELECT
        p.product_id,
        p.product_name,
        p.unit_cost,
        p.holding_cost_per_unit,
        p.moq,

        ei.ending_stock,

        rd.avg_30d_daily_demand,

        ps.supplier_id,
        ps.supplier_name,
        ps.standard_lead_time_days,

        so.total_demand,
        so.total_units_sold,
        so.total_stockout_units,
        so.stockout_rate_pct,

        sr.stockout_quartile,

        -- Current inventory coverage in days
        ei.ending_stock
        / NULLIF(rd.avg_30d_daily_demand, 0)
            AS recent_inventory_days,

        -- Inventory coverage relative to supplier lead time
        (
            ei.ending_stock
            / NULLIF(rd.avg_30d_daily_demand, 0)
        )
        / NULLIF(ps.standard_lead_time_days, 0)
            AS coverage_to_lead_time_ratio,

        -- Number of recent-demand days represented by one MOQ
        p.moq
        / NULLIF(rd.avg_30d_daily_demand, 0)
            AS moq_demand_days,

        -- Financial value of ending inventory
        ei.ending_stock * p.unit_cost
            AS ending_inventory_value,

        -- Estimated holding-cost exposure of ending inventory
        ei.ending_stock * p.holding_cost_per_unit
            AS ending_holding_cost

    FROM products p

    JOIN ending_inventory ei
        ON p.product_id = ei.product_id

    JOIN recent_demand rd
        ON p.product_id = rd.product_id

    JOIN primary_supplier ps
        ON p.product_id = ps.product_id

    JOIN product_stockout so
        ON p.product_id = so.product_id

    LEFT JOIN stockout_ranked sr
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
    product_id,
    product_name,

    ending_stock,

    ROUND(
        avg_30d_daily_demand,
        2
    ) AS avg_30d_daily_demand,

    ROUND(
        recent_inventory_days,
        2
    ) AS recent_inventory_days,

    supplier_id,
    supplier_name,
    standard_lead_time_days,

    ROUND(
        coverage_to_lead_time_ratio,
        2
    ) AS coverage_to_lead_time_ratio,

    coverage_quartile,

    ROUND(
        stockout_rate_pct,
        2
    ) AS historical_stockout_rate_pct,

    stockout_quartile,

    moq,

    ROUND(
        moq_demand_days,
        2
    ) AS moq_demand_days,

    ROUND(
        ending_inventory_value,
        2
    ) AS ending_inventory_value,

    ROUND(
        ending_holding_cost,
        2
    ) AS ending_holding_cost,

    CASE

        WHEN avg_30d_daily_demand = 0
             AND ending_stock > 0
        THEN 'Zero-Demand Review'

        WHEN coverage_to_lead_time_ratio < 1
             AND stockout_quartile = 4
        THEN 'High Replenishment Review'

        WHEN coverage_to_lead_time_ratio < 1
        THEN 'Replenishment Review'

        WHEN coverage_quartile = 4
             AND stockout_quartile = 4
        THEN 'High Excess + Historical Stockout Review'

        WHEN coverage_quartile = 4
        THEN 'High Excess Review'

        WHEN coverage_quartile = 3
        THEN 'Elevated Excess Review'

        ELSE 'Lower Relative Priority'

    END AS review_category,

    CASE

        WHEN avg_30d_daily_demand = 0
             AND ending_stock > 0
        THEN
            'Investigate demand outlook and dead-stock risk; review future purchasing before additional replenishment.'

        WHEN coverage_to_lead_time_ratio < 1
             AND stockout_quartile = 4
        THEN
            'Prioritize replenishment review; evaluate order quantity, lead-time demand, and safety-stock requirements.'

        WHEN coverage_to_lead_time_ratio < 1
        THEN
            'Review replenishment requirement against lead-time demand and available inventory.'

        WHEN coverage_quartile = 4
             AND stockout_quartile = 4
        THEN
            'Investigate recent replenishment and purchasing levels; current inventory is high despite significant historical stockouts.'

        WHEN coverage_quartile = 4
        THEN
            'Review purchasing levels and inventory-reduction opportunities against expected demand.'

        WHEN coverage_quartile = 3
        THEN
            'Monitor inventory coverage and review future order quantities before additional replenishment.'

        ELSE
            'Continue monitoring inventory position relative to demand and supplier lead time.'

    END AS recommended_review_action

FROM final_metrics

ORDER BY
    CASE
        WHEN avg_30d_daily_demand = 0
             AND ending_stock > 0
            THEN 1

        WHEN coverage_to_lead_time_ratio < 1
             AND stockout_quartile = 4
            THEN 2

        WHEN coverage_to_lead_time_ratio < 1
            THEN 3

        WHEN coverage_quartile = 4
             AND stockout_quartile = 4
            THEN 4

        WHEN coverage_quartile = 4
            THEN 5

        WHEN coverage_quartile = 3
            THEN 6

        ELSE 7
    END,

    ending_inventory_value DESC;


-- =====================================================
-- VALIDATION / KEY FINDINGS
-- =====================================================
-- Total products reviewed: 120
--
-- Review-category distribution:
--   Lower Relative Priority                  = 60
--   Elevated Excess Review                   = 30
--   High Excess Review                       = 22
--   High Excess + Historical Stockout Review = 7
--   Zero-Demand Review                       = 1
--
-- No products were classified as:
--   High Replenishment Review
--   Replenishment Review
--
-- Key interpretation:
-- The ending inventory snapshot is broadly inventory-heavy.
-- No active-demand product currently holds less than one
-- supplier lead-time period of inventory.
--
-- Seven products combine high current inventory coverage
-- with historically high stockout rates. These products
-- warrant investigation into changes in replenishment and
-- purchasing behavior rather than being treated simply as
-- overstocked products.
--
-- One product has positive ending inventory but zero recent
-- demand and therefore requires a separate dead-stock /
-- demand-outlook review.
--
-- These classifications are analytical review priorities,
-- not formal inventory-policy thresholds or automated
-- procurement decisions.
-- =====================================================