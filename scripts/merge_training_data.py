#!/usr/bin/env python3
"""Merge ClothIQ MLTrainingData directories into one training dataset."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from collections import Counter
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Merge multiple ClothIQ MLTrainingData directories."
    )
    parser.add_argument(
        "--input",
        action="append",
        required=True,
        help="Input MLTrainingData directory containing labels.json. May be repeated.",
    )
    parser.add_argument("--output-dir", required=True, help="Merged output directory.")
    parser.add_argument(
        "--skip-images",
        action="store_true",
        help="Do not copy images/ directories. labels.json imageData is still preserved.",
    )
    return parser.parse_args()


def load_labels(data_dir: Path) -> list[dict[str, Any]]:
    labels_path = data_dir / "labels.json"
    if not labels_path.exists():
        raise FileNotFoundError(f"labels.json not found: {labels_path}")

    with labels_path.open("r", encoding="utf-8") as handle:
        labels = json.load(handle)
    if not isinstance(labels, list):
        raise ValueError(f"labels.json must contain a list: {labels_path}")
    return labels


def sample_key(sample: dict[str, Any]) -> str:
    sample_id = sample.get("id")
    if isinstance(sample_id, str) and sample_id:
        return f"id:{sample_id}"

    signature = {
        "clothingType": sample.get("clothingType"),
        "timestamp": sample.get("timestamp"),
        "imageHash": hashlib.sha256(
            str(sample.get("imageData", "")).encode("utf-8")
        ).hexdigest(),
        "keypoints": sample.get("keypoints") or [],
        "isUserCorrected": sample.get("isUserCorrected"),
    }
    encoded = json.dumps(signature, sort_keys=True, separators=(",", ":"))
    return "signature:" + hashlib.sha256(encoded.encode("utf-8")).hexdigest()


def copy_images(input_dir: Path, output_dir: Path) -> tuple[int, int]:
    source_images = input_dir / "images"
    if not source_images.is_dir():
        return 0, 0

    destination_images = output_dir / "images"
    destination_images.mkdir(parents=True, exist_ok=True)

    copied = 0
    skipped = 0
    for source_file in sorted(path for path in source_images.iterdir() if path.is_file()):
        destination_file = destination_images / source_file.name
        if destination_file.exists():
            if (
                destination_file.stat().st_size == source_file.stat().st_size
                and destination_file.read_bytes() == source_file.read_bytes()
            ):
                skipped += 1
                continue

            stem = source_file.stem
            suffix = source_file.suffix
            source_hash = hashlib.sha256(source_file.read_bytes()).hexdigest()[:10]
            destination_file = destination_images / f"{stem}-{source_hash}{suffix}"

        shutil.copy2(source_file, destination_file)
        copied += 1

    return copied, skipped


def main() -> int:
    args = parse_args()
    input_dirs = [Path(item) for item in args.input]
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    merged: list[dict[str, Any]] = []
    seen: set[str] = set()
    input_counts: list[tuple[Path, int, int]] = []
    duplicate_count = 0
    copied_images = 0
    skipped_images = 0

    for input_dir in input_dirs:
        labels = load_labels(input_dir)
        added = 0
        for sample in labels:
            key = sample_key(sample)
            if key in seen:
                duplicate_count += 1
                continue
            seen.add(key)
            merged.append(sample)
            added += 1

        input_counts.append((input_dir, len(labels), added))

        if not args.skip_images:
            copied, skipped = copy_images(input_dir, output_dir)
            copied_images += copied
            skipped_images += skipped

    output_file = output_dir / "labels.json"
    with output_file.open("w", encoding="utf-8") as handle:
        json.dump(merged, handle, ensure_ascii=False, indent=2)

    type_counts = Counter(sample.get("clothingType", "unknown") for sample in merged)
    corrected_counts = Counter(
        sample.get("clothingType", "unknown")
        for sample in merged
        if sample.get("isUserCorrected") is True
    )
    augmented_count = sum(
        1
        for sample in merged
        if sample.get("isAugmented") is True or bool(sample.get("sourceSampleID"))
    )

    print("ClothIQ MLTrainingData merge")
    for input_dir, total, added in input_counts:
        print(f"- input: {input_dir} labels={total} added={added}")
    print(f"- duplicates skipped: {duplicate_count}")
    print(f"- output labels: {output_file}")
    print(f"- merged samples: {len(merged)}")
    print(f"- augmented samples: {augmented_count}")
    if not args.skip_images:
        print(f"- images copied: {copied_images}, skipped: {skipped_images}")
    print("- clothing types:")
    for clothing_type, count in sorted(type_counts.items()):
        print(f"  - {clothing_type}: {count} (corrected={corrected_counts[clothing_type]})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
