"""Local PP-OCR model experiment; never runs in the app or calls cloud OCR.

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
    parser.add_argument("--ocr-version", choices=["5", "6"], default="5")
    parser.add_argument("--model-type", choices=["mobile", "server", "tiny", "small", "medium"], default="mobile")
    args = parser.parse_args()
    if len({image.stem for image in args.images}) != len(args.images):
        parser.error("Image stems must be unique within one run")
    allowed = {"5": {"mobile", "server"}, "6": {"tiny", "small", "medium"}}
    if args.model_type not in allowed[args.ocr_version]:
        parser.error("Choose mobile/server for v5 or tiny/small/medium for v6")
    version = OCRVersion.PPOCRV6 if args.ocr_version == "6" else OCRVersion.PPOCRV5
    model_type = ModelType(args.model_type)
    args.output.mkdir(parents=True, exist_ok=True)
    for image in args.images:
        if not image.is_file():
            parser.error(f"Missing image: {image}")
        if (args.output / f"{image.stem}.json").exists():
            parser.error("Capture already exists; choose a new output directory")
    engine = RapidOCR(params={
        "Det.lang_type": LangDet.EN if args.ocr_version == "6" else LangDet.CH,
        "Det.model_type": model_type,
        "Det.ocr_version": version,
        "Rec.lang_type": LangRec.EN,
        "Rec.model_type": model_type,
        "Rec.ocr_version": version,
        "Global.model_root_dir": str(args.output / "models"),
        "Global.return_word_box": True,
        "EngineConfig.onnxruntime.intra_op_num_threads": 2,
        "EngineConfig.onnxruntime.inter_op_num_threads": 2,
    })
    for image in args.images:
        started = time.perf_counter()
        result = engine(str(image))
        elapsed = time.perf_counter() - started
        models = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in (args.output / "models").glob("*.onnx")}
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
            "provenance": f"Local desktop CPU PP-OCRv{args.ocr_version} {args.model_type} via RapidOCR/ONNX; not Android verification",
            "ocrVersion": version.value,
            "modelType": args.model_type,
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
