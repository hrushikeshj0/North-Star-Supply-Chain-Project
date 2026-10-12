USE northstar_supply_chain;

-- =====================================================
-- 06. PRODUCT PROFITABILITY ANALYSIS
-- =====================================================
-- Purpose:
-- Evaluate product sales contribution, estimated gross
-- profitability, margin performance, and inventory capital
-- exposure to support product and purchasing decisions.
--
-- Profitability calculations use fulfilled units from the
-- inventory table and product-level standard unit costs.
-- Therefore, results represent analytical gross-profit
-- estimates rather than accounting profitability.
-- =====================================================


-- =====================================================
-- 1. PRODUCT PROFITABILITY BASELINE
-- =====================================================

SELECT
    p.product_id,
    p.product_name,
    c.category_name,

    SUM(i.sold_quantity) AS total_units_sold,

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
    c.category_name,
    p.unit_cost,
    p.selling_price

ORDER BY
    estimated_gross_profit DESC;

-- Key observations:
-- Product profitability varies based on both fulfilled
-- sales volume and per-unit economics.
--
-- P039 generated the highest estimated gross profit at
-- approximately $3.97M from 16,546 fulfilled units.
-- Its strong 49.10% gross margin and approximately $240
-- gross profit per unit contributed to its leading position.
--
-- P062 generated approximately $3.29M in estimated gross
-- profit, supported by 17,226 fulfilled units and a
-- 48.94% gross margin.
--
-- High sales volume does not necessarily produce the
-- highest gross profit. P081 recorded 17,344 fulfilled
-- units, more than P039, but generated approximately
-- $1.84M in estimated gross profit because its gross
-- margin was lower at 29.82%.
--
-- Conversely, low unit sales can substantially limit total
-- profit contribution even when percentage margins are
-- relatively strong. P072, for example, has a 44.54%
-- gross margin but only 14 fulfilled units, resulting in
-- approximately $1.67K of estimated gross profit.
--
-- Product performance should therefore be evaluated using
-- both sales volume and margin rather than either measure
-- independently.
--
-- Profitability values are analytical estimates based on
-- standard product unit cost and fulfilled units. They do
-- not represent accounting net profit or transaction-level
-- inventory costing.
-- =====================================================

-- =====================================================
-- 2. SALES VOLUME AND MARGIN SEGMENTATION
-- =====================================================
-- Purpose:
-- Segment products based on relative fulfilled-sales volume
-- and gross-margin performance.
--
-- Sales quartile:
--   Q1 = lowest fulfilled-sales volume
--   Q4 = highest fulfilled-sales volume
--
-- Margin quartile:
--   Q1 = lowest gross margin
--   Q4 = highest gross margin
--
-- Quartiles are portfolio-relative analytical measures
-- rather than formal commercial-performance thresholds.
-- =====================================================

WITH product_profitability AS (
    SELECT
        p.product_id,
        p.product_name,
        c.category_name,

        SUM(i.sold_quantity) AS total_units_sold,

        p.unit_cost,
        p.selling_price,

        100.0 *
        (p.selling_price - p.unit_cost)
        / NULLIF(p.selling_price, 0)
            AS gross_margin_pct,

        SUM(i.sold_quantity)
        * (p.selling_price - p.unit_cost)
            AS estimated_gross_profit

    FROM products p

    JOIN categories c
        ON p.category_id = c.category_id

    JOIN inventory i
        ON p.product_id = i.product_id

    GROUP BY
        p.product_id,
        p.product_name,
        c.category_name,
        p.unit_cost,
        p.selling_price
),

product_ranked AS (
    SELECT
        *,

        NTILE(4) OVER (
            ORDER BY total_units_sold
        ) AS sales_volume_quartile,

        NTILE(4) OVER (
            ORDER BY gross_margin_pct
        ) AS margin_quartile

    FROM product_profitability
)

SELECT
    product_id,
    product_name,
    category_name,

    total_units_sold,

    ROUND(
        gross_margin_pct,
        2
    ) AS gross_margin_pct,

    ROUND(
        estimated_gross_profit,
        2
    ) AS estimated_gross_profit,

    sales_volume_quartile,
    margin_quartile,

    CASE
        WHEN sales_volume_quartile = 4
             AND margin_quartile = 4
        THEN 'High Volume / High Margin'

        WHEN sales_volume_quartile = 4
             AND margin_quartile = 1
        THEN 'High Volume / Low Margin'

        WHEN sales_volume_quartile = 1
             AND margin_quartile = 4
        THEN 'Low Volume / High Margin'

        WHEN sales_volume_quartile = 1
             AND margin_quartile = 1
        THEN 'Low Volume / Low Margin'

        ELSE 'Mid-Portfolio / Mixed'
    END AS commercial_segment

FROM product_ranked

ORDER BY
    CASE
        WHEN sales_volume_quartile = 4
             AND margin_quartile = 4 THEN 1

        WHEN sales_volume_quartile = 4
             AND margin_quartile = 1 THEN 2

        WHEN sales_volume_quartile = 1
             AND margin_quartile = 4 THEN 3

        WHEN sales_volume_quartile = 1
             AND margin_quartile = 1 THEN 4

        ELSE 5
    END,

    estimated_gross_profit DESC;

