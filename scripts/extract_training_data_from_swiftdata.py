#!/usr/bin/env python3
"""Recover ML training labels from a ClothIQ SwiftData store.

The app stores photo measurement anchors as top-left-origin normalized image
coordinates. Training labels use Vision normalized coordinates, where Y=0 is the
bottom edge. This script converts saved photo measurements back into training
keypoint labels and embeds the corresponding image as base64 JPEG data.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import sqlite3
import sys
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone, timedelta
from pathlib import Path
from typing import Iterable


BOTTOM_TYPES = {"shorts", "pants", "jeans", "leggings", "skirt"}
PANTS_LIKE_TYPES = {"shorts", "pants", "jeans"}

ALLOWED_MEASUREMENTS_BY_CLOTHING_TYPE = {
    "short_sleeve": {"shoulder_width", "chest_circumference", "total_length", "sleeve_length"},
    "long_sleeve": {
        "shoulder_width",
        "chest_circumference",
        "total_length",
        "sleeve_length",
        "arm_circumference",
    },
    "shirt": {
        "shoulder_width",
        "chest_circumference",
        "total_length",
        "sleeve_length",
        "neck_circumference",
    },
    "polo": {"shoulder_width", "chest_circumference", "total_length", "sleeve_length"},
    "jacket": {
        "shoulder_width",
        "chest_circumference",
        "total_length",
        "sleeve_length",
        "cuff_circumference",
    },
    "coat": {"shoulder_width", "chest_circumference", "total_length", "sleeve_length"},
    "vest": {"shoulder_width", "chest_circumference", "total_length"},
    "cardigan": {"shoulder_width", "chest_circumference", "total_length", "sleeve_length"},
    "hoodie": {"shoulder_width", "chest_circumference", "total_length", "sleeve_length"},
    "dress": {
        "shoulder_width",
        "chest_circumference",
        "total_length",
        "waist_circumference",
        "hip_circumference",
    },
    "jumpsuit": {
        "shoulder_width",
        "chest_circumference",
        "total_length",
        "waist_circumference",
        "hip_circumference",
        "rise",
    },
    "shorts": {"waist_circumference", "total_length", "rise", "hem"},
    "pants": {"waist_circumference", "total_length", "rise", "hem", "thigh_circumference"},
    "jeans": {"waist_circumference", "total_length", "rise", "hem", "thigh_circumference"},
    "skirt": {"waist_circumference", "total_length"},
    "leggings": {"waist_circumference", "total_length", "hip_circumference"},
}

COCOA_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)


@dataclass(frozen=True)
class MeasurementRow:
    item_pk: int
    measurement_pk: int
    clothing_type: str
    image_path: str
    measured_at: float | None
    confidence: float
    measurement_type: str
    start_x: float
    start_y: float
    end_x: float
    end_y: float


@dataclass(frozen=True)
class KeypointCandidate:
    identifier: str
    x: float
    y: float
    visibility: float
    confidence: float
    priority: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract ClothIQ ML training labels from a SwiftData default.store."
    )
    parser.add_argument("--store", required=True, help="Path to SwiftData default.store")
    parser.add_argument(
        "--documents-dir",
        help="App Documents directory. Defaults to a sibling Documents directory when possible.",
    )
    parser.add_argument("--output-dir", required=True, help="Directory to write labels.json")
    parser.add_argument(
        "--merge-labels",
        action="append",
        default=[],
        help="Existing labels.json to include before recovered samples. May be repeated.",
    )
    parser.add_argument(
        "--min-keypoints",
        type=int,
        default=2,
        help="Minimum visible labels required to emit a recovered sample.",
    )
    return parser.parse_args()


def infer_documents_dir(store: Path) -> Path:
    if store.parent.name == "Application Support":
        return store.parent.parent / "Documents"

    sibling = store.parent / "Documents"
    if sibling.is_dir():
        return sibling

    return store.parent


def load_rows(store: Path) -> list[MeasurementRow]:
    query = """
        select
            i.Z_PK,
            m.Z_PK,
            i.ZTYPE,
            i.ZIMAGEPATH,
            m.ZMEASUREDAT,
            coalesce(m.ZCONFIDENCE, 1.0),
            m.ZTYPE,
            m.ZSTARTPOINTX,
            m.ZSTARTPOINTY,
            m.ZENDPOINTX,
            m.ZENDPOINTY
        from ZMEASUREMENTMODEL m
        join ZCLOTHINGITEMMODEL i on m.ZCLOTHINGITEM = i.Z_PK
        where i.ZTYPE is not null
          and i.ZIMAGEPATH is not null
          and m.ZTYPE is not null
          and m.ZSTARTPOINTX is not null
          and m.ZSTARTPOINTY is not null
          and m.ZENDPOINTX is not null
          and m.ZENDPOINTY is not null
        order by i.Z_PK, m.ZTYPE, m.ZMEASUREDAT desc, m.Z_PK desc
    """
    with sqlite3.connect(store) as connection:
        rows = connection.execute(query).fetchall()

    return [
        MeasurementRow(
            item_pk=int(row[0]),
            measurement_pk=int(row[1]),
            clothing_type=str(row[2]),
            image_path=str(row[3]),
            measured_at=float(row[4]) if row[4] is not None else None,
            confidence=float(row[5]),
            measurement_type=str(row[6]),
            start_x=float(row[7]),
            start_y=float(row[8]),
            end_x=float(row[9]),
            end_y=float(row[10]),
        )
        for row in rows
    ]


def clamp_unit(value: float) -> float:
    return min(max(value, 0.0), 1.0)


def to_vision_point(x: float, y: float) -> tuple[float, float]:
    return clamp_unit(x), clamp_unit(1.0 - y)


def average_point(points: Iterable[tuple[float, float]]) -> tuple[float, float]:
    point_list = list(points)
    return (
        sum(point[0] for point in point_list) / len(point_list),
        sum(point[1] for point in point_list) / len(point_list),
    )


def side_prefix(x: float) -> str:
    return "left" if x <= 0.5 else "right"


def candidate(
    identifier: str,
    point: tuple[float, float],
    confidence: float,
    priority: int,
) -> KeypointCandidate:
    return KeypointCandidate(
        identifier=identifier,
        x=clamp_unit(point[0]),
        y=clamp_unit(point[1]),
        visibility=1.0 if confidence > 0.0 else 0.0,
        confidence=confidence,
        priority=priority,
    )


def measurement_to_keypoints(row: MeasurementRow) -> list[KeypointCandidate]:
    allowed_measurements = ALLOWED_MEASUREMENTS_BY_CLOTHING_TYPE.get(row.clothing_type)
    if allowed_measurements is not None and row.measurement_type not in allowed_measurements:
        return []

    start = to_vision_point(row.start_x, row.start_y)
    end = to_vision_point(row.end_x, row.end_y)
    center = average_point([start, end])
    confidence = clamp_unit(row.confidence)
    measurement_type = row.measurement_type
    clothing_type = row.clothing_type

    if measurement_type == "shoulder_width":
        return [
            candidate("left_shoulder", start, confidence, 80),
            candidate("right_shoulder", end, confidence, 80),
        ]

    if measurement_type == "chest_circumference":
        return [
            candidate("chest_left", start, confidence, 80),
            candidate("chest_right", end, confidence, 80),
        ]

    if measurement_type == "sleeve_length":
        return [
            candidate("left_shoulder", start, confidence, 55),
            candidate("left_sleeve", end, confidence, 55),
        ]

    if measurement_type in {"arm_circumference", "cuff_circumference"}:
        return [
            candidate("left_sleeve", start, confidence, 60),
            candidate("right_sleeve", end, confidence, 60),
        ]

    if measurement_type == "neck_circumference":
        return [
            candidate("left_shoulder", start, confidence, 55),
            candidate("right_shoulder", end, confidence, 55),
            candidate("neckline", center, confidence, 65),
        ]

    if measurement_type == "waist_circumference":
        return [
            candidate("waist_left", start, confidence, 90),
            candidate("waist_right", end, confidence, 90),
        ]

    if measurement_type == "hip_circumference":
        return [
            candidate("hip_left", start, confidence, 90),
            candidate("hip_right", end, confidence, 90),
        ]

    if measurement_type == "rise":
        # The line start is often a vertical projection from the waist, so keep
        # waist labels from the explicit waist measurement when it exists.
        return [
            candidate("crotch", end, confidence, 75),
        ]

    if measurement_type == "hem":
        if clothing_type in PANTS_LIKE_TYPES:
            return [
                candidate("hem_left", start, confidence, 95),
                candidate("hem_right", end, confidence, 95),
                candidate("hem_center", center, confidence, 85),
            ]
        return [
            candidate("hem_center", center, confidence, 90),
        ]

    if measurement_type == "thigh_circumference":
        return [
            candidate("hip_left", start, confidence, 45),
            candidate("hip_right", end, confidence, 45),
            candidate("crotch", center, confidence, 45),
        ]

    if measurement_type == "total_length":
        if clothing_type in BOTTOM_TYPES:
            waist_identifier = f"{side_prefix(row.start_x)}_waist"
            # Match app training identifiers, not enum case spelling.
            waist_identifier = "waist_left" if waist_identifier == "left_waist" else "waist_right"
            labels = [candidate(waist_identifier, start, confidence, 50)]
            if clothing_type not in PANTS_LIKE_TYPES:
                labels.append(candidate("hem_center", end, confidence, 50))
            return labels

        return [
            candidate("neckline", start, confidence, 60),
            candidate("hem_center", end, confidence, 60),
        ]

    return []


def measurement_row_preference(row: MeasurementRow) -> tuple[float, float, int]:
    measured_at = row.measured_at if row.measured_at is not None else float("-inf")
    return (measured_at, clamp_unit(row.confidence), row.measurement_pk)


def preferred_measurement_rows(rows: list[MeasurementRow]) -> list[MeasurementRow]:
    best_by_type: dict[str, MeasurementRow] = {}
    for row in rows:
        existing = best_by_type.get(row.measurement_type)
        if existing is None or measurement_row_preference(row) > measurement_row_preference(existing):
            best_by_type[row.measurement_type] = row

    return list(best_by_type.values())


def merged_keypoints(rows: list[MeasurementRow]) -> list[dict[str, float | str]]:
    best_by_identifier: dict[str, KeypointCandidate] = {}
    for row in preferred_measurement_rows(rows):
        for keypoint in measurement_to_keypoints(row):
            existing = best_by_identifier.get(keypoint.identifier)
            if existing is None:
                best_by_identifier[keypoint.identifier] = keypoint
                continue

            new_score = (keypoint.priority, keypoint.confidence)
            existing_score = (existing.priority, existing.confidence)
            if new_score > existing_score:
                best_by_identifier[keypoint.identifier] = keypoint

    return [
        {
            "identifier": keypoint.identifier,
            "x": round(keypoint.x, 7),
            "y": round(keypoint.y, 7),
            "visibility": keypoint.visibility,
        }
        for keypoint in sorted(best_by_identifier.values(), key=lambda item: item.identifier)
    ]


def swift_timestamp_to_iso(value: float | None) -> str:
    if value is None:
        return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    timestamp = COCOA_EPOCH + timedelta(seconds=value)
    return timestamp.replace(microsecond=0).isoformat().replace("+00:00", "Z")


def image_data(documents_dir: Path, image_path: str) -> str | None:
    resolved = documents_dir / image_path
    if not resolved.is_file():
        return None

    return base64.b64encode(resolved.read_bytes()).decode("ascii")


def stable_sample_id(clothing_type: str, encoded_image: str) -> str:
    image_hash = hashlib.sha256(base64.b64decode(encoded_image)).hexdigest()
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"clothiq:{clothing_type}:{image_hash}")).upper()


def recovered_samples(store: Path, documents_dir: Path, rows: list[MeasurementRow], min_keypoints: int) -> list[dict]:
    rows_by_item: dict[int, list[MeasurementRow]] = {}
    for row in rows:
        rows_by_item.setdefault(row.item_pk, []).append(row)

    samples: list[dict] = []
    for item_pk, item_rows in sorted(rows_by_item.items()):
        first = item_rows[0]
        encoded_image = image_data(documents_dir, first.image_path)
        if not encoded_image:
            print(f"[WARN] 이미지 파일을 찾을 수 없어 건너뜀: {first.image_path}", file=sys.stderr)
            continue

        preferred_rows = preferred_measurement_rows(item_rows)
        keypoints = merged_keypoints(preferred_rows)
        visible_count = sum(1 for keypoint in keypoints if keypoint["visibility"] >= 0.5)
        if visible_count < min_keypoints:
            print(f"[WARN] 키포인트 부족으로 건너뜀: item {item_pk}", file=sys.stderr)
            continue

        average_confidence = sum(row.confidence for row in preferred_rows) / len(preferred_rows)
        latest_row = max(preferred_rows, key=measurement_row_preference)
        samples.append(
            {
                "id": stable_sample_id(first.clothing_type, encoded_image),
                "imageData": encoded_image,
                "clothingType": first.clothing_type,
                "keypoints": keypoints,
                "timestamp": swift_timestamp_to_iso(latest_row.measured_at),
                "isUserCorrected": False,
                "confidence": round(clamp_unit(average_confidence), 7),
            }
        )

    return samples


def load_existing_labels(paths: list[str]) -> list[dict]:
    samples: list[dict] = []
    for raw_path in paths:
        path = Path(raw_path)
        with path.open("r", encoding="utf-8") as handle:
            loaded = json.load(handle)
        if not isinstance(loaded, list):
            raise ValueError(f"labels.json must contain a list: {path}")
        samples.extend(loaded)
    return samples


def dedupe_samples(samples: list[dict]) -> list[dict]:
    deduped: list[dict] = []
    seen: set[str] = set()
    for sample in samples:
        sample_id = str(sample.get("id", ""))
        if sample_id and sample_id in seen:
            continue
        if sample_id:
            seen.add(sample_id)
        deduped.append(sample)
    return deduped


def main() -> int:
    args = parse_args()
    store = Path(args.store)
    if not store.is_file():
        print(f"[ERROR] store 파일을 찾을 수 없습니다: {store}", file=sys.stderr)
        return 1

    documents_dir = Path(args.documents_dir) if args.documents_dir else infer_documents_dir(store)
    if not documents_dir.is_dir():
        print(f"[ERROR] Documents 디렉토리를 찾을 수 없습니다: {documents_dir}", file=sys.stderr)
        return 1

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = load_rows(store)
    recovered = recovered_samples(store, documents_dir, rows, args.min_keypoints)
    merged = dedupe_samples(load_existing_labels(args.merge_labels) + recovered)

    output_file = output_dir / "labels.json"
    with output_file.open("w", encoding="utf-8") as handle:
        json.dump(merged, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    type_counts: dict[str, int] = {}
    for sample in recovered:
        type_counts[sample["clothingType"]] = type_counts.get(sample["clothingType"], 0) + 1

    print(f"recovered_samples={len(recovered)}")
    print(f"merged_samples={len(merged)}")
    for clothing_type, count in sorted(type_counts.items()):
        print(f"{clothing_type}={count}")
    print(f"output={output_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
