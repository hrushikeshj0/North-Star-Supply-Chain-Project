USE northstar_supply_chain;

-- =====================================================
-- 05. SUPPLIER PERFORMANCE ANALYSIS
-- =====================================================
-- Purpose:
-- Evaluate supplier delivery reliability, lead-time
-- performance, purchasing volume, and financial exposure
-- to identify suppliers requiring procurement review.
--
-- Business questions:
-- 1. Which suppliers deliver most reliably?
-- 2. Which suppliers have the highest late-delivery rates?
-- 3. How do actual lead times compare with expectations?
-- 4. How much purchasing spend is associated with each supplier?
-- 5. Are poor-performing suppliers strategically important
--    because of purchasing volume or product dependency?
-- =====================================================


-- =====================================================
-- 1. SUPPLIER DELIVERY PERFORMANCE BASELINE
-- =====================================================
-- One row per supplier summarizing purchasing activity
-- and historical delivery performance.
-- =====================================================

SELECT
    s.supplier_id,
    s.supplier_name,
    s.standard_lead_time_days,

    COUNT(p.purchase_id) AS total_purchase_orders,

    SUM(p.quantity) AS total_units_purchased,

    ROUND(
        SUM(p.quantity * p.unit_cost),
        2
    ) AS total_purchase_spend,

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

    ROUND(
        100.0 *
        SUM(
            CASE
                WHEN p.actual_delivery_date <= p.expected_delivery_date
                THEN 1
                ELSE 0
            END
        )
        / NULLIF(COUNT(p.purchase_id), 0),
        2
    ) AS on_time_delivery_pct,

    ROUND(
        AVG(
            DATEDIFF(
                p.actual_delivery_date,
                p.purchase_date
            )
        ),
        2
    ) AS avg_actual_lead_time_days,

    ROUND(
        AVG(
            DATEDIFF(
                p.actual_delivery_date,
                p.expected_delivery_date
            )
        ),
        2
    ) AS avg_delivery_variance_days,

    ROUND(
        AVG(
            CASE
                WHEN p.actual_delivery_date > p.expected_delivery_date
                THEN DATEDIFF(
                    p.actual_delivery_date,
                    p.expected_delivery_date
                )
            END
        ),
        2
    ) AS avg_late_delivery_days

FROM suppliers s

JOIN purchases p
    ON s.supplier_id = p.supplier_id

GROUP BY
    s.supplier_id,
    s.supplier_name,
    s.standard_lead_time_days

ORDER BY
    on_time_delivery_pct ASC,
    avg_late_delivery_days DESC;

-- Key observation:
-- Supplier delivery performance varies significantly
-- across the supplier portfolio.
--
-- Lowest on-time delivery performance:
--   S004 = 32.26%
--   S006 = 33.33%
--   S011 = 43.66%
--
-- Highest on-time delivery performance:
--   S018 = 93.33%
--   S001 = 92.68%
--   S009 = 92.59%
--   S019 = 92.54%
--
-- S004 shows particularly weak delivery reliability:
-- only 20 of 62 purchase orders were delivered on time,
-- while 42 were delivered late.
--
-- S006 also shows poor reliability, with only 9 of
-- 27 purchase orders delivered on time.
--
-- S011 combines a relatively long standard lead time
-- (18 days) with low on-time performance (43.66%).
--
-- S020 requires additional attention despite performing
-- better than the three lowest-reliability suppliers.
-- Northstar purchased approximately $13.22M from S020,
-- while its on-time delivery rate was only 67.29%.
-- This indicates that supplier performance should be
-- evaluated together with business exposure rather than
-- delivery reliability alone.
--
-- The strongest suppliers achieved approximately
-- 92-93% on-time delivery performance.
--
-- These findings identify suppliers for further review,
-- but do not establish that supplier delays caused
-- product stockouts. Establishing causality would require
-- analysis of individual replenishment and inventory events.
-- =====================================================

-- =====================================================
-- 2. SUPPLIER RELIABILITY AND BUSINESS EXPOSURE
-- =====================================================
-- Purpose:
-- Compare supplier delivery reliability with purchasing
-- exposure to distinguish poor-performing suppliers from
-- poor-performing suppliers that also represent material
-- operational or financial dependency.
--
-- Reliability quartile:
--   Q1 = lowest on-time delivery performance
--   Q4 = highest on-time delivery performance
--
-- Spend quartile:
--   Q1 = lowest purchasing spend
--   Q4 = highest purchasing spend
--
-- Quartiles are portfolio-relative analytical measures,
-- not formal supplier-performance thresholds.
-- =====================================================

