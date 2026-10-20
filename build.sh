#!/bin/bash
# ============================================
# Qwen2.5-VL-3B RK3588 交叉编译脚本
# ============================================

set -euo pipefail

# ----------------- 可配置变量 -----------------
BUILD_DIR="build"
BUILD_TYPE="Release"
TEST_ENV_PREFIX="./test"        # 安装目标目录
JOBS=${JOBS:-1}
TOOLCHAIN_FILE="cmake/toolchain-buildroot.cmake"

# 获取脚本所在的项目根目录
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

# 工具链路径
TOOLCHAIN_DIR="$HOME/toolchains/buildroot-gcc13.3"

# 将工具链 bin 加入 PATH（提供 cmake / make / 交叉编译器）
export PATH="${TOOLCHAIN_DIR}/bin:${PATH}"
# ---------------------------------------------

echo "=========================================="
echo " Qwen2.5-VL-3B RK3588 交叉编译"
echo " 项目目录: ${PROJECT_ROOT}"
echo " 工具链:   ${TOOLCHAIN_FILE}"
echo "=========================================="

# 1. 创建必要的目录
mkdir -p "${PROJECT_ROOT}/${BUILD_DIR}"
mkdir -p "${PROJECT_ROOT}/${TEST_ENV_PREFIX}"

# 2. 进入构建目录并配置 CMake
cd "${PROJECT_ROOT}/${BUILD_DIR}"

echo ""
echo "[1/4] 配置 CMake (交叉编译, Build Type: ${BUILD_TYPE}) ..."
cmake .. \
    -DCMAKE_BUILD_TYPE="${BUILD_TYPE}" \
    -DCMAKE_TOOLCHAIN_FILE="../${TOOLCHAIN_FILE}" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

# 3. 编译
echo ""
echo "[2/4] 开始编译 (使用 ${JOBS} 个并行任务) ..."
cmake --build . -j"${JOBS}"

# 4. Strip 二进制（减小体积）
echo ""
echo "[3/4] Strip 二进制 ..."
"${TOOLCHAIN_DIR}/bin/aarch64-linux-strip" \
    "${PROJECT_ROOT}/VLM_NPU" 2>/dev/null || true

# 5. 安装到测试环境
echo ""
echo "[4/4] 安装到测试环境: ${TEST_ENV_PREFIX} ..."
cmake --install . --prefix "${PROJECT_ROOT}/${TEST_ENV_PREFIX}"

# 返回项目根目录
cd "${PROJECT_ROOT}"

echo ""
echo "=========================================="
echo " 构建完成！"
echo ""
echo " 可执行文件: ${PROJECT_ROOT}/VLM_NPU"
echo " 安装目录:   ${TEST_ENV_PREFIX}/"
echo "   ├── bin/VLM_NPU"
echo "   ├── lib/  (运行时库)"
echo "   └── models/ (模型文件)"
echo ""
echo " 板端运行: cd /mnt/qwen_vl && ./run_board.sh"
echo "=========================================="
