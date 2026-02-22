#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
ClothIQ Keypoint Detection Model Training Script

이 스크립트는 수집된 학습 데이터를 사용하여 의류 키포인트 감지 모델을 학습합니다.
TensorFlow/Keras를 사용하여 Core ML 호환 모델을 생성합니다.

Requirements:
    pip install tensorflow coremltools pillow numpy pandas scikit-learn
"""

import os
import json
import base64
import numpy as np
import pandas as pd
from pathlib import Path
from PIL import Image
import io
import argparse
from typing import Dict, List, Tuple
from datetime import datetime

# TensorFlow 설정
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
from tensorflow.keras.preprocessing.image import ImageDataGenerator
import coremltools as ct
from sklearn.model_selection import train_test_split

class ClothingKeypointTrainer:
    """의류 키포인트 감지 모델 학습 클래스"""

    def __init__(self, data_path: str, output_path: str):
        self.data_path = Path(data_path)
        self.output_path = Path(output_path)
        self.output_path.mkdir(parents=True, exist_ok=True)

        # 모델 파라미터
        self.img_size = (224, 224)
        self.num_keypoints = 17  # 키포인트 개수
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

        print(f"✅ 총 {len(samples)}개의 샘플 로드됨")

        for sample in samples:
            # Base64 이미지 디코딩
            img_data = base64.b64decode(sample['imageData'])
            img = Image.open(io.BytesIO(img_data))

            # 이미지 전처리
            img = img.convert('RGB')
            img = img.resize(self.img_size, Image.LANCZOS)
            img_array = np.array(img) / 255.0  # 정규화

            self.images.append(img_array)

            # 키포인트 추출 (x, y, visibility)
            keypoint_array = []
            for kp in sample['keypoints']:
                keypoint_array.extend([
                    kp['x'],
                    kp['y'],
                    kp['visibility']
                ])

            # 키포인트 개수가 부족한 경우 패딩
            while len(keypoint_array) < self.num_keypoints * 3:
                keypoint_array.extend([0.0, 0.0, 0.0])

            # 키포인트 개수가 많은 경우 잘라내기
            keypoint_array = keypoint_array[:self.num_keypoints * 3]

            self.keypoints.append(keypoint_array)
            self.metadata.append({
                'clothingType': sample['clothingType'],
                'isUserCorrected': sample['isUserCorrected'],
                'confidence': sample['confidence']
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
            weights='imagenet'
        )
        base_model.trainable = False  # 초기에는 동결

        inputs = keras.Input(shape=(*self.img_size, 3))

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
                str(self.output_path / 'best_model.h5'),
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
            inputs=[ct.ImageType(
                name='image',
                shape=(1, *self.img_size, 3),
                scale=1/255.0
            )],
            outputs=[ct.TensorType(name='keypoints')],
            minimum_deployment_target=ct.target.iOS15
        )

        # 메타데이터 추가
        coreml_model.author = 'ClothIQ'
        coreml_model.license = 'MIT'
        coreml_model.short_description = 'Clothing Keypoint Detection Model'
        coreml_model.version = datetime.now().strftime('%Y%m%d')

        # 저장
        output_file = self.output_path / 'ClothingKeypointDetector.mlmodel'
        coreml_model.save(str(output_file))

        print(f"✅ Core ML 모델 저장 완료: {output_file}")

        # 모델 정보 저장
        info = {
            'version': coreml_model.version,
            'created': datetime.now().isoformat(),
            'num_keypoints': self.num_keypoints,
            'input_size': list(self.img_size),
            'training_samples': len(self.images),
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

    args = parser.parse_args()

    print("🚀 ClothIQ 키포인트 감지 모델 학습 시작")
    print("=" * 50)

    # 트레이너 생성
    trainer = ClothingKeypointTrainer(args.data_path, args.output_path)
    trainer.epochs = args.epochs
    trainer.batch_size = args.batch_size

    try:
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