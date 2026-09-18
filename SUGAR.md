# SUGAR 复现手册

> 本文件是对你之前那份指南的评估 + 重写。原文件已存为思路参考，本版本的目标是：**每一条命令都对照实际克隆下来的仓库代码核实过**，并且按"先跑通官方流程，暂不换数据集"的顺序组织。

---

## 0. 对原指南的评估

**做得好的地方**：Stage1→2→3 的系统性拆解是准确的，和 `README.md` / `train.sh` 对得上；对 SUGAR 与 MimicLite/SONIC/RGMT/PGMT/BFM-Zero 的定位区分抓得很准，这部分概念性认知不需要重写。

**问题**：
1. **体量失衡**：全文 3000 多行，前 38 个小节（约 60%）都在做论文间的横向对比，和"如何在 G1 上重新训练复现"这个具体任务关系不大；真正的操作步骤被稀释在后半段，可执行性反而弱。
2. **命令未核实**：原文第四十~六十几节给出的所有命令，都是从 README 转述的通用版本，没有对照这台机器的实际情况（没有 `conda`、Google Drive 需要走代理、SSH key 已配好可直接 `git@github.com` clone 等）。我已经逐条跑通/核实，见下文。
3. **缺少资源预估**：`--num_envs 4096 --max_iterations 30001` 跑两遍（Refiner+Tracker）加上 Generator 1001 epoch，在单卡 4090 上大概率是"以天为单位"的任务，原文没有给出量级预估就直接建议开跑，容易在不知情的情况下占满 GPU 一两天。
4. **新数据集部分过早展开**：你已经明确说这次先不做新数据，原文第 49~65 节关于新数据 schema/task registration 的内容目前用不上，我把它压缩成了一个"以后再做"的附录，不占主线篇幅。

下面是重写后的版本，分为「背景速览」「已核实的仓库现状」「实操手册」三部分。

---

## 1. 背景速览（精简版）

SUGAR 不是单纯的 motion tracker，而是 **human-object interaction video → 可自主闭环执行的 loco-manipulation policy** 的完整流水线：

```
RGB-D 人类视频
   → Stage 1  Kinematic Prior Extraction（人体/物体重建 + retarget + VLM contact，未开源）
   → Stage 2  Physics-based Refiner（privileged RL，把噪声轨迹修成物理可行）
   → Stage 3a Command Tracker（BC+RL 蒸馏，reference-conditioned 的底层 WBC）
   → Stage 3b Command Generator（state-based Diffusion Transformer，reference-free 高层规划）
→ 部署：Generator 生成短期 command → Tracker 执行 → PD → G1
```

和同类工作的一句话区分：

| 方法 | 高层输入 | 是否 reference tracking | 核心问题 |
|---|---|---|---|
| MimicLite | robot motion | ✅ | 高效通用 tracking |
| RGMT | 带噪 robot motion | ✅（动态加权） | noisy reference 鲁棒性 |
| SONIC | 多源 motion→统一 token | ✅ | 统一 motion 接口 |
| PGMT | motion + 地形 | ✅ | 地形感知 tracking |
| BFM-Zero | motion/goal/reward→z | 不一定 | promptable behavior，无需 per-task 重训 |
| **SUGAR** | object/task state | **最终 ❌**（Generator 阶段丢弃 reference） | 视频驱动的自主 loco-manipulation |

SUGAR 的 Command Tracker 这一层，和 MimicLite/RGMT/SONIC 是同一层的东西；SUGAR 整体比它们高一层，多了"视频→物理修复→蒸馏→去 reference 化"这条链。六个任务（CarryBox/KickBox/PushBox/PickBottle/StandBottle/SitChair）目前是**各自独立训练**，不是一个统一 foundation policy。

关于 Progressive State Pool（用 RL 自己修正成功的状态逐步替代直接从视频初始化，避免 penetration 导致仿真炸掉）、Interaction Reward（强制真实接触而不只是"姿态像"）这些设计细节，原指南的描述是准确的，不再重复展开。

---

## 2. 已核实的仓库现状

对照 `/home/yingchaomu/下载/SUGAR` 实际内容逐条核实：

| 原指南的说法 | 核实结果 |
|---|---|
| TODO 列表：inference/训练全流程/6 任务数据已开源，RGB-D→数据 pipeline 和 sim-to-sim 未开源 | ✅ 与 `README.md` 完全一致 |
| `train.sh` 顺序：Refiner→rollout→process→Tracker→rollout→process→Generator | ✅ 与仓库 `train.sh` 逐行一致，唯一遗漏：Generator 训练命令还需要 `use_target` 参数（CarryBox/PickBox/PushBox 为 `True`，PickBottle/StandBottle/SitChair 为 `False`），原指南没提到这个开关 |
| `--num_envs 4096 --max_iterations 30001` | ✅ 与 `train.sh` 一致，且 `RobotSceneCfg(num_envs=4096, ...)` 在各任务 env cfg 里也是硬编码默认值 |
| 任务注册命名 `Sugar-G129dof-{TASK}-Refiner/-Refiner-Rollout/-Tracker/-Tracker-Rollout/-Inference` | ✅ 逐一 grep `gym.register` 核实无误 |
| `play.py`/`train.py` 的 `--checkpoint/--motion_folder/--teacher_ckpt/--teacher_motion_folder/--rollout_dir/--generator_checkpoint/--eval_random_motion/--headless` 等参数 | ✅ 全部在 `scripts/sugar_rl/{train,play}.py` 的 argparse 中核实存在；`--headless` 来自标准 IsaacLab `AppLauncher.add_app_launcher_args` |
| 安装步骤（isaacsim 5.1.0 + IsaacLab v2.3.0 + rsl_rl + sugar_rl/sugar_il） | ✅ 与 `README.md` 一致 |
| `git@github.com:isaac-sim/IsaacLab.git`（SSH clone） | ✅ 本机 SSH key 已配好（`ssh -T git@github.com` 认证成功），可直接用；本手册脚本里为了避免依赖 SSH agent，统一改用了 https |

