#!/usr/bin/env bash
# SUGAR 本机环境搭建（uv venv 替代 conda，单卡 RTX 4090）
# 已在 /home/yingchaomu/下载/SUGAR 验证通过，踩坑记录见 SUGAR.md 3.1
set -euo pipefail

DOWNLOADS="/home/yingchaomu/下载"
VENV="${DOWNLOADS}/sugar-venv"
ISAACLAB_DIR="${DOWNLOADS}/IsaacLab"
SUGAR_DIR="${DOWNLOADS}/SUGAR"

if [ ! -d "${VENV}" ]; then
    uv venv --python 3.11 "${VENV}"
fi
source "${VENV}/bin/activate"
echo "[1/6] python: $(which python) $(python --version)"

# uv venv 默认不带 pip 模块，isaaclab.sh 内部用 `python -m pip` 会报错
uv pip install pip

echo "[2/6] installing isaacsim 5.1.0 ..."
uv pip install "isaacsim[all,extscache]==5.1.0" --extra-index-url https://pypi.nvidia.com

echo "[3/6] cloning IsaacLab v2.3.0 ..."
if [ ! -d "${ISAACLAB_DIR}" ]; then
    git clone https://github.com/isaac-sim/IsaacLab.git "${ISAACLAB_DIR}"
fi
cd "${ISAACLAB_DIR}"
git checkout v2.3.0

# isaacsim 依赖链会把 setuptools 升到 84.x，该版本不再自带 pkg_resources，
# 而 flatdict==4.0.1 的 legacy setup.py 需要它，这里先降级
uv pip install "setuptools<81"
uv pip install flatdict==4.0.1 --no-build-isolation

# isaaclab.sh --install 找不到 cmake 时会尝试 sudo apt-get，
# 无人值守/无 sudo 密码环境下会卡死；直接用 PyPI 的 cmake 二进制绕开
uv pip install cmake

echo "[4/6] installing IsaacLab + rsl_rl ..."
./isaaclab.sh --install rsl_rl

echo "[5/6] installing sugar_rl / sugar_il ..."
cd "${SUGAR_DIR}"
uv pip install -e source/sugar_rl
uv pip install -e source/sugar_il

echo "[6/6] verifying isaacsim import ..."
# isaacsim 首次导入会要求交互式接受 EULA，非交互环境必须设这个变量
export OMNI_KIT_ACCEPT_EULA=Y
python -c "import isaacsim; print('isaacsim OK')"

echo "DONE: local environment setup complete"