-- =====================================================
-- STEP 2 VALIDATION: COMMERCIAL SEGMENT SUMMARY
-- =====================================================

WITH product_profitability AS (
    SELECT
        p.product_id,
        p.product_name,

        SUM(i.sold_quantity) AS total_units_sold,

        100.0 *
        (p.selling_price - p.unit_cost)
        / NULLIF(p.selling_price, 0)
            AS gross_margin_pct

    FROM products p

    JOIN inventory i
        ON p.product_id = i.product_id

    GROUP BY
        p.product_id,
        p.product_name,
        p.unit_cost,
        p.selling_price
),

product_ranked AS (
    SELECT
        *,

        NTILE(4) OVER (
            ORDER BY total_units_sold
        ) AS sales_volume_quartile,

        NTILE(4) OVER (
            ORDER BY gross_margin_pct
        ) AS margin_quartile

    FROM product_profitability
),

product_segmented AS (
    SELECT
        product_id,

        CASE
            WHEN sales_volume_quartile = 4
                 AND margin_quartile = 4
            THEN 'High Volume / High Margin'

            WHEN sales_volume_quartile = 4
                 AND margin_quartile = 1
            THEN 'High Volume / Low Margin'

            WHEN sales_volume_quartile = 1
                 AND margin_quartile = 4
            THEN 'Low Volume / High Margin'

            WHEN sales_volume_quartile = 1
                 AND margin_quartile = 1
            THEN 'Low Volume / Low Margin'

            ELSE 'Mid-Portfolio / Mixed'
        END AS commercial_segment

    FROM product_ranked
)

SELECT
    commercial_segment,
    COUNT(*) AS product_count

FROM product_segmented

GROUP BY commercial_segment

ORDER BY product_count DESC;

-- Key observations:
-- Sales-volume and margin segmentation identified several
-- distinct commercial profiles across the product portfolio.
--
-- 10 products were classified as High Volume / High Margin.
-- These products combine strong fulfilled-sales volume with
-- upper-quartile gross margins and represent commercially
-- attractive products within the portfolio.
--
-- 4 products were classified as High Volume / Low Margin.
-- These products generate strong sales volume but operate
-- with bottom-quartile gross margins. They should be reviewed
-- for pricing, product cost, and margin-improvement
-- opportunities rather than judged on volume alone.
--
-- 5 products were classified as Low Volume / High Margin.
-- Although their per-unit economics are relatively strong,
-- low fulfilled-sales volume limits their overall commercial
-- contribution. Demand, availability, and product positioning
-- should be considered before recommending action.
--
-- 10 products were classified as Low Volume / Low Margin.
-- These products combine weak relative sales volume with
-- bottom-quartile margins and may warrant closer portfolio
-- review.
--
-- The remaining 91 products fall into mixed combinations
-- of sales-volume and margin quartiles and were classified
-- as Mid-Portfolio / Mixed.
--
-- These segments are relative to the Northstar product
-- portfolio and are analytical screening categories rather
-- than formal commercial-performance thresholds.
-- =====================================================

-- =====================================================
-- 3. PROFITABILITY AND INVENTORY CAPITAL EXPOSURE
-- =====================================================
-- Purpose:
-- Compare estimated product gross-profit contribution with
-- the financial value of ending inventory.
--
-- This helps distinguish products with large inventory
-- positions that also generate substantial commercial value
-- from products where significant capital is tied up despite
-- relatively weak gross-profit contribution.
--
-- Important:
-- Gross profit is measured across the historical analysis
-- period, while ending inventory value is a point-in-time
-- snapshot. Therefore, the measures are compared for
-- prioritization rather than treated as an accounting ratio.
-- =====================================================

WITH product_profitability AS (
    SELECT
        p.product_id,
        p.product_name,
        c.category_name,

        SUM(i.sold_quantity) AS total_units_sold,

        SUM(i.sold_quantity)
        * (p.selling_price - p.unit_cost)
            AS estimated_gross_profit

    FROM products p

    JOIN categories c
        ON p.category_id = c.category_id

    JOIN inventory i
        ON p.product_id = i.product_id

    GROUP BY
        p.product_id,
        p.product_name,
        c.category_name,
        p.selling_price,
        p.unit_cost
),