**本机与原指南假设不同的地方**（这是我做的主要修正）：
- 原指南全程用 `conda create -n sugar python=3.11`；本机**没有装 conda**，改用 `uv venv --python 3.11` 创建虚拟环境，功能等价。
- 网络访问 GitHub / PyPI / Google Drive 都走系统代理（`https_proxy=http://127.0.0.1:7897`），已确认可达，`gdown` 下载 Google Drive 文件没有问题。
- GPU 只有一张 RTX 4090（24GB），原指南"多卡"相关的默认假设不适用；下面给出的时间预估都是单卡口径。

---

## 3. 实操手册

### 3.1 环境搭建（已在后台执行）

我已经用以下脚本在后台跑起来了（日志：`logs/setup_env.log`）：

```bash
# /home/yingchaomu/下载/SUGAR/setup_local_env.sh（仓库内，已整理成最终版）
source /home/yingchaomu/下载/sugar-venv/bin/activate
uv pip install "isaacsim[all,extscache]==5.1.0" --extra-index-url https://pypi.nvidia.com
git clone https://github.com/isaac-sim/IsaacLab.git /home/yingchaomu/下载/IsaacLab
cd /home/yingchaomu/下载/IsaacLab && git checkout v2.3.0
uv pip install flatdict==4.0.1 --no-build-isolation
./isaaclab.sh --install rsl_rl
cd /home/yingchaomu/下载/SUGAR
uv pip install -e source/sugar_rl
uv pip install -e source/sugar_il
```

这一步预计下载量较大（isaacsim 全量扩展缓存通常在 10GB+），需要一些时间，完成/失败都会有通知，不需要手动轮询。

**实际踩到的两个坑（`uv venv` 特有，`conda` 环境不会遇到）**：
1. `uv venv` 建出来的环境默认**不带 `pip` 模块**，而 `isaaclab.sh --install` 内部用的是 `python -m pip install --editable ...`，直接跑会报 `No module named pip`。修复：`uv pip install pip` 装一下。
2. isaacsim 依赖链会把 `setuptools` 升到 `84.x`，这个版本已经**不再自带 `pkg_resources`**；而官方要求的 `pip install flatdict==4.0.1 --no-build-isolation` 恰好需要 `pkg_resources` 来跑它的 legacy `setup.py`，装的时候会报 `ModuleNotFoundError: No module named 'pkg_resources'`。修复：装 flatdict 之前先 `uv pip install "setuptools<81"` 降级一下。
3. `isaaclab.sh --install` 内部有个 `install_system_deps`：只要 `command -v cmake` 找不到，就会 `sudo apt-get install cmake build-essential`，在无人值守/无 sudo 密码的环境里会卡死在 `sudo: 需要密码`。这台机器本来就有 `build-essential`（g++/gcc/make 都在），只缺 `cmake`；不用 sudo，直接 `uv pip install cmake` 把 PyPI 上的 cmake 二进制包装进 venv 的 `bin/` 让它在 PATH 里可见，`command -v cmake` 检测就能通过，绕开 apt。

修好之后按顺序补跑：`uv pip install flatdict==4.0.1 --no-build-isolation` → `uv pip install cmake` → `./isaaclab.sh --install rsl_rl` → `uv pip install -e source/sugar_rl` → `uv pip install -e source/sugar_il`。

4. `sugar_il` 的依赖会把 `torch` 从 isaacsim 装的 `2.7.0+cu128` 拉低到 `2.5.1+cu124`（连带一批 `nvidia-*-cu12` 库也被降级）。已验证 `torch.cuda.is_available()` 在降级后依旧是 `True`，本机驱动 580.159.03/CUDA 13.0 向下兼容 cu124 没问题，训练脚本能正常拿到 GPU，目前判断可以接受，先不去纠正这个版本，等真的遇到 isaacsim 侧因为 torch 版本报错再处理。
5. `import isaacsim` 首次运行会弹一个**交互式 EULA 确认**（`Do you accept the EULA? (Yes/No)`），非交互终端里直接卡死变成 `EOF when reading a line` 导致脚本判失败。解决：跑任何 isaacsim/IsaacLab 相关命令前先 `export OMNI_KIT_ACCEPT_EULA=Y`（源码位置 `isaacsim/kit/kit_app.py`，只认 y/yes/1）。**这个环境变量后面所有训练/推理命令都需要带上**，不只是装环境这一步。

### 3.2 数据下载（已在后台执行）

日志：`logs/download_data.log`，用 `uvx --from gdown gdown <id>` 拉取，不占用 sugar-venv：

```bash
uvx --from gdown gdown 1AIJWqS5rFGl5u2Qq6jCCTHKdh51SX2Sc -O data.zip          # ~400MB
uvx --from gdown gdown 1wXNAjNMrfV0e-d2pQ6m9dm4xrG5lSoyD -O descriptions.zip  # ~50MB
uvx --from gdown gdown 1Uc2SPPVvTboEgw4Scyuz3TmzNKDg-dx- -O demo_ckpts.zip    # ~250MB
```