WITH supplier_metrics AS (
    SELECT
        s.supplier_id,
        s.supplier_name,
        s.standard_lead_time_days,

        COUNT(p.purchase_id) AS total_purchase_orders,

        SUM(p.quantity) AS total_units_purchased,

        SUM(p.quantity * p.unit_cost)
            AS total_purchase_spend,

        100.0 *
        SUM(
            CASE
                WHEN p.actual_delivery_date
                     <= p.expected_delivery_date
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
                WHEN p.actual_delivery_date
                     > p.expected_delivery_date
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
        s.standard_lead_time_days
),

supplier_ranked AS (
    SELECT
        *,

        NTILE(4) OVER (
            ORDER BY on_time_delivery_pct
        ) AS reliability_quartile,

        NTILE(4) OVER (
            ORDER BY total_purchase_spend
        ) AS spend_quartile

    FROM supplier_metrics
)

SELECT
    supplier_id,
    supplier_name,

    total_purchase_orders,
    total_units_purchased,

    ROUND(
        total_purchase_spend,
        2
    ) AS total_purchase_spend,

    ROUND(
        on_time_delivery_pct,
        2
    ) AS on_time_delivery_pct,

    ROUND(
        avg_actual_lead_time_days,
        2
    ) AS avg_actual_lead_time_days,

    ROUND(
        avg_late_delivery_days,
        2
    ) AS avg_late_delivery_days,

    reliability_quartile,
    spend_quartile,

    CASE
        WHEN reliability_quartile = 1
             AND spend_quartile = 4
        THEN 'High-Priority Supplier Review'

        WHEN reliability_quartile = 1
        THEN 'Reliability Review'

        WHEN reliability_quartile = 2
             AND spend_quartile = 4
        THEN 'Monitor - High Spend'

        ELSE 'Standard Monitoring'
    END AS supplier_review_category

FROM supplier_ranked

ORDER BY
    CASE
        WHEN reliability_quartile = 1
             AND spend_quartile = 4 THEN 1
        WHEN reliability_quartile = 1 THEN 2
        WHEN reliability_quartile = 2
             AND spend_quartile = 4 THEN 3
        ELSE 4
    END,

    total_purchase_spend DESC;

-- Key observations:
-- Combining delivery reliability with purchasing spend
-- changes supplier prioritization significantly.
--
-- S020 is the highest-priority supplier for procurement
-- review. Its on-time delivery rate is only 67.29%,
-- placing it in the lowest reliability quartile, while
-- approximately $13.22M of purchasing spend places it
-- in the highest spend quartile.
--
-- S004, S006, S011, and S013 also fall within the lowest
-- reliability quartile and should be reviewed for delivery
-- performance. Their financial exposure, however, is lower
-- than S020.
--
-- S016 and S017 represent a different type of risk.
-- Both are in the highest purchasing-spend quartile, but
-- fall in the second reliability quartile. Their large
-- purchasing exposure makes continued monitoring important
-- even though they are not among the least reliable suppliers.
--
-- High purchasing spend alone does not indicate poor supplier
-- performance. For example, S008 is the highest-spend supplier
-- at approximately $16.99M while maintaining an 88.81%
-- on-time delivery rate.
--
-- Supplier review priority should therefore consider both
-- operational reliability and business exposure rather than
-- either metric independently.
--
-- Quartiles are relative to Northstar's supplier portfolio
-- and are used for analytical prioritization rather than as
-- =====================================================

-- =====================================================
-- 3. SUPPLIER PRODUCT DEPENDENCY
-- =====================================================
-- Purpose:
-- Measure Northstar's product-level dependency on each
-- supplier using the product-supplier relationship table.
--
-- total_products_supplied:
-- Number of products the supplier is approved/available
-- to supply.
--
-- primary_products:
-- Number of products for which the supplier is designated
-- as the primary supplier.
--
-- sole_source_products:
-- Number of products for which this supplier is the only
-- supplier represented in the product-supplier network.
--
-- This adds strategic dependency context to supplier
-- delivery and financial performance.
-- =====================================================

WITH product_supplier_count AS (
    SELECT
        product_id,
        COUNT(*) AS supplier_count
    FROM product_suppliers
    GROUP BY product_id
)

SELECT
    s.supplier_id,
    s.supplier_name,

    COUNT(
        DISTINCT ps.product_id
    ) AS total_products_supplied,

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

FROM suppliers s

LEFT JOIN product_suppliers ps
    ON s.supplier_id = ps.supplier_id

LEFT JOIN product_supplier_count psc
    ON ps.product_id = psc.product_id

GROUP BY
    s.supplier_id,
    s.supplier_name

ORDER BY
    primary_products DESC,
    sole_source_products DESC;

-- Key observations:
-- Supplier dependency varies considerably across the
-- product portfolio.
--
-- S016 has the broadest supplier relationship footprint,
-- supplying 21 products and acting as the primary supplier
-- for 13. It is also the sole modeled supplier for 6
-- products, the highest sole-source exposure in the
-- supplier network.
--
-- S007 is another important supplier, supporting 14
-- products, including 11 primary-supplier relationships
-- and 5 sole-source products.
--
-- S011 presents a notable continuity-risk combination.
-- Although it supplies only 5 products, it is the primary
-- supplier for all 5 and is the sole modeled supplier for
-- 4 of them. Combined with its 43.66% on-time delivery
-- rate, this makes S011 important for procurement review
-- despite its relatively low purchasing spend.
--
-- S020, already identified as a high-priority supplier
-- because of low relative reliability and high purchasing
-- spend, is also the primary supplier for 9 products and
-- the sole modeled supplier for 2 products. This further
-- increases its strategic importance.
--
-- S004 also combines poor delivery performance with some
-- dependency exposure: it is the primary supplier for
-- 4 products and the sole modeled supplier for 2.
--
-- Supplier dependency should therefore be considered
-- alongside delivery reliability and purchasing spend.
-- A supplier with relatively low spend may still represent
-- significant operational risk when alternative suppliers
-- are limited.
--
-- "Sole-source" refers only to supplier relationships
-- represented in the Northstar dataset and does not imply
-- contractual exclusivity.
-- =====================================================

-- =====================================================
-- 4. FINAL SUPPLIER REVIEW LIST
-- =====================================================
-- Purpose:
-- Combine delivery reliability, purchasing exposure, and
-- product dependency into one supplier-level decision-
-- support dataset for procurement review.
--
-- Review categories prioritize investigation. They do not
-- represent automatic supplier replacement decisions.
-- =====================================================

WITH supplier_performance AS (
    SELECT
        s.supplier_id,
        s.supplier_name,
        s.standard_lead_time_days,

        COUNT(p.purchase_id) AS total_purchase_orders,

        SUM(p.quantity) AS total_units_purchased,

        SUM(p.quantity * p.unit_cost)
            AS total_purchase_spend,

        SUM(
            CASE
                WHEN p.actual_delivery_date
                     <= p.expected_delivery_date
                THEN 1
                ELSE 0
            END
        ) AS on_time_deliveries,

        SUM(
            CASE
                WHEN p.actual_delivery_date
                     > p.expected_delivery_date
                THEN 1
                ELSE 0
            END
        ) AS late_deliveries,

        100.0 *
        SUM(
            CASE
                WHEN p.actual_delivery_date
                     <= p.expected_delivery_date
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
                WHEN p.actual_delivery_date
                     > p.expected_delivery_date
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
        s.standard_lead_time_days
),

supplier_ranked AS (
    SELECT
        *,

        NTILE(4) OVER (
            ORDER BY on_time_delivery_pct
        ) AS reliability_quartile,

        NTILE(4) OVER (
            ORDER BY total_purchase_spend
        ) AS spend_quartile

    FROM supplier_performance
),

product_supplier_count AS (
    SELECT
        product_id,
        COUNT(*) AS supplier_count

    FROM product_suppliers

    GROUP BY product_id
),

supplier_dependency AS (
    SELECT
        s.supplier_id,

        COUNT(
            DISTINCT ps.product_id
        ) AS total_products_supplied,

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

    FROM suppliers s

    LEFT JOIN product_suppliers ps
        ON s.supplier_id = ps.supplier_id

    LEFT JOIN product_supplier_count psc
        ON ps.product_id = psc.product_id

    GROUP BY s.supplier_id
)

SELECT
    sr.supplier_id,
    sr.supplier_name,

    sr.total_purchase_orders,
    sr.total_units_purchased,

    ROUND(
        sr.total_purchase_spend,
        2
    ) AS total_purchase_spend,

    sr.on_time_deliveries,
    sr.late_deliveries,

    ROUND(
        sr.on_time_delivery_pct,
        2
    ) AS on_time_delivery_pct,

    sr.standard_lead_time_days,

    ROUND(
        sr.avg_actual_lead_time_days,
        2
    ) AS avg_actual_lead_time_days,

    ROUND(
        sr.avg_late_delivery_days,
        2
    ) AS avg_late_delivery_days,

    sr.reliability_quartile,
    sr.spend_quartile,

    sd.total_products_supplied,
    sd.primary_products,
    sd.sole_source_products,

    CASE

        WHEN sr.reliability_quartile = 1
             AND (
                 sr.spend_quartile = 4
                 OR sd.sole_source_products > 0
             )
        THEN 'High-Priority Supplier Review'

        WHEN sr.reliability_quartile = 1
        THEN 'Reliability Review'

        WHEN sr.reliability_quartile = 2
             AND sr.spend_quartile = 4
        THEN 'Monitor - High Spend'

        WHEN sd.sole_source_products >= 3
        THEN 'Monitor - Supplier Dependency'

        ELSE 'Standard Monitoring'

    END AS supplier_review_category,

    CASE

        WHEN sr.reliability_quartile = 1
             AND sr.spend_quartile = 4
        THEN
            'Prioritize supplier performance review due to weak relative delivery reliability and high purchasing exposure.'

        WHEN sr.reliability_quartile = 1
             AND sd.sole_source_products > 0
        THEN
            'Review delivery performance and alternative sourcing options due to weak reliability and sole-source product exposure.'

        WHEN sr.reliability_quartile = 1
        THEN
            'Review supplier delivery performance and investigate recurring causes of late deliveries.'

        WHEN sr.reliability_quartile = 2
             AND sr.spend_quartile = 4
        THEN
            'Continue close monitoring due to high purchasing exposure and below-upper-tier delivery reliability.'

        WHEN sd.sole_source_products >= 3
        THEN
            'Review sourcing resilience and alternative supplier coverage for products with limited modeled supplier options.'

        ELSE
            'Continue standard supplier performance monitoring.'

    END AS recommended_review_action

FROM supplier_ranked sr

JOIN supplier_dependency sd
    ON sr.supplier_id = sd.supplier_id

ORDER BY

    CASE

        WHEN sr.reliability_quartile = 1
             AND (
                 sr.spend_quartile = 4
                 OR sd.sole_source_products > 0
             )
        THEN 1

        WHEN sr.reliability_quartile = 1
        THEN 2

        WHEN sr.reliability_quartile = 2
             AND sr.spend_quartile = 4
        THEN 3

        WHEN sd.sole_source_products >= 3
        THEN 4

        ELSE 5

    END,

    sr.total_purchase_spend DESC;

-- FINAL SUPPLIER ANALYSIS FINDINGS:
-- The final supplier review combines delivery reliability,
-- purchasing exposure, and product dependency rather than
-- evaluating suppliers using a single KPI.
--
-- Five suppliers were classified as High-Priority Supplier
-- Review: S020, S013, S011, S004, and S006.
--
-- S020 represents a major procurement concern because it
-- combines lowest-quartile delivery reliability (67.29%
-- on-time) with approximately $13.22M in purchasing spend,
-- placing it in the highest spend quartile. It is also the
-- primary supplier for 9 products and the sole modeled
-- supplier for 2 products.
--
-- S011 represents a different type of supplier risk.
-- Purchasing spend is relatively low at approximately
-- $2.00M, but its on-time delivery rate is only 43.66%.
-- It is also the primary supplier for all 5 products it
-- supplies and is the sole modeled supplier for 4.
-- Therefore, supplier importance cannot be assessed from
-- purchasing spend alone.
--
-- S004 has the lowest on-time delivery rate in the supplier
-- portfolio at 32.26%. It is the primary supplier for
-- 4 products and the sole modeled supplier for 2, making
-- alternative sourcing worth investigating.
--
-- S006 also has very weak delivery reliability at 33.33%
-- on-time and has one sole-source product relationship.
--
-- S013 has a 68.67% on-time delivery rate and one
-- sole-source product relationship, placing it in the
-- high-priority review group despite moderate spend.
--
-- S016 and S017 were classified as Monitor - High Spend.
-- Both have substantial purchasing exposure but stronger
-- delivery performance than the lowest reliability
-- quartile. They should therefore be monitored rather
-- than treated as immediate supplier-replacement candidates.
--
-- S007 and S010 were classified as Monitor - Supplier
-- Dependency. S007 is particularly important from a
-- sourcing-resilience perspective because it is the sole
-- modeled supplier for 5 products while maintaining
-- relatively strong 91.56% on-time delivery performance.
--
-- S008 has the highest purchasing spend in the portfolio
-- at approximately $16.99M while maintaining an 88.81%
-- on-time delivery rate. High financial exposure therefore
-- does not automatically indicate poor supplier performance.
--
-- Recommended procurement actions include investigating
-- recurring causes of late deliveries, reviewing alternative
-- sourcing for products with limited supplier coverage,
-- and closely monitoring high-spend suppliers.
--
-- The analysis does not establish that supplier delays
-- caused historical product stockouts. Supplier performance
-- and inventory availability are related operational areas,
-- but causal attribution would require event-level analysis
-- of replenishment timing and inventory positions.
--
-- Review categories and dependency thresholds are analytical
-- screening tools rather than formal Northstar procurement
-- policies. "Sole-source" refers only to supplier
-- relationships represented in the modeled dataset.
-- =====================================================