ending_inventory AS (
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

product_financials AS (
    SELECT
        pp.product_id,
        pp.product_name,
        pp.category_name,
        pp.total_units_sold,
        pp.estimated_gross_profit,

        ei.ending_stock,

        ei.ending_stock * p.unit_cost
            AS ending_inventory_value

    FROM product_profitability pp

    JOIN ending_inventory ei
        ON pp.product_id = ei.product_id

    JOIN products p
        ON pp.product_id = p.product_id
),

financial_ranked AS (
    SELECT
        *,

        NTILE(4) OVER (
            ORDER BY estimated_gross_profit
        ) AS gross_profit_quartile,

        NTILE(4) OVER (
            ORDER BY ending_inventory_value
        ) AS inventory_value_quartile

    FROM product_financials
)

SELECT
    product_id,
    product_name,
    category_name,

    total_units_sold,

    ROUND(
        estimated_gross_profit,
        2
    ) AS estimated_gross_profit,

    ending_stock,

    ROUND(
        ending_inventory_value,
        2
    ) AS ending_inventory_value,

    gross_profit_quartile,
    inventory_value_quartile,

    CASE
        WHEN inventory_value_quartile = 4
             AND gross_profit_quartile = 1
        THEN 'High Capital / Low Profit Contribution'

        WHEN inventory_value_quartile = 4
             AND gross_profit_quartile = 4
        THEN 'High Capital / High Profit Contribution'

        WHEN inventory_value_quartile = 1
             AND gross_profit_quartile = 4
        THEN 'Low Capital / High Profit Contribution'

        ELSE 'Balanced / Mixed'
    END AS capital_profit_profile

FROM financial_ranked

ORDER BY
    CASE
        WHEN inventory_value_quartile = 4
             AND gross_profit_quartile = 1 THEN 1

        WHEN inventory_value_quartile = 4
             AND gross_profit_quartile = 4 THEN 2

        WHEN inventory_value_quartile = 1
             AND gross_profit_quartile = 4 THEN 3

        ELSE 4
    END,

    ending_inventory_value DESC;

-- =====================================================
-- STEP 3 VALIDATION: CAPITAL / PROFIT PROFILE SUMMARY
-- =====================================================

WITH product_profitability AS (
    SELECT
        p.product_id,
        p.product_name,
        c.category_name,

        SUM(i.sold_quantity) AS total_units_sold,

        SUM(i.sold_quantity)
        * (p.selling_price - p.unit_cost)
            AS estimated_gross_profit

    FROM products p

    JOIN categories c
        ON p.category_id = c.category_id

    JOIN inventory i
        ON p.product_id = i.product_id

    GROUP BY
        p.product_id,
        p.product_name,
        c.category_name,
        p.selling_price,
        p.unit_cost
),

ending_inventory AS (
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

product_financials AS (
    SELECT
        pp.product_id,
        pp.estimated_gross_profit,

        ei.ending_stock * p.unit_cost
            AS ending_inventory_value

    FROM product_profitability pp

    JOIN ending_inventory ei
        ON pp.product_id = ei.product_id

    JOIN products p
        ON pp.product_id = p.product_id
),

financial_ranked AS (
    SELECT
        *,

        NTILE(4) OVER (
            ORDER BY estimated_gross_profit
        ) AS gross_profit_quartile,

        NTILE(4) OVER (
            ORDER BY ending_inventory_value
        ) AS inventory_value_quartile

    FROM product_financials
),

financial_segmented AS (
    SELECT
        product_id,

        CASE
            WHEN inventory_value_quartile = 4
                 AND gross_profit_quartile = 1
            THEN 'High Capital / Low Profit Contribution'

            WHEN inventory_value_quartile = 4
                 AND gross_profit_quartile = 4
            THEN 'High Capital / High Profit Contribution'

            WHEN inventory_value_quartile = 1
                 AND gross_profit_quartile = 4
            THEN 'Low Capital / High Profit Contribution'

            ELSE 'Balanced / Mixed'
        END AS capital_profit_profile

    FROM financial_ranked
)

SELECT
    capital_profit_profile,
    COUNT(*) AS product_count

FROM financial_segmented

GROUP BY capital_profit_profile

ORDER BY product_count DESC;

-- Key observations:
-- The capital-versus-profit segmentation produced two
-- observed profiles across the 120-product portfolio:
--
--   High Capital / High Profit Contribution = 23 products
--   Balanced / Mixed                        = 97 products
--
-- No products were classified as High Capital / Low Profit
-- Contribution or Low Capital / High Profit Contribution.
--
-- All 23 products that simultaneously reached the highest
-- ending-inventory-value quartile and an explicitly defined
-- capital/profit profile also fell within the highest
-- gross-profit quartile.
--
-- This suggests that high inventory-value exposure is
-- concentrated largely among products that also make strong
-- gross-profit contributions within the modeled portfolio.
--
-- Therefore, high inventory value alone should not be
-- interpreted as inefficient capital allocation. Several
-- high-value inventory positions support commercially
-- important products.
--
-- This finding should be considered together with the
-- inventory coverage analysis. A product may generate high
-- gross profit while still carrying more inventory than
-- recent demand and supplier lead time appear to require.
--
-- No evidence was found in this segmentation of products
-- simultaneously having top-quartile ending inventory value
-- and bottom-quartile gross-profit contribution.
--
-- Gross profit represents a historical-period flow measure,
-- while ending inventory value represents a point-in-time
-- snapshot. The comparison is therefore intended for
-- portfolio prioritization rather than as an accounting
-- return-on-investment calculation.
-- =====================================================