完成后应该在 `SUGAR/` 下得到 `data/{TASK}/...`、`descriptions/`、`demo_ckpts/{TASK}/{tracker.pt,generator.ckpt}`。

### 3.3 M0：官方已训练策略的 inference sanity check

这是"复现训练好的策略"这个目标里最直接的一步，两个后台任务都完成后立刻可以跑：

```bash
source /home/yingchaomu/下载/sugar-venv/bin/activate
export OMNI_KIT_ACCEPT_EULA=Y
cd /home/yingchaomu/下载/SUGAR
bash inference.sh CarryBox
```

`inference.sh` 内部等价于：

```bash
python scripts/sugar_rl/play.py --task Sugar-G129dof-CarryBox-Inference \
    --checkpoint demo_ckpts/CarryBox/tracker.pt \
    --generator_checkpoint demo_ckpts/CarryBox/generator.ckpt \
    --motion_folder data/CarryBox \
    --num_envs 16 --eval_random_motion
```

目标不是看动作好不好看，而是确认 IsaacSim / IsaacLab / task registry / G1 USD / 物体 asset / tracker+generator checkpoint 全部能正常加载执行。成功后再依次跑 `KickBox / PushBox / SitChair / StandBottle / PickBottle`。

**已在本机验证通过**：`Sugar-G129dof-CarryBox-Inference`，16 个环境、`--eval_random_motion`、`--headless`，跑了 10 分钟无报错——IsaacSim 启动、G1 URDF 导入、CarryBox 任务与物体 asset 实例化、`demo_ckpts/CarryBox/{tracker.pt,generator.ckpt}` 加载并驱动仿真全部正常。日志末尾有个 `carb.tasking` 的 `Recursion not allowed` assertion，是外部 `timeout` 命令在仿真中途发 `SIGTERM` 导致关闭流程被打断的产物，不是 SUGAR 自身的 bug（`play.py` 在 `--eval_random_motion` 模式下本来就是持续跑，没有自然退出点，用 `--eval_max_time` 可以让它自己收尾退出）。

> 注：脚本默认不加 `--headless`，会尝试开 GUI 窗口。本机 `DISPLAY=:1` 存在，你在本机桌面跑没问题；如果我用工具在无交互终端里跑，我会加 `--headless` 做自动化验证，你自己复现时想看可视化效果就去掉这个参数。

### 3.4 M1：完整单任务训练复现（train.sh CarryBox）

**官方算力/耗时口径**（来自论文 arXiv 2605.20373 附录 D，已核实，不是估算）：单卡 RTX 5090、4096 并行环境、24 steps/env/iteration；Refiner ≈20 GPU-小时，Tracker ≈20 GPU-小时，Command Generator ≈5 GPU-小时，**单任务合计约 45 GPU-小时（不到 2 天）**。本机 RTX 4090 吞吐略低于 5090，预计单任务实际耗时会比这个数字略长，但量级一致，不是原来保守估计的"以天计"那么夸张。六个任务彼此独立训练，Refiner→Tracker→Generator 在单任务内部严格串行（后一阶段依赖前一阶段 rollout），但**任务之间完全可以并行**——手上有多台服务器的话，一台服务器跑一个任务是最高效的分配方式。

已确认可以不用为算力/时长找人确认，直接按下面顺序执行：

1. 先用**官方 `data/CarryBox` 数据 + 默认 `--num_envs 4096`**跑 Refiner，训练命令见下；
2. **不要跳步**：Refiner 收敛后，rollout 出来的数据人工抽查几十条轨迹，确认物体真的被抓住/推动而不是"看起来像"→再进 Tracker → Tracker 用 expert command 测试扰动恢复能力 → 再进 Generator。每一级都要看对应指标（object trajectory tracking、contact success、penetration、fall/termination rate），不要只看 reward 曲线。

对应命令（`train.sh` 已经把这一串串起来了，如果你要一键跑）：

```bash
source /home/yingchaomu/下载/sugar-venv/bin/activate
export OMNI_KIT_ACCEPT_EULA=Y
cd /home/yingchaomu/下载/SUGAR
bash train.sh CarryBox reproduce_carrybox
```

拆开单独跑（建议第一次复现这样做，方便定位问题出在哪一级）：

