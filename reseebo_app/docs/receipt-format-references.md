# Receipt format references

Checked on **2026-10-09**. These references inform review and synthetic parser
cases. A sample does not establish a universal format across branches, POS
versions, dates, or payment methods.

## Evidence limits

Original source pages and document/body text were read. Receipt photo URLs were
found, but their pixels could not be inspected: image fetching failed and browser
tooling failed. Image-search generated descriptions were not accepted as verified
receipt text or layout. No photos were downloaded or bundled. No customer
identifiers, TINs, card details, or transaction identifiers are reproduced.
Synthetic fixtures remain labeled synthetic, rather than exact transcriptions.

## Philippine source catalog

| Store | Source and provenance | Confirmed evidence | Limitation |
| --- | --- | --- | --- |
| Puregold | [First-hand shopping post, 2026-07-20](https://note.com/norris_iloilo/n/n2f7474d537f5). Author identifies the Jaro branch and includes a receipt photo with cashier names removed. | The original Japanese caption describes a line break between product name and price, with the preceding price adjoining the next product name. The body says product names are abbreviated. These are author-described observations about this sample. | Photo pixels, exact OCR ordering, quantity syntax, and bounds were not verified. |
| Puregold | [User-uploaded blank sales invoice](https://www.scribd.com/document/855140498/Puregold-Price-Club-Inc), uploaded by kurtcaseria9. Extracted document body identifies Puregold Price Club Inc. and a Paniqui address. Publication date not established. | The document body contains item-table labels for quantity, unit, description, unit price, and amount, followed by separate tax, discount, and total fields. Buyer/date fields and item rows are blank. | A blank form, not a filled thermal grocery receipt. Scribd marks its title/summary AI-enhanced; only extracted document-body text was used. Positions and authenticity were not independently verified. |
| Savemore | [Same first-hand post, final receipt section, 2026-07-20](https://note.com/norris_iloilo/n/n2f7474d537f5). | Author identifies the receipt as Savemore while saying its heading reads FESTIVE MARKET. Its caption quotes `CHANGE PHP2.40`. This supports a candidate heading alias and treating change separately from product amounts. | Photo pixels, item layout, quantities, and bounds were not verified. |
| SM Hypermart | [First-hand travel/photo post, 2007-05-02](https://jeffwerner.ca/security_use_and_packaging/). Caption identifies SM Hypermart, Mall of Asia, Manila. [Linked photo](https://jeffwerner.ca/images/journal/CRW_6077.jpg). | Page supplies a first-hand photo source associated with that branch. | Image fetching failed. No item-row, quantity, tax, or price-layout claims are made. Sample is historical. |
| DALI | [First-hand shopping post, 2026-07-15](https://note.com/oyako_tagaytay/n/n929317daedad). Describes DALI shopping in Tagaytay and captions a shopping receipt. [Linked image](https://assets.st-note.com/img/1784096562-maF463kKzO8trWBhDMZdLSCJ.jpg?width=1200). | Original page identifies an actual purchase and supplies a receipt-photo reference. | Photo fetching failed. Author's separate item/price list does not verify printed row layout, quantity notation, or exact OCR text. |
| WalterMart | [First-hand receipt/price post, 2025-11-29](https://note.com/oyako_tagaytay/n/nef72d3b3ba84). Identifies WalterMart inside Ayala Mall in Tagaytay. [Linked image](https://assets.st-note.com/img/1764365664-VgTH7n8F5ytZoRY0m3MabuiW.jpg?width=1200). | Original post identifies the purchase and captions a shopping receipt. | Photo fetching failed. Prose mentions produce and loose rice, but printed weight, quantity, and price arrangements remain unverified. Image-search summaries were excluded. |
| Robinsons Supermarket | [Candidate app demonstration](https://grocerybudget.app/blog/scan-grocery-receipts-log-trips) describes an extracted Robinsons shopping trip. | Candidate for later source collection. | App extraction screenshot is not original receipt evidence. No chain-specific fixture or native format claim is grounded in this source. No visually verified original receipt was obtained. |
| Wellbest | Searches included the exact name with receipt, resibo, and grocery terms. | No usable original grocery receipt sample found during this check. | Unrelated wellness shops, import manifests, and corporate/payment records do not support grocery item-row layout. This is a collection gap, not proof that public samples do not exist. |

## Grounded parser implications

These are test suggestions derived from evidence, not additional source facts:

- Test a product name followed by a separate amount line, including a following
  product beginning close to that amount. The Puregold author's description
  supports this ambiguity. Synthetic geometry is not measured photo geometry.
- Preserve abbreviated names for review rather than inventing brands, variants,
  or sizes.
- Store-heading aliases require evidence; FESTIVE MARKET is an author-described
  Savemore example. No automatic store alias has been added by this research.
- Keep change, tax breakdowns, discounts, and totals separate from product rows.
  The Savemore caption and blank invoice body support these field roles.
- Distinguish quantity, unit price, and row amount in a labeled table. Derive
  positions from current OCR evidence, not guessed chain-wide coordinates.

Three `source_*` synthetic fixtures use the Puregold author's line-break
description, with invented item names, amounts, and bounds. No store-specific
values, confidence, or exact row grammar were inferred from inaccessible photos.

## Separate benchmark reference

The [ICDAR 2019 SROIE official task page](https://rrc-red.cvc.uab.es/?ch=13&com=tasks)
describes scanned receipt text boxes/transcripts and key-information extraction.
The [organizers' paper](https://arxiv.org/abs/2103.10213) is the primary technical
reference. This is a separate benchmark, not evidence of Philippine chain
formats or current item-level accuracy. No benchmark data was imported.

## Further validation

Collect several consented original receipts per chain spanning branches, dates,
count/weight purchases, discounts, and long-receipt capture. Inspect actual pixels
before recording grammar, then pair sanitized OCR lines/tokens with expected rows
and unresolved fields. Synthetic checks do not replace real-device first-launch
offline OCR and persistence verification. See [validation notes](receipt_ocr_validation.md).
