#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
ClothIQ Keypoint Detection Model Training Script

이 스크립트는 수집된 학습 데이터를 사용하여 의류 키포인트 감지 모델을 학습합니다.
TensorFlow/Keras를 사용하여 Core ML 호환 모델을 생성합니다.

Requirements:
    pip install tensorflow coremltools pillow numpy pandas scikit-learn
"""

from __future__ import annotations

import os
import json
import base64
import hashlib
from pathlib import Path
import io
import argparse
import importlib.util
from typing import Any, Optional
from datetime import datetime

np = None
Image = None
tf = None
keras = None
layers = None
ct = None
train_test_split = None

KEYPOINT_IDENTIFIERS = [
    "left_shoulder",
    "right_shoulder",
    "left_armpit",
    "right_armpit",
    "left_sleeve",
    "right_sleeve",
    "neckline",
    "hem_center",
    "chest_left",
    "chest_right",
    "waist_left",
    "waist_right",
    "hip_left",
    "hip_right",
    "crotch",
    "hem_left",
    "hem_right",
]

REQUIRED_PACKAGES = ["numpy", "PIL", "tensorflow", "coremltools", "sklearn"]


def make_coreml_package_compiler_readable(package_path: Path) -> None:
    """CoreML compiler subprocesses must be able to traverse .mlpackage files."""
    if not package_path.is_dir():
        return

    for root, dirs, files in os.walk(package_path):
        for directory in dirs:
            os.chmod(Path(root) / directory, 0o755)
        for filename in files:
            os.chmod(Path(root) / filename, 0o644)
    os.chmod(package_path, 0o755)


def dependency_status() -> dict[str, bool]:
    return {name: importlib.util.find_spec(name) is not None for name in REQUIRED_PACKAGES}


def ensure_training_dependencies() -> None:
    missing = [name for name, exists in dependency_status().items() if not exists]
    if missing:
        raise RuntimeError(
            "학습/변환 의존성이 없습니다: "
            + ", ".join(missing)
            + "\n설치 예: python3 -m pip install tensorflow coremltools pillow numpy scikit-learn"
        )

    global np, Image, tf, keras, layers, ct, train_test_split
    import numpy as np_module
    from PIL import Image as image_module
    import tensorflow as tf_module
    import coremltools as ct_module
    from sklearn.model_selection import train_test_split as split_module

    np = np_module
    Image = image_module
    tf = tf_module
    keras = tf_module.keras
    layers = tf_module.keras.layers
    ct = ct_module
    train_test_split = split_module


def is_augmented_sample(sample: dict[str, Any]) -> bool:
    return sample.get("isAugmented") is True or bool(sample.get("sourceSampleID"))


def is_usable_sample(sample: dict[str, Any]) -> bool:
    if not sample.get("clothingType") or not sample.get("keypoints"):
        return False
    image_data = sample.get("imageData")
    if not isinstance(image_data, str) or not image_data:
        return False
    try:
        base64.b64decode(image_data, validate=True)
    except Exception:
        return False
    return True


def sample_image_hash(sample: dict[str, Any]) -> Optional[str]:
    image_data = sample.get("imageData")
    if not isinstance(image_data, str) or not image_data:
        return None
    try:
        decoded = base64.b64decode(image_data, validate=True)
    except Exception:
        return None
    return hashlib.sha256(decoded).hexdigest()


def merge_samples_by_image(samples: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Merge duplicate records for the same captured image into one label set."""
    grouped: dict[tuple[str, str], list[dict[str, Any]]] = {}
    unhashable: list[dict[str, Any]] = []

    for sample in samples:
        hash_value = sample_image_hash(sample)
        clothing_type = sample.get("clothingType")
        if not hash_value or not clothing_type:
            unhashable.append(sample)
            continue
        grouped.setdefault((clothing_type, hash_value), []).append(sample)

    merged_samples: list[dict[str, Any]] = []
    for group in grouped.values():
        base = max(
            group,
            key=lambda sample: (
                sample.get("isUserCorrected") is True,
                len(sample.get("keypoints") or []),
                float(sample.get("confidence") or 0.0),
            ),
        ).copy()

        keypoints_by_identifier: dict[str, dict[str, Any]] = {}
        scores_by_identifier: dict[str, tuple[bool, float, float, float]] = {}

        for sample in group:
            sample_score = float(sample.get("confidence") or 0.0)
            is_corrected = sample.get("isUserCorrected") is True
            for keypoint in sample.get("keypoints") or []:
                identifier = keypoint.get("identifier")
                if not identifier:
                    continue
                score = (
                    is_corrected,
                    float(keypoint.get("visibility") or 0.0),
                    float(keypoint.get("confidence") or 0.0),
                    sample_score,
                )
                if identifier not in scores_by_identifier or score > scores_by_identifier[identifier]:
                    keypoints_by_identifier[identifier] = keypoint.copy()
                    scores_by_identifier[identifier] = score

        base["keypoints"] = list(keypoints_by_identifier.values())
        base["isUserCorrected"] = any(sample.get("isUserCorrected") is True for sample in group)
        base["mergedSampleCount"] = len(group)
        merged_samples.append(base)

    return merged_samples + unhashable


