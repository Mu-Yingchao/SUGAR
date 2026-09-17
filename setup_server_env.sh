#!/usr/bin/env bash
# SUGAR 服务器环境搭建（conda，8×RTX4090，root 用户）
# 已在 Noetix-0 (/data0/SUGAR_repro) 验证通过，踩坑记录见 SUGAR.md
#
# 用法：先把本机已经 clone 好的 v2.3.0 IsaacLab 目录 rsync 到
#   ${ISAACLAB_DIR}（排除 .git），再运行本脚本。
# 原因：这台服务器对 github.com 的直连不稳定（部分请求 SSL timeout），
#   IsaacLab 仓库较大，容易在 git clone 阶段反复失败；SUGAR 本身仓库很小
#   通常可以直接 git clone 成功。更稳妥的长期方案见 SUGAR.md 里的
#   「SSH RemoteForward 借用本机 Clash」章节。
set -euo pipefail

REPRO_DIR=/data0/SUGAR_repro
ISAACLAB_DIR="${REPRO_DIR}/IsaacLab"
SUGAR_DIR="${REPRO_DIR}/SUGAR"

source /root/miniconda3/etc/profile.d/conda.sh
if ! conda env list | grep -q '^sugar '; then
    conda create -n sugar python=3.11 -y
fi
conda activate sugar
echo "[1/6] python: $(which python) $(python --version)"

echo "[2/6] installing isaacsim 5.1.0 ..."
pip install "isaacsim[all,extscache]==5.1.0" --extra-index-url https://pypi.nvidia.com

[ -d "${ISAACLAB_DIR}/isaaclab.sh" ] || [ -f "${ISAACLAB_DIR}/isaaclab.sh" ] || {
    echo "ERROR: ${ISAACLAB_DIR} 不存在，请先从本机 rsync 过来（见脚本头部说明）"
    exit 1
}
cd "${ISAACLAB_DIR}"

echo "[3/6] system deps + flatdict (root 用户，apt 不需要 sudo) ..."
apt-get update -qq && apt-get install -y --no-install-recommends cmake build-essential -qq
# isaacsim 依赖链会把 setuptools 升到不再自带 pkg_resources 的版本，
# flatdict==4.0.1 的 legacy setup.py 需要它，这里先降级
pip install "setuptools<81"
pip install flatdict==4.0.1 --no-build-isolation

echo "[4/6] installing rsl_rl (内部会重装 torch+cu128，下载量较大) ..."
for attempt in 1 2 3; do
    if ./isaaclab.sh --install rsl_rl; then
        break
    fi
    echo "rsl_rl install attempt ${attempt} failed, retrying in 10s..."
    sleep 10
done
python -c "import torch; print('torch', torch.__version__, torch.cuda.is_available())"

echo "[5/6] installing sugar_rl / sugar_il ..."
cd "${SUGAR_DIR}"
pip install -e source/sugar_rl
pip install -e source/sugar_il

echo "[6/6] verifying isaacsim import ..."
export OMNI_KIT_ACCEPT_EULA=Y
python -c "import isaacsim; print('isaacsim OK')"

echo "DONE: server environment setup complete"
