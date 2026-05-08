#!/usr/bin/env python3
"""Create an augmented ClothIQ ML training dataset from real captured samples.

The source samples remain intact. Augmented samples are explicitly marked with
`isAugmented` and `sourceSampleID` so readiness reports can distinguish real
captures from derived training examples.
"""

from __future__ import annotations

import argparse
import base64
import json
import uuid
from io import BytesIO
from pathlib import Path
from typing import Any

from PIL import Image, ImageEnhance, ImageOps


LEFT_RIGHT_IDENTIFIER_PAIRS = {
    "left_shoulder": "right_shoulder",
    "right_shoulder": "left_shoulder",
    "left_armpit": "right_armpit",
    "right_armpit": "left_armpit",
    "left_sleeve": "right_sleeve",
    "right_sleeve": "left_sleeve",
    "chest_left": "chest_right",
    "chest_right": "chest_left",
    "waist_left": "waist_right",
    "waist_right": "waist_left",
    "hip_left": "hip_right",
    "hip_right": "hip_left",
    "hem_left": "hem_right",
    "hem_right": "hem_left",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate marked augmented labels.json from ClothIQ training samples."
    )
    parser.add_argument("--input", required=True, help="Input labels.json")
    parser.add_argument("--output-dir", required=True, help="Output training data directory")
    parser.add_argument(
        "--target-per-type",
        type=int,
        default=20,
        help="Minimum total samples per clothing type after augmentation.",
    )
    parser.add_argument(
        "--jpeg-quality",
        type=int,
        default=86,
        help="JPEG quality for augmented imageData.",
    )
    return parser.parse_args()


def decode_image(sample: dict[str, Any]) -> Image.Image:
    image_data = base64.b64decode(sample["imageData"])
    return Image.open(BytesIO(image_data)).convert("RGB")


def encode_image(image: Image.Image, quality: int) -> str:
    buffer = BytesIO()
    image.save(buffer, format="JPEG", quality=quality, optimize=True)
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def clone_sample(sample: dict[str, Any]) -> dict[str, Any]:
    return json.loads(json.dumps(sample))


def augmented_id(source_id: str, variant_name: str, variant_index: int) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"clothiq-aug:{source_id}:{variant_name}:{variant_index}")).upper()


def flip_keypoints(keypoints: list[dict[str, Any]]) -> list[dict[str, Any]]:
    flipped: list[dict[str, Any]] = []
    for keypoint in keypoints:
        updated = dict(keypoint)
        identifier = updated.get("identifier")
        if identifier in LEFT_RIGHT_IDENTIFIER_PAIRS:
            updated["identifier"] = LEFT_RIGHT_IDENTIFIER_PAIRS[identifier]
        if isinstance(updated.get("x"), (int, float)):
            updated["x"] = round(1.0 - float(updated["x"]), 7)
        flipped.append(updated)
    return flipped


def variant_image(image: Image.Image, name: str) -> Image.Image:
    if name == "flip":
        return ImageOps.mirror(image)
    if name == "bright_up":
        return ImageEnhance.Brightness(image).enhance(1.16)
    if name == "bright_down":
        return ImageEnhance.Brightness(image).enhance(0.86)
    if name == "contrast_up":
        return ImageEnhance.Contrast(image).enhance(1.18)
    if name == "contrast_down":
        return ImageEnhance.Contrast(image).enhance(0.88)
    if name == "flip_bright":
        return ImageEnhance.Brightness(ImageOps.mirror(image)).enhance(1.10)
    if name == "flip_contrast":
        return ImageEnhance.Contrast(ImageOps.mirror(image)).enhance(1.12)
    return image.copy()


def variant_keypoints(sample: dict[str, Any], name: str) -> list[dict[str, Any]]:
    keypoints = sample.get("keypoints") or []
    if name.startswith("flip"):
        return flip_keypoints(keypoints)
    return clone_sample({"keypoints": keypoints})["keypoints"]


def make_augmented_sample(
    sample: dict[str, Any],
    variant_name: str,
    variant_index: int,
    quality: int,
) -> dict[str, Any]:
    image = decode_image(sample)
    augmented = clone_sample(sample)
    augmented["id"] = augmented_id(str(sample.get("id", "")), variant_name, variant_index)
    augmented["imageData"] = encode_image(variant_image(image, variant_name), quality)
    augmented["keypoints"] = variant_keypoints(sample, variant_name)
    augmented["isAugmented"] = True
    augmented["sourceSampleID"] = str(sample.get("id", ""))
    augmented["augmentation"] = {"variant": variant_name, "index": variant_index}
    augmented["confidence"] = min(float(sample.get("confidence", 0.8)), 0.82)
    return augmented


def dedupe_by_id(samples: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    deduped: list[dict[str, Any]] = []
    for sample in samples:
        sample_id = str(sample.get("id", ""))
        if sample_id in seen:
            continue
        seen.add(sample_id)
        deduped.append(sample)
    return deduped


def main() -> int:
    args = parse_args()
    input_file = Path(args.input)
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    with input_file.open("r", encoding="utf-8") as handle:
        source_samples = json.load(handle)

    samples = dedupe_by_id(source_samples)
    by_type: dict[str, list[dict[str, Any]]] = {}
    for sample in samples:
        clothing_type = sample.get("clothingType")
        if isinstance(clothing_type, str) and clothing_type:
            by_type.setdefault(clothing_type, []).append(sample)

    variants = [
        "flip",
        "bright_up",
        "bright_down",
        "contrast_up",
        "contrast_down",
        "flip_bright",
        "flip_contrast",
    ]

    augmented_samples: list[dict[str, Any]] = []
    for clothing_type, type_samples in sorted(by_type.items()):
        needed = max(0, args.target_per_type - len(type_samples))
        variant_index = 0
        for index in range(needed):
            source = type_samples[index % len(type_samples)]
            variant_name = variants[(index // len(type_samples)) % len(variants)]
            augmented_samples.append(make_augmented_sample(source, variant_name, variant_index, args.jpeg_quality))
            variant_index += 1

    output_samples = dedupe_by_id(samples + augmented_samples)
    output_file = output_dir / "labels.json"
    with output_file.open("w", encoding="utf-8") as handle:
        json.dump(output_samples, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"source_samples={len(samples)}")
    print(f"augmented_samples={len(augmented_samples)}")
    print(f"output_samples={len(output_samples)}")
    for clothing_type in sorted(by_type):
        total = sum(1 for sample in output_samples if sample.get("clothingType") == clothing_type)
        augmented = sum(
            1
            for sample in output_samples
            if sample.get("clothingType") == clothing_type and sample.get("isAugmented") is True
        )
        print(f"{clothing_type}=total:{total},original:{total - augmented},augmented:{augmented}")
    print(f"output={output_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