```bash
# Refiner
python scripts/sugar_rl/train.py \
    --task Sugar-G129dof-CarryBox-Refiner --num_envs 4096 --max_iterations 30001 \
    --motion_folder data/CarryBox \
    --log_dir outputs/CarryBox_reproduce/logs/refiner --headless

# Refiner rollout → 供 Tracker 用
python scripts/sugar_rl/play.py \
    --task Sugar-G129dof-CarryBox-Refiner-Rollout --num_envs 1000 \
    --checkpoint outputs/CarryBox_reproduce/ckpts/refiner.pt \
    --rollout_dir outputs/CarryBox_reproduce/rollout_datasets/refiner/raw_npz \
    --motion_folder data/CarryBox --headless

python scripts/sugar_rl/process_refiner_rollout.py \
    --data_dir outputs/CarryBox_reproduce/rollout_datasets/refiner --task_name CarryBox

# Tracker
python scripts/sugar_rl/train.py \
    --task Sugar-G129dof-CarryBox-Tracker --num_envs 4096 --max_iterations 30001 \
    --teacher_ckpt outputs/CarryBox_reproduce/ckpts/refiner.pt \
    --motion_folder outputs/CarryBox_reproduce/rollout_datasets/refiner/rl_dataset \
    --teacher_motion_folder data/CarryBox \
    --log_dir outputs/CarryBox_reproduce/logs/tracker --headless

# Tracker rollout → 供 Generator 用
python scripts/sugar_rl/play.py \
    --task Sugar-G129dof-CarryBox-Tracker-Rollout --num_envs 1000 \
    --checkpoint outputs/CarryBox_reproduce/ckpts/tracker.pt \
    --rollout_dir outputs/CarryBox_reproduce/rollout_datasets/tracker/raw_npz \
    --motion_folder outputs/CarryBox_reproduce/rollout_datasets/refiner/rl_dataset \
    --teacher_motion_folder data/CarryBox \
    --teacher_ckpt outputs/CarryBox_reproduce/ckpts/refiner.pt --headless

python scripts/sugar_rl/process_tracker_rollout.py \
    --data_dir outputs/CarryBox_reproduce/rollout_datasets/tracker

# Generator（注意 CarryBox 属于 use_target=True 的一组，见下）
python scripts/sugar_il/train.py --config-name train_generator_workspace.yaml \
    task=CarryBox use_target=True num_epochs=1001 \
    log_path=outputs/CarryBox_reproduce/logs/generator \
    dataset_path=outputs/CarryBox_reproduce/rollout_datasets/tracker/il_dataset
```

`use_target` 开关（`train.sh` 里的逻辑，原指南没提到）：

```
CarryBox / PickBox / PushBox   → use_target=True
PickBottle / StandBottle / SitChair → use_target=False
```

### 3.5 换新数据集（Phase 2，本次不做，仅存档）

结论不变：官方 **RGB-D 视频 → SUGAR processed 数据**这段 pipeline 没开源，换新数据本质是要自己把新数据（不管来自 GVHMR/GMR 重建还是别的）拼成和官方 `data/{Task}/data_XXX/` 一样的 schema，再挂到新的 `TASK_NAME` 走一遍 3.4 的流程。

**真实 schema（已用 `data/CarryBox/data_000/` 实测核实，不是猜的）**，每条轨迹一个目录，三个文件，50Hz，约 481~500 帧（约 10 秒）：

```
robot_50hz.npz
    fps               (1,)         int32
    joint_pos         (T, 29)      float32   # G1 29 DoF
    joint_vel         (T, 29)      float32
    body_pos_w        (T, 35, 3)   float32   # 35 个 body，世界系位置
    body_quat_w       (T, 35, 4)   float32   # 世界系四元数
    body_lin_vel_w    (T, 35, 3)   float32
    body_ang_vel_w    (T, 35, 3)   float32

obj_motion_global_50hz.pkl   (dict)
    obj_trans   (T, 3)      # 世界系位置
    obj_rot     (T, 3, 3)   # 旋转矩阵，不是四元数
    obj_scale   float 或 None
    obj_lin_vel (T, 3)
    obj_ang_vel (T, 3)

contact_labels_50hz.npy      (T,) bool     # 接触标签，per-frame
```

注意 `obj_rot` 是 **3x3 旋转矩阵**而不是四元数，这个和原指南猜测的"quaternion order"不是一回事，换数据时容易在这里翻车。`joint_pos`/`joint_vel` 的 29 维顺序需要和 `descriptions/robots/g1/g1_29dof_rev_1_0_with_rubber_hand.urdf` 里的关节定义顺序对齐，建的时候直接照这个 URDF 走，不要凭经验猜 G1 关节序。

官方每任务规模：论文口径是 100 条训练 + 30 条测试（做过 20→50→100 的数据量消融）；实测下载到的 processed data 里，CarryBox 100 条、KickBox 99 条、PushBox 104 条、PickBottle 103 条、StandBottle 104 条、SitChair 73 条，合计 583 条、565MB。

---

## 4. 当前状态 / 下一步

| Milestone | 状态 |
|---|---|
| M0 环境搭建（isaacsim+IsaacLab+sugar_rl/sugar_il） | ✅ 本机已完成（踩坑记录见 3.1） |
| M0 官方数据/checkpoint 下载 | ✅ 已完成，规模统计见 3.5 |
| M0 inference.sh 跑通（复现"训练好的策略"） | ✅ 已验证，`CarryBox` 16 环境跑 10 分钟无报错，见 3.3 |
| M1 六任务并行完整重训 | 🔄 已转移到 Noetix-0 服务器 8×4090，一卡一任务，见第 5 节 |
| M2 新数据集替换 | ⏸️ 按你的要求，本次不做，schema 已在 3.5 存档 |

> 本机原本单独跑的 `train.sh CarryBox reproduce_carrybox`（3.4 节命令）中途因为机器意外重启而丢失（进度到 Refiner iter 4218/30001），不再补跑——六任务已经整体转移到服务器并行做，本机的 `outputs/CarryBox_reproduce_carrybox/` 是这次中断留下的部分产物，仅供参考，不是最终结果来源。

---

## 5. 服务器多机部署（Noetix-0，8×RTX4090，一卡一任务）

### 5.1 架构

参考你之前 SONIC 项目 `codex_local_control_multi_node_training.md` 的思路，但简化掉了 NCCL/多机 rendezvous 那一套——SUGAR 六个任务本来就是互相独立训练，不是一个 DDP world，所以是"单机多任务"而不是"多机单任务"：