class ClothingKeypointTrainer:
    """의류 키포인트 감지 모델 학습 클래스"""

    def __init__(
        self,
        data_path: str,
        output_path: str,
        clothing_type: Optional[str] = None,
        model_name: str = "ClothingKeypointDetector",
        allow_augmented: bool = False,
        min_real_samples: int = 20,
        min_corrected_samples: int = 3,
        backbone_weights: Optional[str] = "imagenet",
    ):
        self.data_path = Path(data_path)
        self.output_path = Path(output_path)
        self.output_path.mkdir(parents=True, exist_ok=True)
        self.clothing_type = clothing_type
        self.model_name = model_name
        self.allow_augmented = allow_augmented
        self.min_real_samples = min_real_samples
        self.min_corrected_samples = min_corrected_samples
        self.backbone_weights = backbone_weights

        # 모델 파라미터
        self.img_size = (224, 224)
        self.num_keypoints = len(KEYPOINT_IDENTIFIERS)
        self.batch_size = 32
        self.epochs = 100

        # 데이터
        self.images = []
        self.keypoints = []
        self.metadata = []

    def load_training_data(self):
        """학습 데이터 로드"""
        labels_file = self.data_path / "labels.json"

        if not labels_file.exists():
            raise FileNotFoundError(f"학습 데이터를 찾을 수 없습니다: {labels_file}")

        print(f"📂 학습 데이터 로드 중: {labels_file}")

        with open(labels_file, 'r') as f:
            samples = json.load(f)

        if self.clothing_type:
            samples = [
                sample for sample in samples
                if sample.get('clothingType') == self.clothing_type
            ]
            print(f"🧥 의류 타입 필터 적용: {self.clothing_type} ({len(samples)}개)")

        usable_samples = [sample for sample in samples if is_usable_sample(sample)]
        real_samples = [sample for sample in usable_samples if not is_augmented_sample(sample)]
        unique_real_hashes = {
            hash_value
            for sample in real_samples
            if (hash_value := sample_image_hash(sample)) is not None
        }
        unique_corrected_real_hashes = {
            hash_value
            for sample in real_samples
            if sample.get("isUserCorrected") is True
            if (hash_value := sample_image_hash(sample)) is not None
        }

        if not usable_samples:
            raise ValueError("학습 가능한 샘플이 없습니다")

        if len(unique_real_hashes) < self.min_real_samples:
            raise ValueError(
                f"고유 실제 원본 촬영 샘플이 부족합니다: {len(unique_real_hashes)}/{self.min_real_samples}. "
                "증강 샘플은 기본 학습 완료 기준으로 계산하지 않습니다."
            )

        if len(unique_corrected_real_hashes) < self.min_corrected_samples:
            raise ValueError(
                f"고유 사용자 보정 원본 촬영 샘플이 부족합니다: {len(unique_corrected_real_hashes)}/{self.min_corrected_samples}"
            )

        training_samples = usable_samples if self.allow_augmented else real_samples
        training_record_count = len(training_samples)
        training_samples = merge_samples_by_image(training_samples)
        if not self.allow_augmented:
            removed_count = len(usable_samples) - len(real_samples)
            if removed_count > 0:
                print(f"ℹ️ 증강 샘플 {removed_count}개 제외 (기본값)")

        if len(training_samples) != training_record_count:
            print(f"ℹ️ 중복 촬영 레코드 병합: {training_record_count}개 → {len(training_samples)}개")

        print(f"✅ 총 {len(training_samples)}개의 고유 촬영 샘플 로드됨")
        print(f"  - 원본 유효 레코드: {len(real_samples)}개")
        print(f"  - 고유 원본 촬영 샘플: {len(unique_real_hashes)}개")
        print(f"  - 고유 사용자 보정 원본 촬영 샘플: {len(unique_corrected_real_hashes)}개")

        for sample in training_samples:
            # Base64 이미지 디코딩
            img_data = base64.b64decode(sample['imageData'])
            img = Image.open(io.BytesIO(img_data))

            # 이미지 전처리
            img = img.convert('RGB')
            img = img.resize(self.img_size, Image.LANCZOS)
            img_array = np.array(img) / 255.0  # 정규화

            self.images.append(img_array)

            # 키포인트 추출 (VisionMLService의 파싱 순서와 동일하게 정렬)
            keypoint_lookup = {
                kp['identifier']: (
                    kp.get('x', 0.0),
                    kp.get('y', 0.0),
                    kp.get('visibility', 0.0),
                )
                for kp in sample['keypoints']
            }

            keypoint_array = []
            for identifier in KEYPOINT_IDENTIFIERS:
                keypoint_array.extend(keypoint_lookup.get(identifier, (0.0, 0.0, 0.0)))

            self.keypoints.append(keypoint_array)
            self.metadata.append({
                'clothingType': sample.get('clothingType'),
                'isUserCorrected': sample.get('isUserCorrected', False),
                'confidence': sample.get('confidence', 0.0),
                'isAugmented': is_augmented_sample(sample),
                'imageHash': sample_image_hash(sample),
            })

        self.images = np.array(self.images)
        self.keypoints = np.array(self.keypoints)

        print(f"📊 데이터 형태:")
        print(f"  - 이미지: {self.images.shape}")
        print(f"  - 키포인트: {self.keypoints.shape}")

    def create_model(self) -> keras.Model:
        """키포인트 감지 모델 생성"""
        print("\n🔨 모델 생성 중...")

        # MobileNetV2 백본 사용 (경량화)
        base_model = tf.keras.applications.MobileNetV2(
            input_shape=(*self.img_size, 3),
            include_top=False,
            weights=self.backbone_weights
        )
        base_model.trainable = False  # 초기에는 동결

        inputs = keras.Input(shape=(*self.img_size, 3), name='image')

        # 전처리 레이어
        x = tf.keras.applications.mobilenet_v2.preprocess_input(inputs)

        # 백본 통과
        x = base_model(x, training=False)

        # 헤드 네트워크
        x = layers.GlobalAveragePooling2D()(x)
        x = layers.Dense(512, activation='relu')(x)
        x = layers.Dropout(0.3)(x)
        x = layers.Dense(256, activation='relu')(x)
        x = layers.Dropout(0.3)(x)

        # 출력: 키포인트 좌표 + 신뢰도
        outputs = layers.Dense(self.num_keypoints * 3, activation='sigmoid')(x)

        model = keras.Model(inputs, outputs)

        print("✅ 모델 생성 완료")
        print(model.summary())

        return model

    def train(self):
        """모델 학습"""
        print("\n🎯 학습 시작...")

        # 데이터 분할
        X_train, X_val, y_train, y_val = train_test_split(
            self.images, self.keypoints,
            test_size=0.2, random_state=42
        )

        print(f"  - 학습 데이터: {len(X_train)}개")
        print(f"  - 검증 데이터: {len(X_val)}개")

        # 모델 생성
        model = self.create_model()

        # 컴파일
        model.compile(
            optimizer=keras.optimizers.Adam(learning_rate=0.001),
            loss='mse',
            metrics=['mae']
        )

        # 콜백
        callbacks = [
            keras.callbacks.EarlyStopping(
                patience=10,
                restore_best_weights=True
            ),
            keras.callbacks.ReduceLROnPlateau(
                factor=0.5,
                patience=5,
                min_lr=0.00001
            ),
            keras.callbacks.ModelCheckpoint(
                str(self.output_path / 'best_model.keras'),
                save_best_only=True
            )
        ]

        # 학습
        history = model.fit(
            X_train, y_train,
            validation_data=(X_val, y_val),
            batch_size=self.batch_size,
            epochs=self.epochs,
            callbacks=callbacks,
            verbose=1
        )

        self.model = model
        self.history = history

        print("\n✅ 학습 완료!")

        # 최종 성능
        val_loss = min(history.history['val_loss'])
        val_mae = min(history.history['val_mae'])
        print(f"  - 최고 검증 손실: {val_loss:.4f}")
        print(f"  - 최고 검증 MAE: {val_mae:.4f}")

    def export_to_coreml(self):
        """Core ML 모델로 변환"""
        print("\n📦 Core ML 변환 중...")

        # Core ML 변환
        coreml_model = ct.convert(
            self.model,
            source='tensorflow',
            inputs=[ct.ImageType(
                name='image',
                shape=(1, *self.img_size, 3),
                scale=1/255.0
            )],
            minimum_deployment_target=ct.target.iOS15
        )

        # 메타데이터 추가
        coreml_model.author = 'ClothIQ'
        coreml_model.license = 'MIT'
        coreml_model.short_description = 'Clothing Keypoint Detection Model'
        coreml_model.version = datetime.now().strftime('%Y%m%d')
        coreml_model.user_defined_metadata['keypoint_identifiers'] = json.dumps(KEYPOINT_IDENTIFIERS)
        coreml_model.user_defined_metadata['output_layout'] = 'x,y,confidence triples in keypoint_identifiers order; normalized Vision coordinates with y=0 at bottom'

        # Core ML Tools 9+는 iOS15 이상 ML Program을 .mlpackage로 저장한다.
        output_file = self.output_path / f'{self.model_name}.mlpackage'
        coreml_model.save(str(output_file))
        make_coreml_package_compiler_readable(output_file)

        print(f"✅ Core ML 모델 저장 완료: {output_file}")

        # 모델 정보 저장
        info = {
            'version': coreml_model.version,
            'created': datetime.now().isoformat(),
            'num_keypoints': self.num_keypoints,
            'keypoint_identifiers': KEYPOINT_IDENTIFIERS,
            'model_name': self.model_name,
            'clothing_type': self.clothing_type or 'generic',
            'input_size': list(self.img_size),
            'training_samples': len(self.images),
            'unique_real_samples': len({
                meta.get('imageHash')
                for meta in self.metadata
                if meta.get('imageHash') and not meta.get('isAugmented')
            }),
            'final_loss': float(min(self.history.history['val_loss'])),
            'final_mae': float(min(self.history.history['val_mae']))
        }

        with open(self.output_path / 'model_info.json', 'w') as f:
            json.dump(info, f, indent=2)

        print("\n📊 모델 정보:")
        for key, value in info.items():
            print(f"  - {key}: {value}")

    def evaluate_model(self):
        """모델 평가"""
        print("\n📈 모델 평가 중...")

        # 사용자가 수정한 데이터만 추출
        user_corrected_indices = [
            i for i, meta in enumerate(self.metadata)
            if meta['isUserCorrected']
        ]

        if user_corrected_indices:
            X_corrected = self.images[user_corrected_indices]
            y_corrected = self.keypoints[user_corrected_indices]

            loss, mae = self.model.evaluate(X_corrected, y_corrected, verbose=0)

            print(f"  - 사용자 수정 데이터 성능:")
            print(f"    • 손실: {loss:.4f}")
            print(f"    • MAE: {mae:.4f}")

        # 의류 타입별 성능
        clothing_types = set(meta['clothingType'] for meta in self.metadata)

        print(f"\n  - 의류 타입별 성능:")
        for ctype in clothing_types:
            indices = [
                i for i, meta in enumerate(self.metadata)
                if meta['clothingType'] == ctype
            ]

            if indices:
                X_type = self.images[indices]
                y_type = self.keypoints[indices]

                loss, mae = self.model.evaluate(X_type, y_type, verbose=0)
                print(f"    • {ctype}: 손실={loss:.4f}, MAE={mae:.4f} (n={len(indices)})")


