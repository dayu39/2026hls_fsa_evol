# PV 阵列内邻行归约实验

起点：已验收的 B 版本 `4bc3ca3fb11fb124107dba53707fce7343f17f51`。本目录是独立副本，不覆盖 B 的源码和证据。

> 验证结果：CSim 22/22、CSynth 通过；PV 循环降至 1,325 周期，但顶层最小延迟升至 11,647 周期、LUT 升至 1,177,179。该实现不是新的整体性能最佳版本。详见[综合报告](./综合报告.md)和[验收报告](./验收报告.md)。

## 假设

B 的 PV 外层循环有 `pv_row_sum` 距离 1 的真实 RAW 依赖，Vitis 报告 II=10、4,961 周期。本实验让一次共享 `runPeArray` 调用处理同一个 feature 的全部 key row：第 0 行从零开始，每行的 FP32 部分和直接送到下一行，最后一行给出完整 PV 部分和。目标是把跨循环的部分和反馈移到 PE 阵列内，观察调度能否减少完整 PV 阶段周期。

## 唯一设计改动

1. `split_d_internal.hpp`：为共享 `runPeArray` 增加默认关闭的 `pv_row_chain` 参数。
2. `split_d_compute.cpp`：PV 模式下把前一行 `out_accType` 作为本行 `operand_c`；其他模式沿用原输入。
3. `split_d_controller.cpp`：PV 阶段每个 feature 调用一次上述模式，读取末行结果；原 `output_acc` 更新逻辑不变。

该改动保留每列 `row=0..PE_DIM-1` 的累加顺序和原有 FP32 FMA 算术。外层 PV 循环由每组 `PE_DIM+2*PV_INTERLEAVE-1` 次改为 `2*PV_INTERLEAVE` 次；较少的迭代次数并不保证更低的实际周期，因为阵列内多了逐行数据依赖。须以正式 CSynth 的完整 PV 循环 latency、II、顶层资源和 `runPeArray` 实例数判定。

实验副本的 shell/Tcl 文件已统一为 LF，以便 WSL 和 Linux 执行；算法相关变化仅限上面三处。验证配置维持 16×16 PE、head128、目标器件和时钟约束不变。

## 验证

本地功能检查：`./validate_local.ps1`。

远端 Vitis HLS 2024.2：在本目录执行 `bash ./validate_candidate.sh`；脚本运行 CSim 和 CSynth，关闭 RTL CoSim 与 IP 导出。不得复用 B 的构建目录。

判定时与 B 的 22/22、4,961 周期、II=10、LUT 1,055,705、FF 241,737、DSP 352、顶层估算 7.300 ns 对照。HLS 通过不等于 Vivado 物理实现或板测通过。
