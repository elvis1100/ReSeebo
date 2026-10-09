"""Local PP-OCRv5 experiment; never runs in the app or calls cloud OCR.

Install rapidocr==3.10.0 and onnxruntime in an isolated Python environment.
Models download on the first experimental run. Images stay on this machine.
Outputs contain receipt data: use a directory outside source control.
"""

import argparse
import hashlib
import importlib.metadata
import json
from pathlib import Path
import time

from rapidocr import LangDet, LangRec, ModelType, OCRVersion, RapidOCR


def bounds(box):
    xs, ys = zip(*box)
    return dict(left=float(min(xs)), top=float(min(ys)),
                width=float(max(xs) - min(xs)), height=float(max(ys) - min(ys)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if len({image.stem for image in args.images}) != len(args.images):
        parser.error("Image stems must be unique within one run")
    args.output.mkdir(parents=True, exist_ok=True)
    for image in args.images:
        if not image.is_file():
            parser.error(f"Missing image: {image}")
        if (args.output / f"{image.stem}.json").exists():
            parser.error("Capture already exists; choose a new output directory")
    engine = RapidOCR(params={
        "Det.lang_type": LangDet.CH,
        "Det.model_type": ModelType.MOBILE,
        "Det.ocr_version": OCRVersion.PPOCRV5,
        "Rec.lang_type": LangRec.EN,
        "Rec.model_type": ModelType.MOBILE,
        "Rec.ocr_version": OCRVersion.PPOCRV5,
        "Global.model_root_dir": str(args.output / "models"),
        "Global.return_word_box": True,
        "EngineConfig.onnxruntime.intra_op_num_threads": 2,
        "EngineConfig.onnxruntime.inter_op_num_threads": 2,
    })
    models = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
              for p in (args.output / "models").glob("*.onnx")}
    for image in args.images:
        started = time.perf_counter()
        result = engine(str(image))
        elapsed = time.perf_counter() - started
        lines = []
        if result.txts is not None:
            if len(result.txts) != len(result.boxes) or len(result.txts) != len(result.scores):
                raise ValueError("OCR returned inconsistent text/box/score counts")
            for i, (text, box, score) in enumerate(zip(result.txts, result.boxes, result.scores)):
                words = result.word_results[i] if result.word_results else []
                tokens = [dict(text=word[0], **bounds(word[2])) for word in words]
                lines.append(dict(text=text, confidence=float(score), tokens=tokens, **bounds(box)))
        record = {
            "id": image.stem,
            "provenance": "Local desktop CPU PP-OCRv5 mobile via RapidOCR/ONNX; not Android verification",
            "rapidocrVersion": importlib.metadata.version("rapidocr"),
            "onnxruntimeVersion": importlib.metadata.version("onnxruntime"),
            "imageSha256": hashlib.sha256(image.read_bytes()).hexdigest(),
            "modelSha256": models,
            "elapsedSeconds": elapsed,
            "lines": lines,
        }
        target = args.output / f"{image.stem}.json"
        with target.open("x") as output:
            output.write(json.dumps(record, indent=2) + "\n")
        print(f"{image.stem}: {len(lines)} OCR lines, {elapsed:.2f}s -> {target}")


if __name__ == "__main__":
    main()
