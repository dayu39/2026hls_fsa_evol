# C：五组交错调度

- 日期：2026-11-18。
- 唯一来源：`diego3893/FSA_HLS` 的 `4a6fe4762f139075c4208d7729f2acf8e7957822`。
- 本候选只修改 `src/stream/split_d/split_d_controller.cpp`；`include/`、其余 `src/`、`tests/`、`hls/fsa_stream_split_d/run_hls.tcl` 和 `run_hls.sh` 均来自同一提交。
- 修改：让五个独立feature组按lane轮流发射wave，分别保存pv_sum；最后一批无效lane保留空操作。
- 待检验假设：验证真实反馈距离增为5后II是否下降；风险是状态、动态选择和最后一批空操作增加面积与总迭代数。

## 运行

本机数学检查（Ubuntu WSL、Vitis 2024.2 头文件）：

```powershell
.\validate_local.ps1
```

远端 Vitis HLS 2024.2 检查（每个候选单独放一个目录）：

```bash
bash ./validate_candidate.sh
```

脚本固定 `PE_DIM=16`、`HEAD_DIM=128`、VU37P、10ns/2.7ns；运行官方 CSim 和 CSynth，关闭 CoSim、IP 导出与 1024 长用例。结果在 `logs/validation.log` 及 `hls/fsa_stream_split_d/fsa_stream_split_d_build/solution1/`。脚本发现已有构建时会停止，避免覆盖证据。

## 对照与判据

对照提交 `4a6fe476`：CSim 数学 22/22；顶层 LUT 1,072,241、FF 245,431、DSP 352、BRAM_18K 8、估算时钟 7.300ns；PV 内部循环 12,401 周期、II25。原 baseline `ebe529b` 的 PV 同级循环 10,886 周期、LUT 1,213,113。

先检查 CSim 数学结果与异常输入、CSynth 退出码，再记录两个 worker 的 PV 循环 latency/II、顶层资源与估算时钟、RTL 中 `runPeArray` 实例数。达到原 baseline 的周期门槛要求 PV 内部循环 <10,886；同时要求 LUT <1,213,113、器件/时钟/接口/256PE 合同不变。HLS 达标后再考虑 CoSim 和物理实现；本地 C++ 测试不能替代它们。

本候选尚未在 NM37 运行官方 Vitis 验收。三个候选互相独立，不要叠加源码或复用彼此的构建目录。

## 当前本地结果

WSL g++ 编译通过；16×16/head128 数学 22/22、`[PASS]`。日志：`build/local_split_d_check/validate_local.log`。这不是官方 Vitis CSim/CSynth 结果。