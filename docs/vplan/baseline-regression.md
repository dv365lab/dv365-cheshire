# 验证计划：六项基础回归（Baseline Regression）

本计划按 [`cheshire-vplan`](https://github.com/dv365lab/dv365-cheshire/blob/main/.github/skills/cheshire-vplan/SKILL.md) 的流程编写，对象是 [`article.md` 第 6 章](https://github.com/dv365lab/dv365-cheshire/blob/main/article.md#ch06)「建立六项基础回归」所定义的基础层回归。它把已有的六项测试整理成特性、激励、检查、证据与边界，是后续专项 vPlan 的基线参照；它**不**新增测试，也**不**声称本文档生成时重新执行过仿真。

## 0. 元数据

| 项 | 值 |
| --- | --- |
| 特性 / 数据通路 | 基础层回归：取指与启动、UART、一维 / 二维 DMA、Serial Link 远端访问、非缓存 SPM 别名取指、外部 AXI 内存执行 |
| 版本 / 日期 | v1.0 / 2026-10-31 |
| 作者 | DV365 Lab（由 Copilot 按仓库资料整理） |
| 基线提交 | 文档核对基线 `8abfcc3`（`article.md` 第 29 章的核对提交）；已有通过记录来自 2026-10-04 的运行（[`README.md` 第 1 节](https://github.com/dv365lab/dv365-cheshire/blob/main/README.md)） |
| 硬件配置 | `DefaultCfg`（`SelectedCfg=0`，[`tb_cheshire_pkg.sv`](https://github.com/dv365lab/dv365-cheshire/blob/main/target/sim/src/tb_cheshire_pkg.sv)）；`UseDramSys=0`，外部内存为 `axi_sim_mem` |
| 工具组合 | README 实测组合：Bender 0.32.1、Python 3.11.16、xPack RISC-V GCC 15.2.0-1、主机 G++ 8.5.0、Xcelium `26.03-a071`（Rocky Linux 8.10） |
| 运行参数 | `BOOTMODE=0 PRELMODE=1 SEED=1`（Serial Link 预加载，`Makefile.xcelium` 默认值） |
| 状态 | 六项均有通过记录（见第 7 节「状态」列的来源）；本文档本身未执行仿真 |
| 执行环境 | 构建与 lint 可在 CI / 云端 Copilot coding agent 完成；第 7 节的全部仿真只能在有 Xcelium 许可证的 Linux 机器上执行 |

## 1. 目标与范围

- 目标：证明默认配置的 Cheshire SoC 在 Xcelium 中能够完成「加载 → 启动 → 执行 → 返回码」的完整闭环，并且六条互不相同的数据通路各自正确。
- 范围内：`sw/tests/` 中六个 ELF 在默认配置、Serial Link 预加载下的功能正确性；Makefile 层的 PASS / FAIL 判定；证据与负向实验。
- 范围外：AXI-RT / CLIC / vCLIC 配置、JTAG / UART / MEMH 预加载、自主启动（`BOOTMODE=2/3`）、DRAMSys 时序、FPGA、Linux 启动、性能数字。
- 与回归分层的关系（[`article.md` 第 26.5 节](https://github.com/dv365lab/dv365-cheshire/blob/main/article.md#ch26)）：本计划是「基础层」；快速层取其中 `helloworld.spm.elf` 与 `dma_1d.spm.elf`；专项层另立 vPlan。

## 2. 特性清单

| ID | 特性 | 来源 | 数据通路 | 优先级 |
| --- | --- | --- | --- | --- |
| F-01 | Boot ROM 在 `BOOTMODE=0` 下等待外部预加载，VIP 经 Serial Link 写入 ELF 段并写入入口与启动信号 | [`tb_cheshire_soc.sv`](https://github.com/dv365lab/dv365-cheshire/blob/main/target/sim/src/tb_cheshire_soc.sv)（`preload_mode == 1` 分支）、[`vip_cheshire_soc.sv`](https://github.com/dv365lab/dv365-cheshire/blob/main/target/sim/src/vip_cheshire_soc.sv)（`slink_elf_run`、`slink_wait_for_eoc`）、[`hw/bootrom/cheshire_bootrom.S`](https://github.com/dv365lab/dv365-cheshire/blob/main/hw/bootrom/cheshire_bootrom.S) | 启动 | 高 |
| F-02 | 从 SPM（LLC 配置为 scratchpad，入口 `0x10000000`）取指执行 | [`sw/link/spm.ld`](https://github.com/dv365lab/dv365-cheshire/blob/main/sw/link/spm.ld)、`docs/tg/xcelium_zh.md` 第 6.2 节 | 取指 | 高 |
| F-03 | CLINT `mtime` 与 `mcycle` 频率测量，UART 波特率配置与发送 | [`sw/tests/helloworld.c`](https://github.com/dv365lab/dv365-cheshire/blob/main/sw/tests/helloworld.c)（`clint_get_core_freq(rtc_freq, 2500)`、`uart_init`、`uart_write_str`）、[`sw/include/dif/clint.h`](https://github.com/dv365lab/dv365-cheshire/blob/main/sw/include/dif/clint.h)、[`sw/include/dif/uart.h`](https://github.com/dv365lab/dv365-cheshire/blob/main/sw/include/dif/uart.h) | 外设 | 高 |
| F-04 | iDMA 一维阻塞搬运：源 / 目标经非缓存别名（`+0x04000000`），目标尾部 `"!\0"` 保护，逐字节比较 | [`sw/tests/dma_1d.spm.c`](https://github.com/dv365lab/dv365-cheshire/blob/main/sw/tests/dma_1d.spm.c)、[`sw/include/dif/dma.h`](https://github.com/dv365lab/dv365-cheshire/blob/main/sw/include/dif/dma.h)（`sys_dma_blk_memcpy`） | DMA | 高 |
| F-05 | iDMA 二维搬运：每轮 15 字节、目标步长 7、源步长 1、重复 4 次，目标区域重叠覆盖 | [`sw/tests/dma_2d.spm.c`](https://github.com/dv365lab/dv365-cheshire/blob/main/sw/tests/dma_2d.spm.c)（`sys_dma_2d_blk_memcpy(dst, src, sizeof(src_cached) - 4, 7, 1, 4, ...)`） | DMA | 高 |
| F-06 | CPU 经 Serial Link 写远端（本地非缓存地址 `+0x100000000`），DMA 从远端读回本地并比较 | [`sw/tests/dma_slink.spm.c`](https://github.com/dv365lab/dv365-cheshire/blob/main/sw/tests/dma_slink.spm.c)；远端由 VIP 中 `MAPPED=1`、`RAND_RESP=0` 的 AXI 从设备模型承接（`docs/tg/xcelium_zh.md` 第 8.3 节） | 远端 | 高 |
| F-07 | DMA 覆盖已执行过的代码后，从非缓存 SPM 别名重新取指得到新代码 | [`sw/tests/spm_uncached.spm.c`](https://github.com/dv365lab/dv365-cheshire/blob/main/sw/tests/spm_uncached.spm.c)（`payload1` / `payload2`，64 字节，`outcome1 + outcome2 == 3`） | 取指 / 缓存 | 高 |
| F-08 | 程序链接到外部 AXI 内存（入口 `0x80000000`），经 LLC 路径从 `axi_sim_mem` 执行并输出 UART | [`sw/link/dram.ld`](https://github.com/dv365lab/dv365-cheshire/blob/main/sw/link/dram.ld)、`vip_cheshire_soc.sv`（`gen_dramsys` 之外的 `axi_sim_mem` 分支） | 数据 / 外部内存 | 高 |
| F-09 | 返回码协议：CRT0 写 `scratch[2] = (ret << 1) | 1`，VIP 轮询 bit 0 并右移，0 → `SUCCESS`，非 0 → `FAILED: return code N` | [`sw/lib/crt0.S`](https://github.com/dv365lab/dv365-cheshire/blob/main/sw/lib/crt0.S)（`slli t0, a0, 1` / `ori t0, t0, 1`）、`vip_cheshire_soc.sv`（`slink_wait_for_eoc`） | 结束判定 | 高 |

## 3. 激励策略

### 3.1 定向场景

六项全部是定向测试，激励由裸机程序产生，参数固定：

| 场景 | 初始状态 | 触发操作 | 独立预期结果 | 完成条件 | 失败条件 |
| --- | --- | --- | --- | --- | --- |
| S-01 Hello World（SPM） | ELF 预加载到 `0x10000000`，Boot ROM 等待 | 读 RTC 频率、测核心频率、初始化 UART、写字符串 | `[UART] Hello World!` 由 VIP 从 DUT 串口信号解码得到 | `main()` 返回 0 | 无 UART 文本、奇偶错误、返回码非 0 |
| S-02 DMA 一维 | 源字符串写入非缓存别名；目标尾部预写 `"!\0"` | `sys_dma_blk_memcpy` 搬运 18 字节 | 目标等于 `"This is a DMA test!"`，尾部保护未被覆盖 | 传输 ID 完成 | 不一致字节数 > 0（作为返回码） |
| S-03 DMA 二维 | 同上 | 15 字节 × 4 轮，目标步长 7，源步长 1 | 目标等于 `"This ishis is is is as is a DMA test!"`（重叠覆盖后的预期） | 传输完成 | 不一致字节数 > 0 |
| S-04 Serial Link 远端 | 检查 DMA 与 Serial Link 存在 | CPU 写远端 → DMA 从远端读回本地非缓存目标 | 目标等于 `"This is a DMA test!"` | 传输完成 | `CHECK_ASSERT` 返回 -1 / -2，或不一致字节数 > 0 |
| S-05 非缓存取指 | 执行 `payload1` 使其进入缓存 | DMA 用 `payload2` 的 64 字节覆盖 `payload1`，再从 `+0x04000000` 别名执行 | `outcome1 + outcome2 == 3` | 两次执行返回 | 取到旧指令导致和不为 3 |
| S-06 Hello World（DRAM） | ELF 预加载到 `0x80000000`（`axi_sim_mem`） | 同 S-01 | 同 S-01，入口为 `0x80000000` | `main()` 返回 0 | 同 S-01 |

### 3.2 随机化

本计划不使用随机激励。`SEED=1` 只固定 SV 侧随机（`-svseed`）；换种子不改变裸机程序行为。专项 vPlan 若引入随机（长度、地址低位、区域、背压、并发），按 `article.md` 第 20.6 节逐项增加并保存种子。

### 3.3 参数与配置

| 机制 | 本计划使用 | 读取位置 |
| --- | --- | --- |
| plusarg | `+BINARY=<abs path>`、`+BOOTMODE=0`、`+PRELMODE=1`，由 `Makefile.xcelium` 的 `XRUN_RUN_FLAGS` 生成 | `tb_cheshire_soc.sv` 的 `$value$plusargs` |
| 模块参数 | `SelectedCfg=0`、`UseDramSys=0`（默认值，未覆盖） | `tb_cheshire_soc.sv` → `fixture_cheshire_soc.sv` |
| 预处理宏 | `+define+SELCFG=0`（传入但未被源码使用） | — |

`SELCFG` 宏与 `SelectedCfg` 参数未连接，因此本计划只对默认配置有效。

## 4. 检查器与 scoreboard

| 检查对象 | 机制 | 位置 | 现有 / 新增 |
| --- | --- | --- | --- |
| DMA 目标内容与尾部保护 | 软件逐字节比较，`errors` 作为返回码 | `dma_1d.spm.c`、`dma_2d.spm.c`、`dma_slink.spm.c` | 现有 |
| 自修改代码结果 | `outcome1 + outcome2 != 3` 作为返回码 | `spm_uncached.spm.c` | 现有 |
| 硬件特性存在 | `CHECK_ASSERT(-1, CHS_REGS->hw_features.f.dma)` 等 | 各 DMA 测试 | 现有 |
| UART 文本 | VIP 解码 DUT `uart_tx` 并打印 `[UART] ...`；奇偶错误 `$error` | `vip_cheshire_soc.sv` | 现有 |
| ELF 加载 | 打不开或读段失败 `$fatal`；打印 `[ELF] INFO: Entrypoint at ...`、`Preloading section at ...` | `vip_cheshire_soc.sv`、`elfloader.cpp` | 现有 |
| Serial Link 读写响应 | 错误响应 `$error("[SLINK] - Write/Read error response")` | `vip_cheshire_soc.sv` | 现有 |
| 返回码 | `[SLINK] SUCCESS` / `[SLINK] FAILED: return code N` | `vip_cheshire_soc.sv` | 现有 |
| Make 判定 | 日志含 `[PASS]` / `SUCCESS` / `exit code 0` → `PASS: <name>`，否则 `FAIL:` 并退出 1 | `Makefile.xcelium` `xrun-run` | 现有 |

已知弱点（`article.md` 第 20.10 节）：Make 判定只搜索成功关键字，不检查 `$error` / 断言失败；人工复核按第 8 节三层证据进行。

## 5. 接口断言（SVA）

本计划不新增断言（六项为已有测试）。建议的后续项（见 `sv-assertions-coverage`）：

| 接口 | 断言内容 | 放置位置 | 状态 |
| --- | --- | --- | --- |
| 外部 LLC / DRAM AXI 端口 `axi_llc_mst_req/rsp` | AW / AR / W 在背压期间 VALID 不撤销、载荷 `$stable`；B / R 响应为 OKAY | `target/sim/src/fixture_cheshire_soc.sv` | 待写 |
| Serial Link VIP 驱动 | 写 / 读响应为 OKAY（现有 `$error` 已覆盖） | `vip_cheshire_soc.sv` | 现有 |

## 6. 覆盖率要回答的问题

| 问题 | 覆盖点 / 分箱 | 收集方式 | 备注 |
| --- | --- | --- | --- |
| 六项是否都真正执行到 DMA / UART / Serial Link 的 RTL | 代码覆盖率（`-coverage all -covdut cheshire_soc`） | `make -f Makefile.xcelium xrun-cov BINARY=<elf>` × 6，`xrun-cov-report` | 覆盖率流程未作为基线验证，先用 `helloworld.spm.elf` 验证整条链 |
| 外部内存端口的 burst 长度 / 大小分布 | `aw.len`、`aw.size`、地址对齐 | 建议的 `cg_llc_aw`（`sv-assertions-coverage`） | 待写 |

不设覆盖率数字门槛。

## 7. 测试列表

测试名称与验证点与 [`article.md` 第 6.1 节](https://github.com/dv365lab/dv365-cheshire/blob/main/article.md#ch06) 完全一致：

| ID | 特性 | ELF | 主要验证点（6.1 原文） | TB 配置 | 参数 | 预期证据 | 日志 | 状态 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| T-01 | F-01 F-02 F-03 F-09 | `helloworld.spm.elf` | SPM 执行、频率测量、UART | `SelectedCfg=0` | `BOOTMODE=0 PRELMODE=1 SEED=1` | `Entrypoint at 0x10000000`、`[UART] Hello World!`、`[SLINK] SUCCESS`、`PASS: helloworld.spm` | `target/sim/xrun/work/logs/helloworld.spm.log` | 已有通过记录（2026-10-04，`docs/tg/xcelium_zh.md` 第 8.6 节） |
| T-02 | F-04 F-09 | `dma_1d.spm.elf` | 一维搬运、目标尾部保护和逐字节比较 | `SelectedCfg=0` | 同上 | `Entrypoint at 0x10000000`、`[SLINK] SUCCESS`、`PASS: dma_1d.spm`（无 UART 文本） | `.../logs/dma_1d.spm.log` | 已有通过记录（同上） |
| T-03 | F-05 F-09 | `dma_2d.spm.elf` | 二维地址生成、步长和重叠覆盖 | `SelectedCfg=0` | 同上 | 同 T-02，`PASS: dma_2d.spm` | `.../logs/dma_2d.spm.log` | 已有通过记录（同上） |
| T-04 | F-06 F-09 | `dma_slink.spm.elf` | CPU 远端写与 DMA 远端读回 | `SelectedCfg=0` | 同上 | 同 T-02，`PASS: dma_slink.spm` | `.../logs/dma_slink.spm.log` | 已有通过记录（同上） |
| T-05 | F-07 F-09 | `spm_uncached.spm.elf` | DMA 修改代码后从非缓存别名取指 | `SelectedCfg=0` | 同上 | 同 T-02，`PASS: spm_uncached.spm` | `.../logs/spm_uncached.spm.log` | 已有通过记录（同上） |
| T-06 | F-01 F-03 F-08 F-09 | `helloworld.dram.elf` | 从外部 AXI 内存模型执行 | `SelectedCfg=0` | 同上 | `Entrypoint at 0x80000000`、`[UART] Hello World!`、`[SLINK] SUCCESS`、`PASS: helloworld.dram` | `.../logs/helloworld.dram.log` | 已有通过记录（同上） |

构建（[`article.md` 第 6.2 节](https://github.com/dv365lab/dv365-cheshire/blob/main/article.md#ch06) 原文）：

```bash
make -j4 \
  "$PWD/sw/tests/helloworld.spm.elf" \
  "$PWD/sw/tests/dma_1d.spm.elf" \
  "$PWD/sw/tests/dma_2d.spm.elf" \
  "$PWD/sw/tests/dma_slink.spm.elf" \
  "$PWD/sw/tests/spm_uncached.spm.elf" \
  "$PWD/sw/tests/helloworld.dram.elf"
```

运行（`article.md` 第 6.3 节）：

```bash
chs_known_cases="sw/tests/helloworld.spm.elf \
sw/tests/dma_1d.spm.elf \
sw/tests/dma_2d.spm.elf \
sw/tests/dma_slink.spm.elf \
sw/tests/spm_uncached.spm.elf \
sw/tests/helloworld.dram.elf"

mkdir -p target/sim/xrun/work/logs
set -o pipefail
make -f Makefile.xcelium xrun-regress \
  BOOTMODE=0 PRELMODE=1 SEED=1 \
  REGRESS_ELFS="$chs_known_cases" \
  2>&1 | tee target/sim/xrun/work/logs/regression-known.log
```

前置：`make -j4 hw-all`、`make -f Makefile.xcelium xrun-all`。`REGRESS_ELFS` 必须显式给出：默认通配会混入 AXI-RT / CLIC 的 `.spm.elf`，且不含 `.dram.elf`（`article.md` 第 6.4 节）。

## 8. 通过判据与证据

每一项都要同时满足三层：

1. **加载**：`[ELF] INFO: Entrypoint at 0x10000000`（T-01…T-05）或 `0x80000000`（T-06）；`[SLINK] Preloading section at ...`、`[SLINK] Preload complete`、`Wrote launch signal and entry point`。
2. **行为**：T-01 / T-06 出现 `[UART] Hello World!`；T-02…T-05 没有 UART 文本，依靠软件比较（返回码）。
3. **结束**：`[SLINK] SUCCESS`、`Simulation complete via $finish(1)`（括号中的 1 不是退出码）、`PASS: <name>`；回归整体 `make` 退出码 0，汇总为六行 `PASS:`。

证据清单：

- `git rev-parse --short HEAD` 与工作树状态；`bender --version`、`riscv64-unknown-elf-gcc --version | head -1`、`xrun -version`。
- 完整命令（第 7 节）与 `REGRESS_ELFS`。
- `rg -n 'PASS:|FAIL:|FAILED|SUCCESS|Entrypoint' target/sim/xrun/work/logs/regression-known.log` 输出。
- 六个单项日志路径。

负向实验（`article.md` 第 6.6 节）：把任一测试临时改为 `return 7;`，重建该 ELF 并运行，预期 `[SLINK] FAILED: return code 7`、`FAIL: <name>`、`make` 退出码非零；改回后重新构建并确认 PASS。

超时：`TIMEOUT_NS` 未被 testbench 读取；用 `timeout 300s make -f Makefile.xcelium xrun-run BINARY=...` 作主机侧兜底（首次编译需放宽）。参考耗时（2026-10-04 实测，不含首次编译）：Hello World 两项约 20 秒，其余四项约 5 秒。

## 9. 风险与未覆盖项

| 项 | 为什么没覆盖 | 若要覆盖需要什么 |
| --- | --- | --- |
| AXI-RT / CLIC / vCLIC 配置与对应 ELF | `SELCFG` 宏未接到 `SelectedCfg` 参数；默认硬件未开启这些功能 | 在 `tb_cheshire_soc` 层真正设置模块参数并重新展开；按配置单独回归 |
| `PRELMODE=0/2/3`（JTAG / UART / MEMH） | 六项实测只用 Serial Link | 对每种加载方式至少跑 `helloworld.spm.elf` 并记录 |
| `BOOTMODE=2/3` 自主启动、`BOOTMODE=1` | 需要 Flash / EEPROM 镜像，未端到端验证；SD Card 在 testbench 中直接 `$fatal` | 准备镜像与 `IMAGE=`，另立 vPlan |
| 外部内存时序 | `axi_sim_mem` 是功能模型，不是 DDR 时序模型 | DRAMSys 接入（`USE_DRAMSYS` 与 `UseDramSys` 仍有 TODO） |
| Serial Link 远端 | 远端是 AXI 从设备模型，不是第二颗 Cheshire | 双实例 testbench |
| 断言失败不影响 Make 判定 | `xrun-run` 只搜索成功关键字 | 断言用 `$fatal` 或证据收集时检查 `*E,` / `ASRTST` 为空 |
| 覆盖率流程 | `xrun-cov` / `xrun-cov-report` 未作为基线验证 | 先用 Hello World 走通并记录 |
| 仿真时间 watchdog | `TIMEOUT_NS` 未实现 | 按 `article.md` 第 20.4 节加入并用不结束的测试验证 |
| 头文件依赖跟踪 | `sw/sw.mk` 未用 `gcc -MM` | 改头文件后删除相关 `.o` 重建 |

## 10. 参考

- [`article.md` 第 6 章](https://github.com/dv365lab/dv365-cheshire/blob/main/article.md#ch06)、[第 20 章](https://github.com/dv365lab/dv365-cheshire/blob/main/article.md#ch20)、[第 26 章](https://github.com/dv365lab/dv365-cheshire/blob/main/article.md#ch26)
- [`README.md`](https://github.com/dv365lab/dv365-cheshire/blob/main/README.md) 第 1、5–8 节
- [Xcelium 调试实录](../tg/xcelium_zh.md) 第 6–11 节
- [`Makefile.xcelium`](https://github.com/dv365lab/dv365-cheshire/blob/main/Makefile.xcelium)
- Skills：`cheshire-regress`（执行）、`cheshire-verify-change`（改动后重跑）、`sv-assertions-coverage`（断言与覆盖率）