```text
本地开发机（控制面）
  ├─ 修改 SUGAR.md / 脚本，commit、push 到 GitHub
  ├─ SSH 发起服务器环境搭建、tmux 训练启动
  └─ SSH 隧道查看 TensorBoard
                  │
                  ▼
         GitHub（代码唯一真源）
      github.com/Mu-Yingchao/SUGAR
                  │
                  ▼
        Noetix-0（118.196.95.17，8×4090）
  GPU0 CarryBox   GPU1 KickBox   GPU2 PushBox
  GPU3 PickBottle GPU4 StandBottle GPU5 SitChair
  （GPU6/7 空闲，可用于消融实验或额外 seed）
```

服务器信息：

```text
外网 IP:    118.196.95.17
内网 IP:    172.31.0.32
密钥:       /home/yingchaomu/下载/Noetix-2-7.pem
用户:       root
项目路径:   /data0/SUGAR_repro/SUGAR（数据盘 /data0，1.9TB 空）
conda env:  sugar (python 3.11)
```

### 5.2 GitHub 作为代码同步媒介

仓库：`https://github.com/Mu-Yingchao/SUGAR`（你自己的 fork，`origin`），原始上游 `tianshuwu/SUGAR` 保留为 `upstream` 方便以后同步官方更新。

`.gitignore` 已经排除 `data`/`descriptions`/`outputs`/`demo_ckpts`/`logs` 等大文件目录（上游仓库自带的规则本来就是对的），本地/服务器改动闭环：

```bash
# 本地改完
cd /home/yingchaomu/下载/SUGAR
git status --short
git add <明确文件列表>
git commit -m "..."
git push origin main

# 服务器拉取（只快进，不 reset）
ssh Noetix-0
cd /data0/SUGAR_repro/SUGAR
git pull --ff-only origin main
```

数据/权重/日志这类大产物不走 Git，继续用 `rsync` 在本机和服务器之间同步（`data`/`descriptions`/`demo_ckpts` 已经用这个办法同步过一次，本机和服务器条数核对完全一致）。

### 5.3 服务器访问 GitHub 不稳定的问题

这台服务器直连 `github.com` **部分不稳定**（小仓库能 clone 成功，大一点的传输容易 SSL timeout——今晚 clone IsaacLab 时反复复现过），后来发现这是已知问题，之前给 Noetix-9 部署过 Docker Clash 的方案在这台机器上试了，但**那个订阅当前所有节点都是 Timeout**（大概率订阅过期，不是配置问题）。

最终用的是 `Yuanjie 服务器通过 SSH RemoteForward 使用本地Clash操作指南` 里的方法：**让服务器复用本机正在工作的 Clash**，不需要服务器自己有可用订阅：

```text
服务器程序 → 服务器 127.0.0.1:7898 → SSH RemoteForward 加密隧道 → 本机 127.0.0.1:7897 → 本机 Clash → Internet
```

本机 `~/.ssh/config` 新增：

```sshconfig
Host Noetix-0
    HostName 118.196.95.17
    User root
    IdentityFile /home/yingchaomu/下载/Noetix-2-7.pem
    IdentitiesOnly yes
    RemoteForward 7898 127.0.0.1:7897
    ExitOnForwardFailure yes
    ServerAliveInterval 30
    ServerAliveCountMax 6
```

**这条隧道依赖一个常驻的本机 SSH 连接**（`ssh -F ~/.ssh/config -N Noetix-0` 后台跑着），本机关机/断网/这条 SSH 断开，服务器的代理就会失效——不是服务器自己在运行代理，是在借用本机的。服务器 `~/.bashrc` 已加入：

```bash
export http_proxy=http://127.0.0.1:7898
export https_proxy=http://127.0.0.1:7898
export HTTP_PROXY=http://127.0.0.1:7898
export HTTPS_PROXY=http://127.0.0.1:7898
export ALL_PROXY=socks5h://127.0.0.1:7898
export all_proxy=socks5h://127.0.0.1:7898
export no_proxy=localhost,127.0.0.1,172.31.0.0/16
```

排查顺序（服务器又连不上外网时）：本机 Clash 是否正常（`curl -x http://127.0.0.1:7897 https://api.ipify.org`）→ 服务器 7898 是否在监听（`ss -lnt | grep 7898`，没有说明隧道断了，本机重新 `ssh Noetix-0`）→ 服务器走隧道测试（`curl -x http://127.0.0.1:7898 https://api.ipify.org`）→ 服务器默认代理是否生效（`curl https://api.ipify.org`，不用 `-x` 也应该出代理 IP）。

服务器上跑 `git`/`pip` 之前，确认 `env | grep -i proxy` 里是 `7898` 且隧道通，就不会再复现今晚 IsaacLab clone 反复超时的问题了。

### 5.4 环境搭建（服务器）

```bash
ssh Noetix-0
mkdir -p /data0/SUGAR_repro && cd /data0/SUGAR_repro
git clone https://github.com/Mu-Yingchao/SUGAR.git SUGAR
# IsaacLab 仓库较大，建议直接从本机 rsync 已 clone 好的 v2.3.0，不要在服务器上重新 git clone：
#   rsync -ah --exclude='.git' -e "ssh -i ~/下载/Noetix-2-7.pem" \
#     ~/下载/IsaacLab/ root@118.196.95.17:/data0/SUGAR_repro/IsaacLab/
bash /data0/SUGAR_repro/SUGAR/setup_server_env.sh
```

### 5.5 六任务并行启动

```bash
ssh Noetix-0
bash /data0/SUGAR_repro/SUGAR/launch_all_tasks.sh
```

