#!/bin/sh
set -e

DIR=/mnt/qwen_vl
MODELS=/root/qwen_models

if [ -z "${1}" ]; then
    IMAGE="$DIR/images/Moon.jpg"
else
    IMAGE="$1"
fi

export LD_LIBRARY_PATH="/usr/bin/rkailib/lib:$DIR/lib:/usr/lib"

echo "=========================================="
echo " Qwen2.5-VL-3B on RK3588"
echo "=========================================="
echo " 图片: $IMAGE"
echo " 模型: $MODELS"
echo " <image> + 问题 或 exit 退出"
echo "=========================================="

exec "$DIR/VLM_NPU" "$IMAGE" \
    "$MODELS/qwen2.5-vl-3b_vision_rk3588.rknn" \
    "$MODELS/qwen2.5-vl-3b-instruct_w8a8_rk3588.rkllm" \
    512 2048
