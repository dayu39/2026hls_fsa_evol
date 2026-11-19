# PV 邻行状态传递实验：Vitis HLS 性能归因分析

> 分析日期：2026-11-19。比较对象是已验收的 B 版本 `4bc3ca3fb11fb124107dba53707fce7343f17f51` 与本实验源码 `05cc7029bfe1a9fbe682b7b8fe14957d3c9506e4`。本文件分析**相同器件、相同时钟约束**下的 Vitis HLS 2024.2 C 综合估算；周期数不是板上实测吞吐率。

## 1. 结论先行

这次改动验证了“把 PV 的逐 key row 累加放进 PE 阵列”在**PV 局部循环**上有效：两个 PV worker 的关键循环均由 4,961 拍、II=10 降至 1,325 拍、II=5，减少 3,636 拍（73.29%）。

但**顶层最小延迟**从 9,403 升至 11,647 拍，增加 2,244 拍（23.86%）。决定性的新证据是 QK 循环：128 次迭代未变，却从 1,283 拍、II=10 升至 6,403 拍、II=50。其每次调用的共享 `runPeArray` 从 9 拍变成 49 拍。QK 的 `score_acc` 是跨迭代反馈，因此阵列调用的 II 虽仍为 5，**包含该反馈的 QK 循环无法每 5 拍启动一次**。

面积也明显退步：顶层 LUT 增加 121,474，FF 增加 269,908。`runPeArray` 自身增加 138,766 FF 和 68,192 LUT，其中新增的 64,352 个 Register 类 LUT 占该模块 LUT 增量约 94.37%。这些是综合估算，不等同于布局布线结果。当前方案适合保留为架构实验，不宜代替 B 成为整体性能起点。

## 2. 对照条件与唯一改动

| 条件 | B 与本实验 |
| --- | --- |
| 工具、器件 | Vitis HLS 2024.2 Build 5238294；`xcvu37p_CIV-fsvh2892-2-e` |
| 时钟 | 目标 10.00 ns；不确定度 2.70 ns |
| 规模 | 16×16 PE，`HEAD_DIM=128`，`PV_INTERLEAVE=8` |
| 验证范围 | 本实验 CSim 22/22、0 errors；CSynth 完成。RTL CoSim、IP 导出、Vivado 实现及板测未运行 |

本实验在 [`runPeArray`](./src/stream/split_d/split_d_compute.cpp) 中增加 `pv_row_chain` 模式：PV 第 `row>0` 行的 FP32 FMA 加数取上一行的 `out_accType`。[`PV 控制循环`](./src/stream/split_d/split_d_controller.cpp) 每个 feature 调用一次该模式，只保存末行部分和，再执行原有的输出累加。QK 源码中的累加算法未改，但 QK 与 PV 复用同一个 `runPeArray` 硬件模块；该模块的综合结构因新模式发生了变化。

## 3. 三层性能数据

| 位置与指标 | B | 本实验 | 变化 |
| --- | ---: | ---: | ---: |
| PV worker 0/1 关键循环，周期 | 4,961 | 1,325 | −3,636（−73.29%） |
| PV 循环 II / trip count | 10 / 496 | 5 / 256 | II 减半；迭代减少 240 |
| QK 累加循环，周期 | 1,283 | 6,403 | +5,120（+399.06%） |
| QK 循环 II / trip count | 10 / 128 | 50 / 128 | II 扩大 5 倍；迭代不变 |
| 共享 `runPeArray` 调用 latency / II | 9 / 5 | 49 / 5 | 调用延迟 +40；模块 II 不变 |
| 顶层 `run` 最小延迟，周期 | 9,403 | 11,647 | +2,244（+23.86%） |

