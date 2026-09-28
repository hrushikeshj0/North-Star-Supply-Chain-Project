# North Star Supply Chain — Dataset Generation Logic

## Purpose

This project uses synthetic, AI-assisted data for portfolio and analytical practice. It does not represent a real company, supplier, or customer. The dataset is designed to support realistic questions about demand, supplier performance, inventory health, purchasing costs, and data quality.

## Scope and scale

The first dataset covers the 2025 calendar year. A fixed random seed will make the generator reproducible.

| Entity | Planned volume | Rule |
| --- | ---: | --- |
| `categories` | 6 | Product groupings used for analysis. |
| `products` | 120 | 20 products per category. |
| `suppliers` | 20 | Suppliers have distinct cost, lead-time, and reliability profiles. |
| `warehouses` | 5 | Geographic fulfillment locations. |
| `date` | 365 | Every date from 2025-01-01 through 2025-12-31. |
| `product_suppliers` | 240 | Each product has one primary and one secondary supplier. |
| `sales` | Approximately 100,000–130,000 | Transaction-level demand events. |
| `purchases` | Generated from replenishment decisions | One purchase-order line per product, supplier, and destination warehouse. |
| `inventory` | 219,000 | One row for every date × product × warehouse. |

`inventory` has 365 × 120 × 5 rows. Its grain is one product at one warehouse on one date.

## Model refinement: transaction locations

Both transaction tables will include `warehouse_id` as a foreign key to `warehouses`.

Each purchase line must have a receiving destination. Each sales transaction must record the warehouse that fulfilled it. These two fields let us reconcile delivered purchases and sales against the correct warehouse inventory record, as well as perform warehouse-level procurement and sales analysis.

```text
sales
  sale_id
  product_id
  warehouse_id
  sale_date
  quantity
  revenue
```

```text
purchases
  purchase_id
  product_id
  supplier_id
  warehouse_id
  purchase_date
  quantity
  unit_cost
  expected_delivery_date
  actual_delivery_date
```

## Reference-data rules

### Categories and products

The six categories will be Electronics, Office Supplies, Home & Kitchen, Personal Care, Outdoor, and Accessories.

Every product receives:

- a category;
- a standard unit cost and selling price;
- a holding cost per unit; and
- a minimum order quantity (MOQ).

Prices are generated so selling price is always greater than standard unit cost. Product margins are deliberately varied so later analysis can contrast high-volume, low-margin items with lower-volume, higher-margin items.

### Product demand profiles

| Profile | Share of products | Daily sales-event tendency | Business meaning |
| --- | ---: | --- | --- |
| High demand | 15% | 8–15 events | Fast movers; greater stockout risk. |
| Medium demand | 55% | 2–5 events | Normal operating products. |
| Low demand | 30% | 0–2 events | Slow movers; greater excess-stock risk. |

Sales quantities are positive integers. High-demand products sell in larger quantities than low-demand products. Category-level seasonality will also be applied; for example, Outdoor products have stronger demand in summer and all categories receive a modest fourth-quarter uplift.

### Supplier profiles

| Profile | Share of suppliers | Standard lead time | Delivery behavior |
| --- | ---: | --- | --- |
| Reliable | 40% | 4–10 days | Usually early or on time; slightly higher price. |
| Standard | 35% | 7–16 days | Mostly on time with occasional small delays. |
| At risk | 25% | 12–21 days | More frequent and longer delivery delays; often lower price. |

Every product has two eligible suppliers. One is marked primary. Orders normally use the primary supplier, but a controlled minority use the secondary supplier to create supplier-comparison scenarios.

## Operational simulation rules

The generator will simulate the year one day at a time. That ordering matters: sales reduce stock, delivered orders increase stock, and new purchase orders are placed only when stock needs replenishment.

1. Seed opening inventory by product and warehouse based on the product’s demand profile, lead time, and a safety-stock buffer.
2. For each date, receive any purchase orders whose actual delivery date is that day.
3. Generate sales events for active products at each warehouse. Sales cannot reduce stock below zero.
4. Calculate closing stock:

   ```text
   closing_stock = opening_stock + received_quantity - sold_quantity
   ```

5. When closing stock falls below the reorder point, create a purchase order for that product and warehouse.
6. The ordered quantity is at least the product MOQ and targets enough stock to cover the next lead-time period plus safety stock.
7. Expected delivery date is purchase date + the supplier's standard lead time. Actual delivery date reflects that supplier's reliability profile.
8. Carry each day's true closing stock forward as the next day's opening stock.

This produces intentional, explainable patterns rather than independent random CSV files.

## Inventory scenarios

| Scenario | Share of products | Generation treatment | Expected analytical signal |
| --- | ---: | --- | --- |
| Normal | 70% | Balanced reorder point and safety stock. | Stable service and inventory levels. |
| Stockout-prone | 10% | Tight safety stock, fast demand, or at-risk primary supplier. | Low/zero stock and lost-sales pressure. |
| Excess inventory | 10% | High initial stock or oversized replenishment quantities. | High inventory value and holding cost. |
| Slow-moving | 10% | Low demand combined with normal replenishment. | Low sales velocity and aging inventory. |

The scenario is assigned at the product level; warehouse demand variation prevents every location from looking identical.

## Intentional data-quality issues

The raw CSVs will contain a small, documented set of issues for a later data-quality phase. They will be injected only after the internally consistent “true” records are produced.

| Issue | Approximate rate | Table | Why it is useful |
| --- | ---: | --- | --- |
| Missing supplier location | 5% of suppliers | `suppliers` | Tests completeness checks. |
| Duplicate-looking sales event | 0.5% of sales | `sales` | Tests duplicate detection using business fields rather than just the primary key. |
| Missing actual delivery date | 1% of purchases | `purchases` | Represents incomplete receiving records and tests null handling. |
| Incorrect closing stock | 0.5% of inventory rows | `inventory` | Tests the inventory-balance validation rule. |

The generator will label these rules in its documentation but will not add a flag column to the raw data. The later quality-check exercise should detect them from the data itself.

## Validation rules for the generated data

Before the data is accepted, the generator will verify:

- all primary keys are unique;
- every foreign key points to an existing parent record;
- every product has exactly one primary supplier;
- `selling_price > unit_cost` for every product;
- purchase quantity is at least the applicable MOQ;
- expected delivery date is not before purchase date;
- actual delivery date, when present, is not before purchase date;
- inventory quantity values are non-negative; and
- inventory rows follow the opening + received − sold = closing relationship before intentional quality issues are injected.