脚本内容：六个任务分别 `CUDA_VISIBLE_DEVICES=0..5` 绑定，各自独立 tmux session（`sugar_CarryBox` ... `sugar_SitChair`），跑 `train.sh {TASK} server_repro`，断开 SSH 不影响训练。查看：

```bash
tmux ls                      # 列出 6 个 session
tmux attach -t sugar_CarryBox   # 进去看，Ctrl+B D 退出不杀进程
```

### 5.6 监控：TensorBoard + 终端日志

官方 Refiner/Tracker（rsl_rl）和 Generator（accelerate）默认都写 TensorBoard，不需要 wandb 账号（见第 2 节已核实）。服务器上起一个统一实例，把 6 个任务的 `outputs/*/logs/` 都纳进来：

```bash
ssh Noetix-0
tmux new -s tensorboard -d \
  "source /root/miniconda3/etc/profile.d/conda.sh && conda activate sugar && \
   tensorboard --logdir /data0/SUGAR_repro/SUGAR/outputs --host 0.0.0.0 --port 6006"
```

本机看：

```bash
ssh -N -L 16006:localhost:6006 Noetix-0
# 浏览器打开 http://127.0.0.1:16006
```

> 本机端口选 `16006` 而不是 `6006`：本机 `6006~6010` 这几个端口当时全被 VS Code 占用了（`ss -lntp` 查出来的），换成大家都不会用的端口最省事，不用先去杀谁占用的进程。

终端级别的日志在 `logs/train_{TASK}.log`（`launch_all_tasks.sh` 用 `tee` 写的），可以直接 `tail -f` 看 `Metrics/motion/error_obj_pos`、`Episode_Reward/hoi_contact`、`Episode_Termination/obj_pos` 这几个最能反映"抓没抓稳"的指标，不用只看 reward 曲线。

### 5.7 服务器上实际踩到的两个坑

**1. `isaacsim.asset.importer.urdf` 报 `ERROR_INCOMPATIBLE_DRIVER` / Vulkan 初始化失败**

`inference.sh`/`train.sh` 第一次在服务器上跑时报了一堆：

```text
[Error] [carb.graphics-vulkan.plugin] VkResult: ERROR_INCOMPATIBLE_DRIVER
[Error] [gpu.foundation.plugin] Failed to create any GPU devices
```

排查发现是系统级 Vulkan loader 包 `libvulkan1` 没装（`find /usr/lib -iname 'libvulkan.so*'` 完全找不到，`ldconfig -p | grep vulkan` 也是空的）——NVIDIA 驱动、ICD json（`/etc/vulkan/icd.d/nvidia_icd.json`）、`libGLX_nvidia.so.0` 都在，就是缺这层 loader 胶水层。修复：

```bash
unset http_proxy https_proxy   # apt 走的是云厂商内网镜像，不能走代理
apt-get install -y libvulkan1
```

装完后 `ERROR_INCOMPATIBLE_DRIVER` 消失，换成一批 "Driver Version: 0 / GPUs do not support RayTracing / GPU Foundation is not initialized" 的警告——这些是 Kit 的**可视化渲染子系统**在纯计算节点上天生用不了（没有显示输出，RT 核心探测不到），跟 PhysX 物理仿真是两条完全独立的路径。用一次 50-iteration 的 Refiner 冒烟测试直接验证过：GPU 利用率能到 56~62%、iteration 时间 2.8s，物理仿真确确实实在用 GPU，这些渲染报错可以放心当噪音忽略，不影响训练。

**2. 六任务同时启动，几个任务几秒内报一堆不相关的错**

第一次用 `launch_all_tasks.sh` 六个任务同时拉起来，PushBox/StandBottle 正常，另外四个（CarryBox/KickBox/PickBottle/SitChair）几秒内就把 `train.sh` 的 Refiner→rollout→Tracker→rollout→Generator 七步全部"跑"完了，报的错五花八门（`FileNotFoundError: tracker.pt`、`KeyError('obj_pos_b')`……）看起来毫不相关。

去查第一个任务（CarryBox）日志里**真正**的第一个 traceback，根因是：

```text
ValueError: No contact sensors added to the prim: '/World/envs/env_0/Robot'.
Unresolved reference prim path ...g1_29dof_rev_1_0_with_rubber_hand.usd@<defaultPrim>...
```

六个进程同时对 G1 URDF 做运行时 URDF→USD 转换（写到 `/tmp/IsaacLab/usd_<timestamp>_<id>/`），资源竞争导致部分转换产物是坏的（USD 里 `defaultPrim` 引用解析不到，机器人身上一个刚体都没挂上），场景创建直接抛异常。而官方 `train.sh` **没有 `set -e`**，Refiner 这步崩了之后不会停，会带着不存在的 checkpoint/数据文件继续往后跑完剩下六步，每一步都秒级失败，看起来像一堆互不相干的报错，其实全是同一个根因的级联产物。

修复两处：
- `train.sh` 开头加了 `set -e`，以后任何一步真的失败会立刻停，不会再级联出一堆迷惑性报错。
- `launch_all_tasks.sh` 六个任务改成**错峰启动**，每起一个 `sleep 30` 再起下一个，让每个任务先跑过 URDF→USD 转换 + 建场这个约 15~20 秒的窗口再让下一个开始抢资源。

错峰重启后六个任务全部正常：GPU0~5 利用率 47~61%，显存 7~10GB，都有真实递增的 `Learning iteration`。这两处修复已经提交进仓库（`train.sh`、`launch_all_tasks.sh`），以后重新跑不会再复现。

