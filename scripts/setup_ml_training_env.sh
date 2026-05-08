#!/bin/bash

#########################################################################################
# ClothIQ ML 학습 Python 환경 설정 스크립트
#
# 기본 동작:
#   1. Python 3.11 계열을 우선 찾아 .venv-ml 생성
#   2. TensorFlow/Core ML 변환 의존성 설치
#   3. 실제 import 가능 여부 검증
#   4. 선택 시 작은 Keras 모델의 Core ML 변환/컴파일 검증
#
# 사용법:
#   scripts/setup_ml_training_env.sh
#   scripts/setup_ml_training_env.sh --python /path/to/python3.11
#   scripts/setup_ml_training_env.sh --verify-only
#   scripts/setup_ml_training_env.sh --verify-only --smoke-conversion
#########################################################################################

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VENV_PATH="$PROJECT_ROOT/.venv-ml"
PYTHON_BIN=""
VERIFY_ONLY=false
SMOKE_CONVERSION=false

usage() {
    cat << EOF
사용법: $0 [옵션]

옵션:
    --python [경로]       사용할 Python 실행 파일
    --venv-path [경로]    venv 생성 경로 (기본값: .venv-ml)
    --verify-only         설치 없이 현재 venv import 검증만 수행
    --smoke-conversion    작은 Keras 모델을 .mlpackage로 변환하고 .mlmodelc 컴파일까지 검증
    --help                도움말 표시

환경 변수:
    PYENV_VERSION=3.11.10  pyenv Python 3.11을 우선 사용하고 싶을 때
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --python)
            PYTHON_BIN="$2"
            shift 2
            ;;
        --venv-path)
            VENV_PATH="$2"
            shift 2
            ;;
        --verify-only)
            VERIFY_ONLY=true
            shift
            ;;
        --smoke-conversion)
            SMOKE_CONVERSION=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "[ERROR] 알 수 없는 옵션: $1" >&2
            usage
            exit 1
            ;;
    esac
done

python_version() {
    "$1" - << 'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}")
PY
}

is_python_311() {
    "$1" - << 'PY'
import sys
raise SystemExit(0 if sys.version_info[:2] == (3, 11) else 1)
PY
}

resolve_python() {
    if [ -n "$PYTHON_BIN" ]; then
        echo "$PYTHON_BIN"
        return
    fi

    if command -v python3 >/dev/null 2>&1 && PYENV_VERSION=3.11.10 python3 -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 11) else 1)' 2>/dev/null; then
        echo "PYENV_VERSION=3.11.10 python3"
        return
    fi

    if command -v python3.11 >/dev/null 2>&1 && python3.11 -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 11) else 1)' 2>/dev/null; then
        echo "python3.11"
        return
    fi

    if command -v python3 >/dev/null 2>&1; then
        echo "python3"
        return
    fi

    echo "[ERROR] python3를 찾을 수 없습니다." >&2
    exit 1
}

run_python() {
    local resolved="$1"
    shift
    if [[ "$resolved" == "PYENV_VERSION="* ]]; then
        env ${resolved%% python3} python3 "$@"
    else
        "$resolved" "$@"
    fi
}

RESOLVED_PYTHON="$(resolve_python)"

if [ "$VERIFY_ONLY" = false ]; then
    if ! run_python "$RESOLVED_PYTHON" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] == (3, 11) else 1)'; then
        echo "[WARNING] Python 3.11이 아닙니다: $(run_python "$RESOLVED_PYTHON" --version 2>&1)"
        echo "[WARNING] TensorFlow/CoreMLTools 호환성 문제가 생기면 Python 3.11 환경을 지정하세요."
    fi

    echo "[INFO] venv 생성/확인: $VENV_PATH"
    run_python "$RESOLVED_PYTHON" -m venv "$VENV_PATH"

    echo "[INFO] pip 업그레이드"
    "$VENV_PATH/bin/python" -m pip install --upgrade pip

    echo "[INFO] ML 학습 의존성 설치"
    "$VENV_PATH/bin/python" -m pip install tensorflow coremltools pillow numpy scikit-learn
fi

echo "[INFO] import 검증"
"$VENV_PATH/bin/python" - << 'PY'
import tensorflow as tf
import coremltools as ct
from PIL import Image
import numpy as np
import sklearn

print(f"tensorflow={tf.__version__}")
print(f"coremltools={ct.__version__}")
print(f"PIL={Image.__version__}")
print(f"numpy={np.__version__}")
print(f"sklearn={sklearn.__version__}")
PY

if [ "$SMOKE_CONVERSION" = true ]; then
    if ! command -v xcrun >/dev/null 2>&1; then
        echo "[ERROR] xcrun을 찾을 수 없어 .mlmodelc 컴파일 검증을 할 수 없습니다." >&2
        exit 1
    fi

    SMOKE_DIR="$(mktemp -d /tmp/clothiq-coreml-smoke.XXXXXX)"
    cleanup_smoke() {
        rm -rf "$SMOKE_DIR"
    }
    trap cleanup_smoke EXIT

    echo "[INFO] Core ML 변환 스모크 테스트"
    "$VENV_PATH/bin/python" - "$SMOKE_DIR" << 'PY'
from pathlib import Path
import sys

import coremltools as ct
import tensorflow as tf

output_dir = Path(sys.argv[1])
model_path = output_dir / "ClothIQSmoke.mlpackage"

inputs = tf.keras.Input(shape=(8, 8, 3), name="image")
x = tf.keras.layers.GlobalAveragePooling2D()(inputs)
outputs = tf.keras.layers.Dense(6, activation="sigmoid")(x)
model = tf.keras.Model(inputs, outputs)
model.compile(optimizer="adam", loss="mse")

coreml_model = ct.convert(
    model,
    source="tensorflow",
    inputs=[ct.ImageType(name="image", shape=(1, 8, 8, 3), scale=1 / 255.0)],
    minimum_deployment_target=ct.target.iOS15,
)
coreml_model.save(str(model_path))
print(model_path)
PY

    echo "[INFO] Core ML 컴파일 스모크 테스트"
    xcrun coremlcompiler compile "$SMOKE_DIR/ClothIQSmoke.mlpackage" "$SMOKE_DIR" >/dev/null
    test -d "$SMOKE_DIR/ClothIQSmoke.mlmodelc"
    echo "[SUCCESS] Core ML 변환/컴파일 스모크 테스트 통과"
fi

echo "[SUCCESS] ML 학습 환경 준비 완료"
