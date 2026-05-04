#!/usr/bin/env python3
"""Audit whether ClothIQ per-type ML training is actually complete.

This is intentionally stricter than readiness checks. It verifies real captured
samples, user-corrected samples, keypoint coverage, training dependencies, and
compiled Core ML model artifacts before the training goal can be considered done.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any


MODEL_BASE_NAME = "ClothingKeypointDetector"

EXPECTED_KEYPOINTS: dict[str, set[str]] = {
    "short_sleeve": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "long_sleeve": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve", "right_sleeve"},
    "shirt": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "polo": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "jacket": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve", "right_sleeve"},
    "coat": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "vest": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center"},
    "cardigan": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "hoodie": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "left_sleeve"},
    "dress": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "waist_left", "waist_right", "hip_left", "hip_right"},
    "jumpsuit": {"left_shoulder", "right_shoulder", "chest_left", "chest_right", "neckline", "hem_center", "waist_left", "waist_right", "hip_left", "hip_right", "crotch"},
    "shorts": {"waist_left", "waist_right", "hem_center", "hem_left", "hem_right", "crotch"},
    "pants": {"waist_left", "waist_right", "hem_center", "hem_left", "hem_right", "crotch", "hip_left", "hip_right"},
    "jeans": {"waist_left", "waist_right", "hem_center", "hem_left", "hem_right", "crotch", "hip_left", "hip_right"},
    "skirt": {"waist_left", "waist_right", "hem_center", "hem_left", "hem_right"},
    "leggings": {"waist_left", "waist_right", "hem_center", "hem_left", "hem_right", "hip_left", "hip_right"},
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit ClothIQ per-type ML training completion.")
    parser.add_argument("--data-path", required=True, help="Directory containing labels.json")
    parser.add_argument("--clothing-type-source", default="ClothIQ/ClothIQ/Core/Domain/Enums/ClothingType.swift")
    parser.add_argument("--models-dir", default="models")
    parser.add_argument("--bundle-models-dir", default="ClothIQ/ClothIQ/Resources/CoreML")
    parser.add_argument("--min-real-samples", type=int, default=20)
    parser.add_argument("--min-corrected-samples", type=int, default=3)
    parser.add_argument("--min-keypoint-coverage", type=int, default=3)
    parser.add_argument(
        "--required-types",
        default="all",
        help="'all', 'captured', or comma-separated ClothingType raw values.",
    )
    parser.add_argument(
        "--write-plan",
        help="Write a Markdown capture/correction plan based on the audit gaps.",
    )
    parser.add_argument(
        "--write-capture-checklist",
        help="Write a Korean Markdown checklist for the next real capture session.",
    )
    return parser.parse_args()


def parse_supported_types(path: Path) -> list[str]:
    if not path.exists():
        raise FileNotFoundError(f"ClothingType source not found: {path}")

    content = path.read_text(encoding="utf-8")
    match = re.search(r"enum\s+ClothingType\b.*?\n}\n", content, flags=re.S)
    if not match:
        raise ValueError(f"ClothingType enum not found: {path}")
    return re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', match.group(0))


def load_samples(labels_path: Path) -> list[dict[str, Any]]:
    if not labels_path.exists():
        raise FileNotFoundError(f"labels.json not found: {labels_path}")
    with labels_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, list):
        raise ValueError("labels.json must contain a JSON array")
    return data


def is_augmented(sample: dict[str, Any]) -> bool:
    return sample.get("isAugmented") is True or bool(sample.get("sourceSampleID"))


def usability_error(sample: dict[str, Any]) -> str | None:
    if not sample.get("clothingType"):
        return "clothingType 누락"
    if not sample.get("keypoints"):
        return "keypoints 누락"
    image_data = sample.get("imageData")
    if not isinstance(image_data, str) or not image_data:
        return "imageData 누락"
    try:
        base64.b64decode(image_data, validate=True)
    except Exception:
        return "imageData 디코딩 실패"
    return None


def visible_keypoints(sample: dict[str, Any]) -> list[dict[str, Any]]:
    labels = []
    for label in sample.get("keypoints") or []:
        identifier = label.get("identifier")
        x = label.get("x")
        y = label.get("y")
        visibility = label.get("visibility", 0)
        if visibility < 0.5:
            continue
        if not identifier or not isinstance(x, (int, float)) or not isinstance(y, (int, float)):
            continue
        if 0 <= x <= 1 and 0 <= y <= 1:
            labels.append(label)
    return labels


def image_hash(sample: dict[str, Any]) -> str | None:
    image_data = sample.get("imageData")
    if not isinstance(image_data, str) or not image_data:
        return None
    try:
        decoded = base64.b64decode(image_data, validate=True)
    except Exception:
        return None
    return hashlib.sha256(decoded).hexdigest()


def has_model_artifact(models_dir: Path, bundle_dir: Path, clothing_type: str) -> tuple[bool, str]:
    resource_name = f"{MODEL_BASE_NAME}_{clothing_type}"
    candidates = [
        models_dir / f"{resource_name}.mlmodelc",
        bundle_dir / f"{resource_name}.mlmodelc",
    ]
    existing = [path for path in candidates if path.is_dir()]
    if existing:
        return True, ", ".join(str(path) for path in existing)

    source_candidates = [
        models_dir / f"{resource_name}.mlpackage",
        bundle_dir / f"{resource_name}.mlpackage",
        models_dir / f"{resource_name}.mlmodel",
        bundle_dir / f"{resource_name}.mlmodel",
    ]
    source_existing = [path for path in source_candidates if path.exists()]
    if source_existing:
        return False, "원본 모델만 있음: " + ", ".join(str(path) for path in source_existing)
    return False, "컴파일된 .mlmodelc 없음"


def dependency_status() -> dict[str, bool]:
    modules = {
        "tensorflow": "tensorflow",
        "coremltools": "coremltools",
        "PIL": "PIL",
    }
    status: dict[str, bool] = {}
    for name, module in modules.items():
        result = subprocess.run(
            [sys.executable, "-c", f"import {module}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=90,
        )
        status[name] = result.returncode == 0
    return status


def required_types_from_arg(value: str, supported_types: list[str], samples: list[dict[str, Any]]) -> list[str]:
    if value == "all":
        return supported_types
    if value == "captured":
        captured = sorted({sample.get("clothingType") for sample in samples if sample.get("clothingType")})
        return [clothing_type for clothing_type in captured if clothing_type in supported_types]
    requested = [item.strip() for item in value.split(",") if item.strip()]
    unknown = [item for item in requested if item not in supported_types]
    if unknown:
        raise ValueError(f"지원하지 않는 의류 타입: {', '.join(unknown)}")
    return requested


def write_collection_plan(
    output_path: Path,
    labels_path: Path,
    required_types: list[str],
    deps: dict[str, bool],
    rows: list[dict[str, Any]],
    invalid_reasons: Counter[str],
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    missing_deps = [name for name, exists in deps.items() if not exists]
    lines = [
        "# ClothIQ ML Training Collection Plan",
        "",
        "## Current Evidence",
        "",
        f"- labels: `{labels_path}`",
        f"- required clothing types: {len(required_types)}",
        "- dependencies: " + ", ".join(f"{name}={'ok' if exists else 'missing'}" for name, exists in deps.items()),
        "",
    ]

    if missing_deps:
        lines.extend([
            "## Environment Blockers",
            "",
            "- Install or provide the missing training/conversion packages before model generation:",
            f"  `{', '.join(missing_deps)}`",
            "",
        ])

    if invalid_reasons:
        reason_text = ", ".join(f"{reason} {count}" for reason, count in sorted(invalid_reasons.items()))
        lines.extend([
            "## Data Quality Blockers",
            "",
            f"- Invalid samples detected: {reason_text}",
            "",
        ])

    lines.extend([
        "## Capture Targets",
        "",
        "| Clothing Type | Unique Real Photos | Need Real | Corrected Real Photos | Need Corrected | Missing Keypoints | Model |",
        "| --- | ---: | ---: | ---: | ---: | --- | --- |",
    ])

    for row in rows:
        missing_keypoints = ", ".join(row["missing_keypoints"]) if row["missing_keypoints"] else "ok"
        model_status = "ok" if row["model_ok"] else "missing"
        lines.append(
            f"| {row['clothing_type']} | {row['real_count']} | {row['need_real']} | "
            f"{row['corrected_count']} | {row['need_corrected']} | {missing_keypoints} | {model_status} |"
        )

    lines.extend([
        "",
        "## Next Capture Rules",
        "",
        "- Capture one clearly visible garment per image, fully spread and not occluded.",
        "- After auto-detection, manually correct anchors/keypoints for each saved sample when possible.",
        "- Prioritize rows with the largest `Need Real` value, then rows with missing keypoints.",
        "- Do not count augmented samples as real captures for completion.",
        "",
        "## Re-run Commands",
        "",
        "```bash",
        "# 1. Verify the local ML training/conversion environment",
        "scripts/setup_ml_training_env.sh --verify-only --smoke-conversion",
        "",
        "# 2. Pull the latest full device snapshot, recover SwiftData labels, and merge",
        "bash scripts/pull_training_snapshot.sh \\",
        "  --device-id <device-id> \\",
        "  --output-dir tmp/latest-training-snapshot \\",
        "  --completion-audit \\",
        "  --collection-plan tmp/ml-training-collection-plan-current-audit.md \\",
        "  --capture-checklist tmp/ml-training-required-capture-checklist.md",
        "",
        "# 3. Audit completion against real original/corrected samples and model artifacts",
        "bash scripts/ml_training_workflow.sh \\",
        "  --data-path tmp/latest-training-snapshot/merged \\",
        "  --completion-audit \\",
        "  --skip-export",
        "",
        "# 4. Train, compile, and deploy all trainable per-type models after the audit passes",
        "bash scripts/ml_training_workflow.sh \\",
        "  --data-path tmp/latest-training-snapshot/merged \\",
        "  --per-type \\",
        "  --skip-export",
        "```",
        "",
    ])

    output_path.write_text("\n".join(lines), encoding="utf-8")


def capture_priority(row: dict[str, Any]) -> int:
    if row["real_count"] == 0:
        return 1
    if row["need_real"] >= 15:
        return 2
    if row["need_real"] > 0 or row["need_corrected"] > 0 or row["missing_keypoints"]:
        return 3
    if not row["model_ok"]:
        return 4
    return 5


def write_capture_checklist(
    output_path: Path,
    labels_path: Path,
    rows: list[dict[str, Any]],
    total_labels: int,
    total_real_unique: int,
    total_corrected_unique: int,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sorted_rows = sorted(
        rows,
        key=lambda row: (
            capture_priority(row),
            -row["need_real"],
            -row["need_corrected"],
            row["clothing_type"],
        ),
    )

    lines = [
        "# ClothIQ ML 학습 촬영 체크리스트",
        "",
        "## 목표",
        "",
        "- 각 의류 타입별 고유 실제 촬영 원본 20장 이상",
        "- 각 의류 타입별 수동 보정된 고유 원본 3장 이상",
        "- 필수 키포인트가 모두 포함되도록 측정 라인 저장",
        "- 감사 통과 후 타입별 `ClothingKeypointDetector_<type>.mlmodelc` 생성 및 배포",
        "",
        "## 현재 감사 기준",
        "",
        f"- 최신 병합 라벨: `{labels_path}`",
        f"- 총 라벨: {total_labels}개",
        f"- 고유 실제 촬영 원본: {total_real_unique}개",
        f"- 고유 사용자 보정 원본: {total_corrected_unique}개",
        "",
        "## 현재 수집 필요 목록",
        "",
        "| 우선순위 | Clothing Type | 현재 고유 원본 | 추가 원본 필요 | 현재 보정 원본 | 추가 보정 필요 | 키포인트 | 모델 |",
        "| ---: | --- | ---: | ---: | ---: | ---: | --- | --- |",
    ]

    for row in sorted_rows:
        missing_keypoints = ", ".join(row["missing_keypoints"]) if row["missing_keypoints"] else "ok"
        model_status = "ok" if row["model_ok"] else "missing"
        lines.append(
            f"| {capture_priority(row)} | `{row['clothing_type']}` | {row['real_count']} | "
            f"{row['need_real']} | {row['corrected_count']} | {row['need_corrected']} | "
            f"{missing_keypoints} | {model_status} |"
        )

    lines.extend([
        "",
        "## 촬영 규칙",
        "",
        "- 한 이미지에는 한 벌만 촬영합니다.",
        "- 의류 전체가 프레임 안에 들어오게 펼쳐서 촬영합니다.",
        "- 소매, 밑단, 허리, 어깨, 목선이 가려지지 않게 합니다.",
        "- 배경과 의류 색상이 너무 비슷하지 않게 합니다.",
        "- 자동 측정 후 타입별 최소 3장은 앵커/키포인트를 직접 보정해서 저장합니다.",
        "- 증강 샘플이나 같은 사진의 중복 라벨은 실제 촬영 원본 수로 계산하지 않습니다.",
        "",
        "## 수집 후 재검증 명령",
        "",
        "```bash",
        "bash scripts/pull_training_snapshot.sh \\",
        "  --device-id <device-id> \\",
        "  --output-dir tmp/latest-training-snapshot \\",
        "  --completion-audit \\",
        "  --collection-plan tmp/ml-training-collection-plan-current-audit.md \\",
        "  --capture-checklist tmp/ml-training-required-capture-checklist.md",
        "",
        "bash scripts/ml_training_workflow.sh \\",
        "  --data-path tmp/latest-training-snapshot/merged \\",
        "  --completion-audit \\",
        "  --capture-checklist tmp/ml-training-required-capture-checklist.md \\",
        "  --skip-export",
        "```",
        "",
    ])

    output_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = parse_args()
    data_path = Path(args.data_path)
    labels_path = data_path / "labels.json"
    supported_types = parse_supported_types(Path(args.clothing_type_source))
    samples = load_samples(labels_path)
    required_types = required_types_from_arg(args.required_types, supported_types, samples)

    label_counts = Counter()
    usable_real_label_counts = Counter()
    usable_real_hashes: dict[str, set[str]] = {}
    corrected_real_hashes: dict[str, set[str]] = {}
    invalid_reasons = Counter()
    keypoint_hashes: dict[str, dict[str, set[str]]] = {}

    for sample in samples:
        clothing_type = sample.get("clothingType")
        if clothing_type:
            label_counts[clothing_type] += 1

        error = usability_error(sample)
        if error:
            invalid_reasons[error] += 1
            continue
        if not clothing_type or is_augmented(sample):
            continue

        hash_value = image_hash(sample)
        if hash_value is None:
            invalid_reasons["imageData 해시 실패"] += 1
            continue

        usable_real_label_counts[clothing_type] += 1
        usable_real_hashes.setdefault(clothing_type, set()).add(hash_value)
        if sample.get("isUserCorrected") is True:
            corrected_real_hashes.setdefault(clothing_type, set()).add(hash_value)

        expected = EXPECTED_KEYPOINTS.get(clothing_type, set())
        visible = visible_keypoints(sample)
        per_type_hashes = keypoint_hashes.setdefault(clothing_type, {})
        for label in visible:
            identifier = label.get("identifier")
            if identifier in expected:
                per_type_hashes.setdefault(identifier, set()).add(hash_value)

    deps = dependency_status()
    failures: list[str] = []

    print("ClothIQ ML 학습 완료 감사")
    print(f"- labels: {labels_path}")
    print(f"- required types: {len(required_types)}개 ({', '.join(required_types)})")
    print(f"- total labels: {len(samples)}")
    if invalid_reasons:
        reason_text = ", ".join(f"{reason} {count}개" for reason, count in sorted(invalid_reasons.items()))
        failures.append(f"무효 샘플 존재: {reason_text}")

    missing_deps = [name for name, exists in deps.items() if not exists]
    print("- dependencies: " + ", ".join(f"{name}={'ok' if exists else 'missing'}" for name, exists in deps.items()))
    if missing_deps:
        failures.append("학습/변환 의존성 누락: " + ", ".join(missing_deps))

    models_dir = Path(args.models_dir)
    bundle_dir = Path(args.bundle_models_dir)
    rows: list[dict[str, Any]] = []
    print("- per-type status:")
    for clothing_type in required_types:
        expected = EXPECTED_KEYPOINTS.get(clothing_type, set())
        real_count = len(usable_real_hashes.get(clothing_type, set()))
        corrected_count = len(corrected_real_hashes.get(clothing_type, set()))
        real_label_count = usable_real_label_counts[clothing_type]
        missing_keypoints = sorted(
            identifier
            for identifier in expected
            if len(keypoint_hashes.get(clothing_type, {}).get(identifier, set())) < args.min_keypoint_coverage
        )
        model_ok, model_detail = has_model_artifact(models_dir, bundle_dir, clothing_type)
        need_real = max(0, args.min_real_samples - real_count)
        need_corrected = max(0, args.min_corrected_samples - corrected_count)
        rows.append({
            "clothing_type": clothing_type,
            "real_count": real_count,
            "real_label_count": real_label_count,
            "need_real": need_real,
            "corrected_count": corrected_count,
            "need_corrected": need_corrected,
            "missing_keypoints": missing_keypoints,
            "model_ok": model_ok,
            "model_detail": model_detail,
        })

        print(
            f"  - {clothing_type}: labels={label_counts[clothing_type]}, "
            f"real_unique={real_count}, real_labels={real_label_count}, corrected_real_unique={corrected_count}, "
            f"keypoints={'ok' if not missing_keypoints else 'missing ' + ','.join(missing_keypoints)}, "
            f"model={'ok' if model_ok else 'missing'} ({model_detail})"
        )

        if real_count < args.min_real_samples:
            failures.append(f"{clothing_type}: 원본 유효 샘플 {real_count}/{args.min_real_samples}")
        if corrected_count < args.min_corrected_samples:
            failures.append(f"{clothing_type}: 사용자 보정 원본 {corrected_count}/{args.min_corrected_samples}")
        if missing_keypoints:
            failures.append(f"{clothing_type}: 키포인트 coverage 부족 - {', '.join(missing_keypoints)}")
        if not model_ok:
            failures.append(f"{clothing_type}: 타입별 컴파일 모델 없음")

    if args.write_plan:
        plan_path = Path(args.write_plan)
        write_collection_plan(plan_path, labels_path, required_types, deps, rows, invalid_reasons)
        print(f"\n수집 계획 작성: {plan_path}")

    if args.write_capture_checklist:
        total_real_unique = len(set().union(*(usable_real_hashes.get(item, set()) for item in required_types)))
        total_corrected_unique = len(set().union(*(corrected_real_hashes.get(item, set()) for item in required_types)))
        checklist_path = Path(args.write_capture_checklist)
        write_capture_checklist(
            checklist_path,
            labels_path,
            rows,
            len(samples),
            total_real_unique,
            total_corrected_unique,
        )
        print(f"촬영 체크리스트 작성: {checklist_path}")

    if failures:
        print("\n결론: 미완료")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("\n결론: 완료")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