PV 数据见本次的 [worker 0](./evidence/runQueryBlock_0_Pipeline_VITIS_LOOP_365_33_csynth.rpt)、[worker 1](./evidence/runQueryBlock_1_Pipeline_VITIS_LOOP_365_33_csynth.rpt)，B 的对照见[原 B 验证报告](https://github.com/dayu39/2026hls_fsa_evol/blob/experiments/pv-three-candidates-20261118/2026-11-18_PV静态行状态映射/验证报告.md)。QK 的两份原始循环报告分别是 [B](./evidence/baseline_B_QK_loop_csynth.rpt) 与[本实验](./evidence/neighbor_chain_QK_loop_csynth.rpt)。顶层数据见[本次顶层报告](./evidence/fsa_stream_split_d_csynth.rpt)及原 B 验证报告。

### 为什么 PV 快了，顶层反而慢了？

1. **PV 的外部反馈被消除。** B 把每个 key row 的部分和保存在 `pv_row_sum`，下一次外层迭代再读取。新的单次阵列调用内部完成逐行传递，外层从 496 次迭代缩到 256 次，II 从 10 缩到 5。PV 循环报告的 1,325 拍接近 `256×5` 加流水填充与收尾开销。
2. **QK 需要反复使用同一行的 `score_acc`。** [`runPeAccumulateTile`](./src/stream/split_d/split_d_compute.cpp) 的 `block/lane` 循环把上一次 `runPeArray` 输出的 `score_acc` 作为下一次加数。原本阵列调用延迟为 9 拍时，QK 循环实现 II=10；改成 49 拍后，QK 循环实现 II=50。128 次迭代对应的循环周期从约 `128×10` 变为约 `128×50`，与报告的 1,283→6,403 拍吻合。这里的瓶颈是**跨迭代反馈延迟**，不是 `runPeArray` 的独立吞吐 II。
3. **共享模块使 PV 改动传播到 QK。** `runPeArray` 的 `pv_row_chain=false` 仅决定运行时数据选择，HLS 仍须为同一模块综合 PV 邻行链。没有证据表明 QK 的数学运算或迭代次数被改动；两份 QK 循环报告直接显示同一个子模块调用延迟从 9 升到 49。

QK 循环的 +5,120 拍与 PV 循环的 −3,636 拍解释了顶层为何没有享受到 PV 局部收益。**不能把两数直接相加作为顶层变化**：顶层有其他阶段、控制与可能的流水重叠，且循环报告和顶层最小延迟属于不同层级。顶层实际对照结果以 +2,244 拍为准。

## 4. 面积增加落在哪里

| 综合估算资源 | B `runPeArray` | 本实验 `runPeArray` | 模块增量 | B 顶层 | 本实验顶层 | 顶层增量 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| DSP | 128 | 128 | 0 | 352 | 352 | 0 |
| FF | 61,365 | 200,131 | +138,766 | 241,737 | 511,645 | +269,908 |
| LUT | 378,796 | 446,988 | +68,192 | 1,055,705 | 1,177,179 | +121,474 |
| BRAM_18K | 0 | 0 | 0 | 8 | 8 | 0 |

根据 [B 的 `runPeArray` 原始报告](./evidence/baseline_B_runPeArray_csynth.rpt)与[本实验报告](./evidence/runPeArray_csynth.rpt)，模块 LUT 的分类变化为：Expression 345,092→348,932（+3,840），Instance 33,664→33,664，Multiplexer 40→40，Register 0→64,352。因而本次 LUT 增量主要体现在**流水寄存器相关逻辑**，不能笼统说是“新增多路选择器占了主要面积”。FF 增量与调用延迟增加也符合更深流水的现象；本次 Vitis 日志记录 `runPeArray` 的流水深度为 50。

两个 query worker 各有共享 `runPeArray` 实例；DSP 总量仍为 352，没有看到再复制整套 PE 阵列的资源迹象。单模块增量乘以两个 worker 与顶层增量数量级接近，但 HLS 各层的资源统计可能有共享、优化和额外控制开销，**不能据此精确拆分顶层每个 LUT 或 FF 的来源**。

## 5. 时钟与物理实现风险

顶层估算时钟在两版均为 7.300 ns；目标 10.00 ns 减去 2.70 ns 不确定度也正好是 7.300 ns。换言之，HLS 估算没有显示正的时序余量。模块内部估算从 7.095 ns 升至 7.293 ns，虽仍低于 7.300 ns 有效预算，但余量只剩 0.007 ns；这里仅是 HLS 层估算，不是 Vivado 的最终 WNS。

顶层 LUT 由器件总量 1,303,680 的约 80.98% 增至 90.30%，仅按总量计算还剩 126,501 个 LUT。新 `runPeArray` 单模块估算为 446,988 LUT，超过报告给出的单 SLR 可用 434,560 LUT。它提示跨 SLR 布局与布线压力，**不能直接推断综合或实现必然失败**；需要 Vivado 实现才能判断最终资源、拥塞和时序。

## 6. 对后续优化的建议

下一轮应以 B 为对照，优先解决“PV 邻行链拉长 QK 反馈路径”的问题。候选改动的验收门槛不应只看 PV 的 II：至少同时检查 `runPeArray` latency、QK 循环 II 与周期、PV 双 worker 周期、顶层最小延迟及 LUT/FF。目标是在保留 PV 外层 II=5 收益时，让 QK 的 128 次累加不要再被 49 拍的共享调用反馈限制。

可探索对 QK 与 PV 做受控的综合结构隔离，或缩短 PV 邻行链的单次调用深度；但完全复制一套 PE 阵列可能超出当前 LUT 余量，应先用小范围 CSynth 验证资源。当前报告只证明了现有实现的瓶颈位置，**尚未证明任何替代结构能够同时满足性能和面积约束**。

## 7. 证据与复核口径

- [正式 Vitis 运行日志](./evidence/validation.log)：CSim `22/22`、`0 errors`，以及 CSynth 完成时间。
- [B 的 QK 循环报告](./evidence/baseline_B_QK_loop_csynth.rpt)、[本实验的 QK 循环报告](./evidence/neighbor_chain_QK_loop_csynth.rpt)：128 次迭代、II=10→50、1,283→6,403 拍。
- [B 的 PE 报告](./evidence/baseline_B_runPeArray_csynth.rpt)、[本实验的 PE 报告](./evidence/runPeArray_csynth.rpt)：调用延迟、II、分类资源与估算时钟。
- [本实验 PV worker 0](./evidence/runQueryBlock_0_Pipeline_VITIS_LOOP_365_33_csynth.rpt)、[worker 1](./evidence/runQueryBlock_1_Pipeline_VITIS_LOOP_365_33_csynth.rpt)、[顶层报告](./evidence/fsa_stream_split_d_csynth.rpt)。B 的顶层和 PV 原始报告见[原 B 实验证据](https://github.com/dayu39/2026hls_fsa_evol/tree/experiments/pv-three-candidates-20261118/2026-11-18_PV静态行状态映射/evidence)。

报告中只比较同口径的 `run` **最小延迟**。顶层最大延迟取决于输入路径及动态循环边界，不适合直接当作固定长度的板上执行时间。本次未进行 RTL CoSim、Vivado 物理实现或上板测试。
