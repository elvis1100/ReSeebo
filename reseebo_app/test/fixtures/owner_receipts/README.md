# Owner receipt OCR evidence

These are uncorrected captures of the owner's exact Wellbest and DALI photos,
not the different downloaded public DALI sample. Original photos are not included.

- `user_wellbest`: owner file `20261009_201745.jpg`.
- `user_dali`: owner file `20261009_201820.jpg`.
- `mlkit`: bundled Latin recognizer on Samsung SM-A576B, Android 16.
- `ppocr`: local desktop PP-OCRv5 mobile detection/English recognition through
  RapidOCR 3.10.0, ONNX Runtime 1.31.0, PP-OCRv4 orientation classifier.
- `original`: unchanged source photo bytes.
- `enhanced`: the exact locally enhanced pixels exported by the Android capture
  harness; both engines saw identical enhanced pixels.

Only the supplier header and manually selected item/total region are retained.
Customer, transaction, payment, tax, and footer identifiers are excluded. Text,
tokens, bounds, and reading order within the retained region are uncorrected.
The complete captures remain under /tmp. Replay confirmed that every sanitized
capture produces exactly the same suggestions and scores as its full capture.

Hashes identify the original/recognized images and alternative model weights.
ML Kit captures include original-source and recognized-image hashes; PP-OCR
records identify the actual recognized pixels. Descriptions and economic truth
were manually read before inspecting OCR in `../grocery_benchmark/*_truth.json`.

These fixtures intentionally include failures. They measure the current system;
they must not be rewritten to make the benchmark pass. Eight captures represent
two receipts, not eight independent samples. Native test success establishes
capture execution, not correct extraction. Desktop PP-OCR is not Android proof.
