# Synthetic receipt OCR fixtures

These JSON files contain invented OCR text and bounds, with hand-checked expected
draft fields. They are parser regressions, not captured receipt images or actual
ML Kit output. No real receipt photos or OCR captures were supplied for this work.

Each fixture has a `synthetic` flag, a behavior-focused `name`, `lines` containing
OCR text/bounds, and `expected` purchase date and item suggestions. Null fields
mean the owner must supply or resolve that value. All results remain unconfirmed.
Bounds use arbitrary image pixels; skew fixtures model modest baseline drift and
adjacent rows. These tests do not measure camera accuracy or offline device OCR.

The `source_*` cases are synthetic examples inspired by the author's description
of Puregold product names and prices on separate lines in this
[first-hand post](https://note.com/norris_iloilo/n/n2f7474d537f5).
The examples use invented names, prices, and OCR order; we did not verify the
post's photos or token geometry. Their literal expected values test conservative
adjacency, subtotal barriers, and adjacent product separation. They are not a
claim about a retailer's universal layout or actual ML Kit output.