def main():
    parser = argparse.ArgumentParser(description='ClothIQ 키포인트 감지 모델 학습')
    parser.add_argument(
        '--data-path',
        type=str,
        default='../ClothIQ/ClothIQ/Documents/MLTrainingData',
        help='학습 데이터 경로'
    )
    parser.add_argument(
        '--output-path',
        type=str,
        default='../models',
        help='모델 출력 경로'
    )
    parser.add_argument(
        '--epochs',
        type=int,
        default=100,
        help='학습 에폭 수'
    )
    parser.add_argument(
        '--batch-size',
        type=int,
        default=32,
        help='배치 크기'
    )
    parser.add_argument(
        '--clothing-type',
        type=str,
        default=None,
        help='특정 의류 타입(rawValue)만 학습합니다. 예: shorts, shirt'
    )
    parser.add_argument(
        '--model-name',
        type=str,
        default='ClothingKeypointDetector',
        help='출력 Core ML 모델 이름(.mlmodel 제외)'
    )
    parser.add_argument(
        '--allow-augmented',
        action='store_true',
        help='증강 샘플까지 학습에 포함합니다. 기본값은 실제 원본 샘플만 사용합니다.'
    )
    parser.add_argument(
        '--min-real-samples',
        type=int,
        default=20,
        help='학습을 허용할 최소 고유 실제 원본 촬영 수'
    )
    parser.add_argument(
        '--min-corrected-samples',
        type=int,
        default=3,
        help='학습을 허용할 최소 고유 사용자 보정 원본 촬영 수'
    )
    parser.add_argument(
        '--backbone-weights',
        choices=['imagenet', 'none'],
        default='imagenet',
        help='MobileNetV2 백본 가중치. none은 외부 다운로드 없이 무작위 초기화합니다.'
    )
    parser.add_argument(
        '--check-deps',
        action='store_true',
        help='학습 의존성 설치 여부만 확인하고 종료합니다.'
    )

    args = parser.parse_args()

    print("🚀 ClothIQ 키포인트 감지 모델 학습 시작")
    print("=" * 50)

    try:
        if args.check_deps:
            status = dependency_status()
            for package, installed in status.items():
                print(f"{package}: {'ok' if installed else 'missing'}")
            return 0 if all(status.values()) else 1

        ensure_training_dependencies()

        # 트레이너 생성
        trainer = ClothingKeypointTrainer(
            args.data_path,
            args.output_path,
            clothing_type=args.clothing_type,
            model_name=args.model_name,
            allow_augmented=args.allow_augmented,
            min_real_samples=args.min_real_samples,
            min_corrected_samples=args.min_corrected_samples,
            backbone_weights=None if args.backbone_weights == 'none' else args.backbone_weights,
        )
        trainer.epochs = args.epochs
        trainer.batch_size = args.batch_size

        # 데이터 로드
        trainer.load_training_data()

        # 학습
        trainer.train()

        # 평가
        trainer.evaluate_model()

        # Core ML 변환
        trainer.export_to_coreml()

        print("\n🎉 모든 작업이 성공적으로 완료되었습니다!")

    except Exception as e:
        print(f"\n❌ 오류 발생: {e}")
        import traceback
        traceback.print_exc()
        return 1

    return 0


if __name__ == '__main__':
    exit(main())