**3.（小坑）`~/.bashrc` 里的 `[ -z "$PS1" ] && return`**

非交互 SSH 命令（`ssh host "some command"`）里 `source ~/.bashrc` 会在这一行直接 return，后面写的代理环境变量、conda init 全部不会生效——`git fetch`/`pip` 等命令表现得像没配代理一样卡死。非交互命令里不要指望 `source ~/.bashrc` 生效，要么在命令里显式 `export http_proxy=...`，要么用 `bash -lc "..."`（login shell 会走 `.bash_profile`/`.profile`，不会踩这个 return）。

---

## 6. 训练效果评估：怎么看、看到了什么

### 6.1 官方评估方式（已核实，不是猜的）

`rsl_rl`（Refiner/Tracker）和 `sugar_il` 的 `accelerate`（Generator）都**默认写 TensorBoard**，不用 wandb 账号。终端每个 iteration 打印一份统计表，但只能看"最新一条"；要看趋势必须拉 TensorBoard 的时间序列。TensorBoard 本身有个 HTTP 数据接口，不一定非要开浏览器，也可以直接 `curl` 拉数值做自动化分析：

```bash
# 本机开着到 16006 的隧道（见 5.6），直接查询某个 run 某个 tag 的完整时间序列
curl -s "http://127.0.0.1:16006/data/plugin/scalars/scalars?run=CarryBox_server_repro%2Flogs%2Frefiner&tag=Train%2Fmean_reward"
```

返回是 `[[wall_time, step, value], ...]` 的 JSON 数组，可以直接拿 Python/`jq` 处理，比人肉盯着 TensorBoard 网页方便，也适合写进自动化的健康检查脚本。

### 6.2 该看哪几个 tag

不要只看 `Train/mean_reward`——reward 数值本身容易被"刷分"，真正说明任务有没有做成的是：

| Tag | 含义 | 怎么解读 |
|---|---|---|
| `Episode_Termination/trajectory_complete` | 完整跑完整条参考轨迹而不是中途失败终止的回合比例 | **最重要的单一指标**，直接反映"任务真的做成了"；应该从 0 持续爬升到接近 1 |
| `Episode_Reward/hoi_contact` | human-object-interaction 接触奖励 | 应该持续上升，反映"真的抓/推/踢到了物体"而不是打空气 |
| `Metrics/motion/error_obj_pos` / `error_obj_rot` | 物体位置/姿态追踪误差 | **训练初期数值小是假象**：回合几步就终止，误差只算了很短一段；等 `trajectory_complete` 涨起来之后，这个误差才是对完整轨迹的真实评估，数值这时候不降反升不代表变差，是统计口径变了（分母从"几步"变成"全程"） |
| `Episode_Termination/obj_pos` | 因为"物体丢了/位置超差"而终止的回合比例 | 应该持续下降，这个如果一直很高说明物体总是被弄丢/推飞 |

### 6.3 目前（Refiner 训练约 11.5 小时，进度 50~57%）的实测结果

```text
                    Mean reward (iter 18 → 现在)          trajectory_complete (iter 18 → 现在)
CarryBox       ~0 → 19.5（涨幅趋缓）                       0% → 90.5%
KickBox        ~0 → 25.4（涨势最猛）                       0% → 93.7%
PushBox        ~0 → 25.2（趋于平稳）                        0% → 97.3%
PickBottle     ~0 → 15.1                                  0% → 95.9%
StandBottle    ~0 → 17.9                                  0% → 75.7%（最难，仍在持续爬升，没有停滞）
SitChair       ~0 → 18.3                                  0% → 97.1%
```

六个任务全部从"训练刚开始几步就失败"涨到 75%+ 的轨迹完整率，是健康的 PPO 学习曲线，没有发散/停滞/reward hacking 的迹象。StandBottle 明显是六个任务里最难的一个，但也在持续进步（29%→76%），不是卡住了。

---

## 7. 部署指南

### 7.1 先厘清一个概念："Play" ≠ Sim-to-sim ≠ Sim-to-real

你问"官方没开源 sim-to-sim，那能不能 play"——这两件事完全不冲突，是三个不同层次的东西：

| 层次 | 是什么 | SUGAR 官方开源了吗 |
|---|---|---|
| **Play（推理）** | 在 **训练用的同一个 IsaacSim 仿真器**里跑训练好的策略，看它能不能完成任务 | ✅ 开源了，就是 `inference.sh` / `scripts/sugar_rl/play.py`，我们昨晚已经在本机和服务器上都验证过 |
| **Sim-to-sim** | 把策略从 IsaacSim **迁移到另一个仿真器**（一般是 MuJoCo，更快、更轻量，常用作上真机前的中间验证） | ❌ 没开源，README TODO 里明确写着 |
| **Sim-to-real** | 部署到 **真实 G1 机器人** | ❌ 不在这个仓库范围内，需要自己接 Unitree SDK/低层控制 |

所以结论是：**能 play，而且现在就能跑**——只是这个"play"是在 IsaacSim 内部看效果，不等于能直接一键部署到 MuJoCo 或者真机。要往真机走，中间那层 sim-to-sim（策略怎么从 IsaacSim 的观测/动作空间对齐到 MuJoCo/真实关节控制）需要你自己搭，这部分可以复用你之前 SONIC/G1/Bumi 项目里积累的 sim2sim/sim2real 经验，不是从零开始。

### 7.2 部署官方已训练好的策略（demo_ckpts，现在就能跑）

