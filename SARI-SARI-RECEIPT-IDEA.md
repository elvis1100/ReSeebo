# Sari-Sari Store Receipt & Supplier Comparison App

> **The idea:** Scan purchase receipts, compare the cost of the same products across suppliers, and help sari-sari store owners plan purchases and selling prices.

**Status:** Brainstorming concept, not a final specification.  
**Hackathon build window:** 20 hours.  
**Product name and AI model:** Still to be decided.

## 1. The problem

Sari-sari store owners buy stock from different groceries, wholesalers, and suppliers. The same product can have different prices depending on where and when they buy it.

Owners may buy from the same supplier repeatedly, or buy from different suppliers on different days. They do not need to purchase from several stores at once to benefit from the app.

Even at the same supplier, a product's price may go up on the next purchase because of inflation, supplier cost changes, or an ended promotion. If the owner keeps the same selling price, their gross profit per piece can decrease. Receipts show the price change, but do not necessarily explain its cause.

Comparing those prices manually means reading old receipts, remembering product names, checking pack sizes, and doing calculations. This becomes harder when receipts use abbreviated names or show prices per pack rather than per piece.

An owner may want to answer:

- Where did I buy this exact product for less?
- Is this supplier still cheaper based on my recent purchases?
- Did the price go up since my last purchase from this supplier?
- How much would I save on my next purchase?
- Is the cheaper supplier worth the additional travel cost?
- How much would I earn per piece at my chosen selling price?

**Our main focus is comparing the same brand, variant, and size across suppliers and across purchase dates.** Comparing different brands can be explored later.

## 2. The proposed solution

A mobile app that turns purchase receipts into a personal supplier price record.

The owner scans a receipt, checks the extracted information, and saves it. The app then compares those purchases with previously saved receipts and presents clear tables showing prices, dates, differences, and other useful details.

The intended result is less manual encoding and easier buying decisions, with the receipt available as evidence for each recorded price.

## 3. What the app does

| Feature | What it helps the owner do |
| --- | --- |
| Scan a receipt | Capture purchase information without typing every line. |
| Review extracted details | Correct unclear names, quantities, or prices before saving. |
| Recognize previously saved products | Connect different receipt descriptions to the same confirmed product. |
| Calculate cost per piece | Compare packs, bundles, and individual items fairly. |
| Compare supplier prices | See which recorded supplier price is lower for the same product. |
| Show price changes | Notice when the latest purchase costs more than an earlier one. |
| Calculate possible tubo | See the estimated gross profit per piece at a chosen selling price. |
| Plan a restock purchase | Estimate purchase costs and savings using saved prices. |

## 4. How the solution would be achieved

The app combines **local AI recognition with ordinary calculations and automation**.

1. **Read the receipt.** Extract text and identify likely supplier, date, products, quantities, and amounts on the phone.
2. **Ask the owner to check it.** Show unclear or missing details instead of silently guessing.
3. **Connect the products.** Suggest matches with the owner's existing product list. Save confirmed matches so future scans require less correction.
4. **Make prices comparable.** Convert the confirmed purchase into cost per sellable piece.
5. **Save and compare.** Store the receipt and purchase details locally, then calculate comparisons and pricing scenarios.

The AI handles recognition and suggested matching. The app's calculations handle costs, differences, and estimated savings, which can be presented directly in tables. Optional sentence summaries can be explored if the offline model supports them reliably; they are not required for the comparisons to be useful.

**We should not promise that every receipt will work automatically.** Layouts vary, names may be shortened, and receipts may omit brand, size, or pieces per pack. The owner must be able to supply those missing details. Category can also be suggested or chosen by the owner.

## 5. The app workflow

**Scan → Review → Confirm product matches → Save → Compare → Plan**

### Step 1: Scan or import a receipt

The owner takes a photo or selects an existing receipt image.

### Step 2: Review the information

The app presents an editable list containing:

- Supplier name and purchase date.
- Product description, with brand, variant, and size where available.
- Quantity purchased and whether it means pieces or packs.
- Pieces per pack, when relevant.
- Line amount and any identifiable discount.

The original image remains available for checking. The app should flag inconsistent amounts and possible duplicate receipts for review.

### Step 3: Confirm which products these are

For example, `BRANDX COF ORIG 26G` may match the owner's saved product, `Brand X Original Coffee 26g`.

Different sizes or variants remain separate. A 26g sachet should not be treated as the same product as a 33g sachet.

### Step 4: Save the purchase

The app calculates cost per piece from the confirmed quantity and amount, then adds a new purchase record to the product's price history. A new purchase does not replace earlier purchases, including purchases from the same supplier.

### Step 5: View comparisons

The owner opens a product and sees tables comparing the latest recorded price per supplier and the price history at a selected supplier. Each price includes its purchase date and a link to the source receipt.

### Step 6: Plan a purchase or selling price

The owner enters a planned restock quantity or selling price. The app shows estimated purchase costs, savings, or gross profit per piece.

## 6. The most valuable comparisons

Tables are the main way to present insights. Clear labels, comparable units, dates, and highlighted differences are enough; the app does not need to generate a sentence for every result.

| Comparison | Essential details to show |
| --- | --- |
| Same product, different suppliers | Supplier, latest purchase date, quantity/pack size, cost per piece, and price difference. |
| Same product, same supplier over time | Purchase dates, previous and new cost per piece, and change in pesos and percent. |
| Savings at a planned quantity | Planned quantity, supplier prices and their dates, estimated purchase totals, and difference. |
| Savings after additional costs | Purchase totals, owner-entered travel/delivery costs, and estimated savings after those costs. |
| Effect on selling profit | Previous/new purchase cost, chosen selling price, and estimated gross profit per piece. |
| Restock list comparison | Products, quantities, available supplier prices and their dates, totals, and missing price records. |

