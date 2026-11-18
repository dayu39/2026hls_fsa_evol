# PV 计算瓶颈：三个独立候选实验

日期：2026-11-18  
基准源码：`diego3893/FSA_HLS`，提交 `4a6fe4762f139075c4208d7729f2acf8e7957822`（`opt/split-d-baseline-20261014`）。

## 实验包

| 候选 | 独立目录 | 只改变的设计源码 | 待验证假设 | 主要风险 |
| --- | --- | --- | --- | --- |
| A：分离累加阶段 | `2026-11-18_PV分离累加阶段/` | `src/stream/split_d/split_d_controller.cpp` | 把 PE wave 和输出累加分成两个循环，让输出累加不受 PE 反馈 II 约束 | 循环启动开销或模块复制抵消收益 |
| B：静态行状态映射 | `2026-11-18_PV静态行状态映射/` | 同上 | 将 PE 部分和按行传递，缩小动态 context 选择逻辑 | 反馈距离仍为 1，II 可能不降 |
| C：五组交错调度 | `2026-11-18_PV五组交错调度/` | 同上 | 五组 feature 轮流执行，让同组反馈距离成为 5 | 更多状态和最后一批空操作增加面积与周期 |

三个目录都含各自可独立运行的 `include/`、`src/`、`tests/`、`hls/fsa_stream_split_d/`、`run_hls.sh`，不依赖另外两个目录。每个目录的 `README_实验说明.md` 给出具体改动、运行命令与风险。对照原提交逐文件 SHA256 核查后，各目录的设计源码差异都只有上表所列的一个文件；接口、数据位宽、PE 数量、器件、时钟约束、测试用例没有修改。

## 已完成的本地验证

每个候选均已使用 WSL Ubuntu 24.04、g++ 13.3 和本机 Vitis 2024.2 头文件，编译原有完整 `test_fsa_stream_split_d.cpp` 测试程序。配置为 16×16 PE、head128；三个候选分别得到数学检查 `22/22` 和 `[PASS]`。各目录中的 `build/local_split_d_check/` 保留日志。复查命令：

```powershell
cd <候选目录>
.\validate_local.ps1
```

这一步验证 C++ 功能，不代表 Vitis HLS CSim、CSynth、CoSim 或板级验收已通过。当前尚未访问 NM37。

## 接通验收环境后的运行方式

将三个目录分别复制到 NM37 上的三个独立路径。每个候选目录里执行一次：

```bash
bash ./validate_candidate.sh
```

脚本会加载 `/opt/Xilinx_2024.2/Vitis/2024.2/settings64.sh`，固定 16×16 PE、head128，运行原仓库 `run_hls.sh` 的官方 CSim 与 CSynth，并关闭 CoSim、IP 导出和 1024 长序列用例。完整输出写入各自的 `logs/validation.log`；发现已有 HLS 构建目录时会停止，避免覆盖首次结果。不要把三个候选的源码叠加，也不要共用构建目录。

验收时先确认 CSim 的 `22/22`、`[PASS]`、异常输入路径和综合退出码，再从两个 worker 的综合报告记录 PV 循环 II/latency、顶层 LUT/FF/DSP/BRAM、估算时钟和 RTL 中 `runPeArray` 实例数。当前对照提交 `4a6fe476` 的 PV 内部循环为 12,401 周期、II=25，顶层 LUT 1,072,241、FF 245,431、DSP 352、BRAM_18K 8、估算时钟 7.300 ns。原始 baseline `ebe529b` 的同级 PV 循环为 10,886 周期、LUT 1,213,113。只有实测周期、资源及功能同时满足约束，才考虑合并候选或继续优化。