```bash
# 本机（有 DISPLAY，能看 GUI 窗口）
source /home/yingchaomu/下载/sugar-venv/bin/activate
export OMNI_KIT_ACCEPT_EULA=Y
cd /home/yingchaomu/下载/SUGAR
bash inference.sh CarryBox        # 去掉 --headless，会弹 IsaacSim 窗口
```

```bash
# 服务器（无 DISPLAY，headless，用 --video 录成 mp4 带回本机看）
ssh Noetix-0
source /root/miniconda3/etc/profile.d/conda.sh && conda activate sugar
export OMNI_KIT_ACCEPT_EULA=Y
cd /data0/SUGAR_repro/SUGAR
python scripts/sugar_rl/play.py --task Sugar-G129dof-CarryBox-Inference \
    --checkpoint demo_ckpts/CarryBox/tracker.pt \
    --generator_checkpoint demo_ckpts/CarryBox/generator.ckpt \
    --motion_folder data/CarryBox \
    --num_envs 4 --eval_random_motion --eval_max_time 500 \
    --video --video_length 500 \
    --headless
# 视频存在 demo_ckpts/CarryBox/videos/play/（log_dir 是 checkpoint 所在目录）
```

`--eval_max_time` 给回合设一个明确的步数上限，跑完自己退出，不用再靠外部 `timeout` 硬杀（我们昨晚那次本机测试就是因为没设这个，最后被 `timeout` 杀掉触发了一个无害的 `carb.tasking` assertion）。六个任务名：`CarryBox / KickBox / PushBox / PickBottle / StandBottle / SitChair`，`inference.sh` 直接换第一个参数即可。

把视频取回本机看：

```bash
scp -i /home/yingchaomu/下载/Noetix-2-7.pem \
  root@118.196.95.17:/data0/SUGAR_repro/SUGAR/demo_ckpts/CarryBox/videos/play/*.mp4 \
  /home/yingchaomu/下载/
```

### 7.3 部署我们自己训出来的策略（训练还没跑完，命令先准备好）

`train.sh` 跑完一个任务后，`tracker.pt`/`generator.ckpt` 落在：

```text
outputs/{TASK}_server_repro/ckpts/tracker.pt
outputs/{TASK}_server_repro/ckpts/generator.ckpt
```

`inference.sh` 支持传第 2/3 个参数指定 checkpoint 路径（不传就用 `demo_ckpts` 默认值），所以跑我们自己的策略就是：

```bash
ssh Noetix-0
source /root/miniconda3/etc/profile.d/conda.sh && conda activate sugar
export OMNI_KIT_ACCEPT_EULA=Y
cd /data0/SUGAR_repro/SUGAR
bash inference.sh CarryBox \
  outputs/CarryBox_server_repro/ckpts/tracker.pt \
  outputs/CarryBox_server_repro/ckpts/generator.ckpt
```

想要 headless + 录视频 + 用自己的 checkpoint，就是把 7.2 服务器那条命令里的 `--checkpoint`/`--generator_checkpoint` 换成上面这两个路径，`--video` 存放路径也会跟着变成 `outputs/CarryBox_server_repro/ckpts/videos/play/`。

想把训完的 checkpoint 拉回本机（比如要接你自己的 sim2sim/sim2real pipeline）：

```bash
rsync -ah -e "ssh -i /home/yingchaomu/下载/Noetix-2-7.pem" \
  root@118.196.95.17:/data0/SUGAR_repro/SUGAR/outputs/CarryBox_server_repro/ckpts/ \
  /home/yingchaomu/下载/SUGAR/outputs/CarryBox_server_repro/ckpts/
```

**现在能跑这条命令的前提**：`train.sh` 对应任务要跑完全部三个阶段（Refiner→Tracker→Generator）。目前（见第 6 节）六个任务都还在 Refiner 阶段（50~57%），预计还要 8~12 小时才能进入 Tracker，全部跑完大概还要 1.5~2 天（见 3.4 节的算力估算）。中途也可以用 Refiner/Tracker 阶段各自产出的 rollout 数据做检查，但 `inference.sh` 这条完整推理链路要等 Generator 训完才有意义（它需要 `generator.ckpt`）。

### 7.4 MuJoCo sim2sim 部署代码：`sugar_deploy`（独立仓库）

7.1 节说的"能 play 但没开源 sim-to-sim"——这个缺口已经动手补了一版，单独放在
`/home/yingchaomu/下载/sugar_deploy`（不塞进 SUGAR 训练仓库，原因和详细说明见它自己的 README）。

用官方 `demo_ckpts/CarryBox` 实测过：两个 checkpoint（`tracker.pt` + `generator.ckpt`）都能正确加载，
整条 Tracker/Generator 数据流跑得通，物理数值稳定（修过一次显式 Euler 积分器 + 偏硬 PD 增益导致的数值
发散）。**目前机器人还站不稳**（~1 秒内瘫软倒地），大概率是箱子尺寸/目标位置占位值不准确，具体排查
思路在 `sugar_deploy/README.md` 的"已知问题 / 下一步排查"一节。

关节顺序、PD 增益、观测组成、36 维 command 结构这些契约，都是逐条从 SUGAR 源码核实出来的，来源标注
在 `sugar_deploy/contract.py`；Generator 部分直接复用了 SUGAR 自己 `play.py` 在用的
`GeneratorWrapper`，没有重新实现（过程中发现训练 yaml 写的是 `DDIMScheduler`，但实际推理路径用的是
`DDPMScheduler`，自己重新拼一遍很容易在这类细节上出错）。
