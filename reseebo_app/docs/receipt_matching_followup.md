# Offline abbreviation matching and OCR comparison

Receipt names can now match catalog names without identical spelling. Complete
shortened identities support prefixes, consonant abbreviations, consecutive
brand initials such as BB, joined words, and one-character errors in longer
words. Automatic selection requires a unique candidate and matching printed
size; missing variants, competing identities, conflicting sizes and extra
numeric identity evidence remain unresolved. Partial matches rank as suggestions.

Controlled examples using the same catalog before and after:

| Receipt description | Saved product | Old exact matcher | New matcher |
| --- | --- | --- | --- |
| BB FORT MILK33G | Bear Brand Fortified Milk, 33g | No match | Selected |
| TangPwdrMango19g | Tang Powder Mango, 19g | No match | Selected |

These are controlled matching tests, not proof that OCR reads those strings from
an arbitrary photo. Public downloaded receipt OCR replay against the bundled
265-product catalog currently yields zero automatic product matches for DALI,
WalterMart and Savemore. Several printed variants and package sizes are absent
from that catalog; no nearby size or flavor is substituted. Real catalog
coverage and owner-confirmed mappings remain necessary for those receipts.

SQLite migration 007 learns confirmed descriptions per saved supplier/branch.
Future scans at that supplier can select a unique learned mapping. The same
shortened name at another supplier cannot silently reuse that mapping. Existing
global aliases are preserved as suggestions. Alias management can remove both
legacy and scoped entries; receipts and purchase history remain intact.

When enhancement is used, the app reads both the selected enhanced image and
its unenhanced crop/rotation. Each pass keeps its own word coordinates. The
selected crop remains authoritative: extra original-only products are never
added, and dates/totals are not replaced from another image. A missing quantity
or amount can be filled only for a unique identical normalized description with
compatible other fields; conflicting readings and inconsistent arithmetic stay
for review. Original comparison evidence is retained separately in the draft.
Owner edits and confirmed lines cannot be overwritten.

Public raw/enhanced OCR replay showed no additional populated quantity or cost
fields from this conservative comparison. It does detect contradictory readings
and can recover missing fields in synthetic tests. This is not a claim of
improved cost accuracy on every public sample. Catalog prices never replace
printed receipt costs, and unreadable digits are not reconstructed to balance
receipt totals.

Local validation: the full suite passed 266 tests; final analysis was clean.
The additional catalog evaluation tests passed separately. Relevant checks cover
abbreviations, counted sizes, wrong sizes, extra digits, competing variants,
supplier isolation, migration preservation, repeated OCR descriptions, crop
boundaries, inconsistent prices and owner edits.

Android verification also passed the actual adapter pipeline with internet
disabled across all six downloaded images. Populated suggestions were DALI:
10 rows / 5 quantities / 6 amounts; WalterMart: 19 / 1 / 19; Savemore: 6 / 6 / 6;
POS demonstration: 3 / 3 / 2. Puregold and the tiny SM photo remained unreadable.
Both OCR passes retained separate evidence. Counts are completeness measures,
not accuracy percentages. The two native tests passed. A separate restart check
verifies supplier-scoped alias persistence as well as receipt/category history.

Parallel review corrected an unsupported suggestion label: token coverage alone
no longer claims that size agrees. One-character tolerance in longer names is
still a heuristic; a missing catalog variant can look like a spelling error.
Automatic matches remain unconfirmed, and the owner must check the saved item.

The separate offline restart test passed, including branch-scoped learned aliases
and rejection of the mapping for another supplier. Phone connectivity was
restored. Parallel review additionally found and fixed retaining a confirmed
supplier-derived match after changing supplier; those selections now lose their
confirmation and are recalculated. Seven focused state tests passed after this
fix, alongside the separately passing ten matcher/evaluation tests.