Keep these views distinct:

- **Latest recorded price per supplier:** The most recent purchase price at each supplier, even if the dates differ.
- **Price history:** Earlier and later purchases, including repeated purchases from the same supplier.
- **Lowest historical price:** The lowest price ever recorded, clearly labeled with its date rather than treated as the current price.

Optional short sentence summaries can accompany the tables if the offline model can produce them accurately from the displayed data. The tables remain useful on their own.

Every comparison should show its source and purchase date. **These are recorded purchase prices, not guaranteed current offers.** Missing supplier prices or unknown availability must remain visible.

For a restock list, account for the packs the owner actually needs to buy. Do not assume they can buy a fraction of a pack or automatically qualify for a bulk discount.

## 7. A simple example

These are hypothetical prices and dates for **the same Brand X Original Coffee 26g sachet**. The purchases happened on different days.

**Latest recorded purchase per supplier:**

| Supplier | Purchase date | Purchase | Amount paid | Cost per sachet |
| --- | --- | --- | --- | --- |
| A | 8 Oct 2026 | 2 packs × 10 sachets | ₱168 | ₱8.40 |
| B | 5 Oct 2026 | 1 pack × 10 sachets | ₱78 | ₱7.80 |
| C | 7 Oct 2026 | 1 pack × 10 sachets | ₱81 | ₱8.10 |

Supplier B has the lowest cost per sachet among these latest records, but its price was recorded earlier than A's.

**Price history at Supplier A:**

| Purchase date | Cost per sachet | Change from previous purchase |
| --- | --- | --- |
| 1 Oct 2026 | ₱8.00 | — |
| 8 Oct 2026 | ₱8.40 | +₱0.40 (+5%) |

The same supplier became more expensive on the next purchase. Both records stay available for comparison.

If those prices still apply, buying 100 sachets from B instead of A saves **₱60 before additional costs**. If the extra trip costs ₱30, the estimated saving becomes **₱30**.

But buying only 20 sachets saves ₱12 before travel. With the same ₱30 extra trip, B would cost ₱18 more overall. The planned quantity changes the decision.

## 8. Selling price and profit

The app should let owners choose a peso addition or a percentage markup, then show the resulting selling price and estimated gross profit per piece.

A DTI sari-sari store guide uses **20% markup as an assumption in its example business projection**. We can use that as a reference, but it is not evidence that every product should use a fixed 20% markup. The owner should be able to adjust it. [DTI sari-sari store guide](https://dtiwebfiles.s3.ap-southeast-1.amazonaws.com/wp-content/uploads/Starting-a-Business-Sari-Sari-Store.pdf)

For example, if the confirmed cost per piece is ₱8:

- Adding 20% markup gives a selling price of ₱9.60 and gross profit of ₱1.60 per piece.
- Choosing a selling price of ₱10 gives gross profit of ₱2 per piece.
- At ₱10, the markup is 25% of cost, while the gross margin is 20% of the selling price. These percentages are different.

The app should label the result **estimated gross profit**, because rent, electricity, losses, and other operating costs can reduce actual earnings. Owner-entered travel or delivery costs should also be included when calculating effective purchase cost.

Where applicable, DTI Suggested Retail Price references should be dated and checked separately from markup calculations. DTI also explains that price controls can apply during declared calamities or emergencies. [DTI price and supply monitoring](https://esigaw.dti.gov.ph/e-sigaw-services/e-konsyumer-corner/consumer-info-hub/price-and-supply-monitoring/)

**Purchase receipts alone cannot tell us actual sales, customer demand, or total business profit.** The app can compare recorded buying costs and pricing scenarios; it cannot guarantee maximum profit.

## 9. Why local AI matters

The intended core workflow runs on the owner's phone: receipt recognition, review, saving, and comparison.

- Owners can scan and compare while offline, once the required app and model assets are installed.
- Receipt images and purchasing records can stay on the device.
- Frequent scans can work without depending on a cloud AI call for each receipt.

This must be demonstrated with internet disabled. A cloud-only scanner followed by offline calculations would not prove the intended local AI feature.

## 10. A focused first version

For the 20-hour hackathon, prioritize three flows:

1. **Scan and confirm:** Extract useful details from a small set of real printed receipts.
2. **Compare:** Match a few identical products across at least two suppliers, include a repeated purchase at one supplier, and show dated tables for cost per piece and price history.
3. **Calculate:** Enter a planned quantity or selling price and see estimated savings or gross profit.

Full inventory management, sales tracking, demand forecasting, live supplier prices, ordering, and cross-brand recommendations can come later.

The biggest early question is whether scanning works well enough on the actual demo phone and receipts. Supported receipt types and correction effort should be tested before expanding the scope.

## 11. What we still need to discuss

- Can we interview a sari-sari store owner and collect receipts from two suppliers?
- Which few products should we use to prove the comparison?
- Do those receipts clearly show pack sizes and quantities?
- Does the owner care more about supplier comparison, restock planning, or selling-price calculations?
- What phone will we use, and how quickly can it process a receipt locally?

**Working pitch:** “Scan your receipts, see where the same stock costs less, and calculate your possible tubo—even without internet.”
