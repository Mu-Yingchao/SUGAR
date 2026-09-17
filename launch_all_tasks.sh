#!/usr/bin/env bash
# 在服务器上执行：6 个任务分别绑定 GPU0-5，tmux 会话后台跑 train.sh
set -euo pipefail

cd /data0/SUGAR_repro/SUGAR
source /root/miniconda3/etc/profile.d/conda.sh
conda activate sugar
export OMNI_KIT_ACCEPT_EULA=Y

TASKS=(CarryBox KickBox PushBox PickBottle StandBottle SitChair)

for i in "${!TASKS[@]}"; do
    TASK="${TASKS[$i]}"
    GPU=$i
    SESSION="sugar_${TASK}"
    tmux kill-session -t "$SESSION" 2>/dev/null || true
    tmux new-session -d -s "$SESSION" \
      "cd /data0/SUGAR_repro/SUGAR && \
       source /root/miniconda3/etc/profile.d/conda.sh && conda activate sugar && \
       export OMNI_KIT_ACCEPT_EULA=Y && \
       export CUDA_VISIBLE_DEVICES=${GPU} && \
       bash train.sh ${TASK} server_repro 2>&1 | tee logs/train_${TASK}.log"
    echo "launched ${TASK} on GPU${GPU} in tmux session ${SESSION}"
done

echo
echo "tmux sessions:"
tmux ls
