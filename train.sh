
# 原脚本没有 set -e：某一步失败（比如 GPU 资源竞争导致的场景创建失败）不会中止，
# 会带着缺失的 checkpoint/数据继续跑完后面几步，几秒内产生一堆看起来不相关的报错。
set -e

TASK_NAME=$1
CURRENT_TIME=$(date +"%Y%m%d_%H%M%S")
EXP_NAME=${2:-$CURRENT_TIME}


# mkdir -p "outputs/ckpts/${TASK_NAME}"
mkdir -p "outputs/${TASK_NAME}_${EXP_NAME}/ckpts"

# training refiner
python scripts/sugar_rl/train.py \
    --task "Sugar-G129dof-${TASK_NAME}-Refiner" \
    --num_envs 4096 \
    --log_dir "outputs/${TASK_NAME}_${EXP_NAME}/logs/refiner" \
    --max_iterations 30001 \
    --motion_folder "data/${TASK_NAME}" \
    --headless

cp "outputs/${TASK_NAME}_${EXP_NAME}/logs/refiner/model_30000.pt" "outputs/${TASK_NAME}_${EXP_NAME}/ckpts/refiner.pt"

# rollout refiner for training tracker
python scripts/sugar_rl/play.py \
    --task "Sugar-G129dof-${TASK_NAME}-Refiner-Rollout" \
    --num_envs 1000 \
    --checkpoint "outputs/${TASK_NAME}_${EXP_NAME}/ckpts/refiner.pt" \
    --rollout_dir "outputs/${TASK_NAME}_${EXP_NAME}/rollout_datasets/refiner/raw_npz" \
    --motion_folder "data/${TASK_NAME}" \
    --headless

python scripts/sugar_rl/process_refiner_rollout.py \
    --data_dir "outputs/${TASK_NAME}_${EXP_NAME}/rollout_datasets/refiner" --task_name "${TASK_NAME}"



# training tracker
python scripts/sugar_rl/train.py \
    --task "Sugar-G129dof-${TASK_NAME}-Tracker" \
    --num_envs 4096 \
    --teacher_ckpt "outputs/${TASK_NAME}_${EXP_NAME}/ckpts/refiner.pt" \
    --motion_folder "outputs/${TASK_NAME}_${EXP_NAME}/rollout_datasets/refiner/rl_dataset" \
    --teacher_motion_folder "data/${TASK_NAME}" \
    --log_dir "outputs/${TASK_NAME}_${EXP_NAME}/logs/tracker" \
    --max_iterations 30001 \
    --headless

cp "outputs/${TASK_NAME}_${EXP_NAME}/logs/tracker/model_30000.pt" "outputs/${TASK_NAME}_${EXP_NAME}/ckpts/tracker.pt"


# rollout tracker for training generator
python scripts/sugar_rl/play.py \
    --task "Sugar-G129dof-${TASK_NAME}-Tracker-Rollout" \
    --checkpoint="outputs/${TASK_NAME}_${EXP_NAME}/ckpts/tracker.pt" \
    --num_envs 1000 \
    --rollout_dir "outputs/${TASK_NAME}_${EXP_NAME}/rollout_datasets/tracker/raw_npz" \
    --motion_folder "outputs/${TASK_NAME}_${EXP_NAME}/rollout_datasets/refiner/rl_dataset" \
    --teacher_motion_folder "data/${TASK_NAME}" \
    --teacher_ckpt "outputs/${TASK_NAME}_${EXP_NAME}/ckpts/refiner.pt" \
    --headless

python scripts/sugar_rl/process_tracker_rollout.py  --data_dir "outputs/${TASK_NAME}_${EXP_NAME}/rollout_datasets/tracker"


# training generator
case "${TASK_NAME}" in
    "CarryBox" | "PickBox" | "PushBox")
        USE_TARGET="True"
        ;;
    "PickBottle" | "StandBottle" | "SitChair")
        USE_TARGET="False"
        ;;
    *)
esac

python scripts/sugar_il/train.py  --config-name train_generator_workspace.yaml task="${TASK_NAME}" use_target=${USE_TARGET} num_epochs=1001 log_path="outputs/${TASK_NAME}_${EXP_NAME}/logs/generator" dataset_path="outputs/${TASK_NAME}_${EXP_NAME}/rollout_datasets/tracker/il_dataset"

cp "outputs/${TASK_NAME}_${EXP_NAME}/logs/generator/epoch_checkpoints/epoch=1000.ckpt" "outputs/${TASK_NAME}_${EXP_NAME}/ckpts/generator.ckpt"

