---
name: cheshire-vplan
description: 为 dv365-cheshire（PULP Cheshire RISC-V SoC）的某个特性或数据通路编写硬件验证计划（vPlan），按「特性清单 → 激励策略 → 检查器 → 接口断言 → 覆盖率问题 → 测试列表（映射到 sw/tests/*.elf 与 Makefile.xcelium 参数）→ 通过判据与证据 → 风险与未覆盖项」的流程输出到 docs/vplan/<feature>.md。当用户要「写验证计划」「vPlan」「测试计划」「怎么验证 DMA / UART / Serial Link / CLIC / 新外设 / 某次 RTL 修改」「覆盖率要测什么」「要加哪些断言」时使用。只写计划与判据，不宣称任何仿真结果；运行回归请用 cheshire-regress。
---

# 为 Cheshire 编写硬件验证计划（vPlan）

## 1. 本仓库语境下的 vPlan 是什么

- 被测对象是 RTL（`hw/` 与 Bender 依赖），验证环境是 `target/sim/src/` 的三层结构：`tb_cheshire_soc`（顶层，读 plusarg、选择加载方式、等待结束）→ `fixture_cheshire_soc`（按 `SelectedCfg` 实例化 DUT `cheshire_soc` 与 VIP）→ `vip_cheshire_soc`（时钟 / 复位、JTAG / Serial Link / UART 驱动、ELF 加载、外部 AXI 内存、Flash / EEPROM 模型、结束码检查）。没有 UVM；激励主要来自运行在 CVA6 上的裸机程序（`sw/tests/*.c|*.S` → `*.spm.elf` / `*.dram.elf` / `*.rom.elf`），由 `make -f Makefile.xcelium xrun-run BINARY=...` 加载执行。
- 一份 vPlan 回答六个问题：验证**什么**（特性与来源）、用**什么激励**、**谁来判断对错**（检查器 / 断言 / 自检）、**覆盖率回答什么**、**哪些测试**以及**什么证据算通过**，最后写清**没有覆盖什么**。
- vPlan 是计划与判据，不是结果记录。任何「PASS」都必须来自有 Xcelium 许可证机器上的日志；在 CI 或云端 Copilot coding agent 中只能写「待在许可证机器上执行」。

## 2. 写作流程

按顺序完成，每一步都要引用仓库文件（`path:line` 或章节），不要凭印象。

### 2.1 界定特性与来源

| 想知道 | 去哪里看 |
| --- | --- |
| 默认硬件配置含哪些模块、参数 | `hw/cheshire_pkg.sv`（`DefaultCfg`、`cheshire_cfg_t`）、`docs/um/arch.md` |
| 地址地图、寄存器 | `hw/cheshire.rdl`、`hw/regs/cheshire_soc_regs.rdl`、生成结果 `hw/cheshire_addrmap_pkg.sv`、`sw/include/regs/cheshire.h`、`docs/um/arch.md` Memory Map |
| 模块连接、外部端口 | `hw/cheshire_soc.sv`、`target/sim/src/fixture_cheshire_soc.sv` |
| 依赖 IP 的 RTL | `bender path <ip>`，依赖名见 `Bender.yml`（cva6、axi、axi_llc、idma、serial_link、clint、clic、opentitan_peripherals、axi_rt …） |
| 软件如何驱动 | `sw/include/dif/*.h`、`sw/lib/*.c`、`sw/lib/crt0.S`（返回码写入 `scratch[2]`） |
| testbench 配置索引 | `target/sim/src/tb_cheshire_pkg.sv`：0 默认、1 AXI-RT、2 CLIC、3 vCLIC |
| 已知边界 | `README.md` 第 7 节、`docs/tg/xcelium_zh.md` 第 10.3 节、`article.md` 第 20.4 节 |

写出「特性清单」表：ID（`F-01`…）、特性、来源引用、所属数据通路（取指 / 数据 / DMA / 远端 / 外设 / 中断 / 启动）。

### 2.2 激励策略

- **定向测试**：针对已知重要场景（例如长度 8、跨 4 KiB 页前 8 字节、只写一个字节、目标步长小于每轮字节数的重叠），每个场景写明初始状态、触发操作、独立预期结果、完成条件、失败条件（`article.md` 第 20.5 节）。
- **随机测试**：必须能保存种子与复现条件。按顺序逐步增加随机因素：长度 → 地址低位 → 源 / 目标区域 → 背压与延迟 → 并发（`article.md` 第 20.6 节）。每个随机用例仍要有参考模型。
- **种子**：`SEED` 只传给 `xrun -svseed`，影响 SV 侧随机（例如 VIP 的随机延迟）；裸机 C 程序本身是确定性的，软件侧随机要自带 LCG 并把种子打印到 UART 或写进返回码约定。
- **参数传递**：预处理宏（`+define+SELCFG=`，编译期）、模块参数（`SelectedCfg`、`UseDramSys`，展开期）、plusarg（`+BINARY= +IMAGE= +BOOTMODE= +PRELMODE=`，运行期）是三种不同机制，名字相似不会自动连通（`article.md` 第 20.3 节）。当前 `SELCFG` 宏**没有**接到 `SelectedCfg` 参数，需要非默认配置的计划必须先说明如何真正切换参数并重新展开。

### 2.3 检查器与 scoreboard

列出每个特性由谁判断对错：

| 层 | 现有机制 | 位置 |
| --- | --- | --- |
| 软件自检 | 逐字节比较、保护区未被覆盖、计数一致，不一致字节数作为 `main()` 返回值 | `sw/tests/dma_1d.spm.c` 等 |
| 返回码协议 | CRT0 把 `(返回值 << 1) | 1` 写入 `scratch[2]`，VIP 轮询 bit 0 并右移 | `sw/lib/crt0.S`、`vip_cheshire_soc.sv` 的 `*_wait_for_eoc` |
| VIP 检查 | ELF 加载失败 `$fatal`；UART 奇偶错误 `$error`；Serial Link 读写错误响应 `$error`；JTAG 异常 `$fatal`；返回码非零 `$error("[...] FAILED: return code %0d")` | `target/sim/src/vip_cheshire_soc.sv` |
| Makefile 判定 | 日志含 `[PASS]` / `SUCCESS` / `exit code 0` 之一 → `PASS: <name>`，否则 `FAIL:` 且退出码非零 | `Makefile.xcelium` 的 `xrun-run` |

新特性若现有机制覆盖不到（例如总线错误响应必须出现、某寄存器复位值），要写明新增检查器放在哪里（软件自检优先；VIP task；或 SVA）。仅打印目标缓冲区让人肉观察、或仅确认程序跑到最后，都不算检查（`article.md` 第 20.5 节）。

### 2.4 接口断言（SVA）

对每条涉及的接口列出要断言的局部时序契约（VALID 在未握手期间不得撤销、载荷稳定、ID 对应、`LAST` 位置、错误响应），示例与放置位置见 `sv-assertions-coverage` skill。断言描述局部契约，数据最终正确仍需参考模型或软件检查（`article.md` 第 20.7 节）。

### 2.5 覆盖率应该回答什么

- 先写「问题」再写 covergroup：长度区间、地址对齐、源 / 目标区域组合、错误响应类型、启动模式、加载方式等（`article.md` 第 20.8 节）。
- 代码覆盖率入口是 `make -f Makefile.xcelium xrun-cov BINARY=<elf>` 与 `xrun-cov-report`（IMC 合并到 `target/sim/xrun/work/cov_summary.txt`），**流程尚未作为基线验证**；计划里要把「验证覆盖率流程本身可用」列为前置任务，并注意 `XRUN_RUN_FLAGS` 默认带 `-R`。
- 覆盖率高不等于检查有效；在计划中把覆盖率定位为「哪些场景被执行过」的证据，不设数字门槛。

### 2.6 测试列表

每行一个测试，列齐：ID（`T-01`…）、覆盖的特性 ID、ELF（`sw/tests/<name>.<spm|dram|rom>.elf`）、TB 配置（`SelectedCfg` 实际值）、运行参数（`BOOTMODE` / `PRELMODE` / `SEED` / 其他 plusarg）、预期证据（日志关键字、UART 文本、返回码）、日志路径（`target/sim/xrun/work/logs/<name>.log`）、状态（已有 / 待写 / 待验证）。

- 六项基础回归的 ELF 名称与验证点以 `article.md` 第 6.1 / 6.2 节为准，不要改写。
- 新测试文件名决定链接方式：`foo.spm.c` 只链接 SPM；无后缀的 `foo.c` 为所有链接模式各生成一个 ELF（`sw/sw.mk` 的 `chs_sw_ld_elf_rule`）。
- `.rom.elf` 的加载地址与运行地址不同，不能直接用于 `PRELMODE=1` 预加载。
- 回归命令写成显式列表：`make -f Makefile.xcelium xrun-regress BOOTMODE=0 PRELMODE=1 SEED=1 REGRESS_ELFS="..."`。

### 2.7 通过判据与证据

三层缺一不可（`article.md` 第 5.7 节、`docs/tg/xcelium_zh.md` 第 6.6 节）：

1. 加载正确：`[ELF] INFO: Entrypoint at 0x10000000`（SPM）或 `0x80000000`（DRAM），`Preloading section at ...`。
2. 行为正确：UART 文本（`[UART] Hello World!`）或软件自检通过（没有文本的 DMA 测试属正常）。
3. 结束正确：`[SLINK] SUCCESS`（或 `[JTAG]` / `[UART]` 前缀）、`Simulation complete via $finish(1)`（数字不是退出码）、Makefile 打印 `PASS: <name>`、`make` 退出码 0。

证据清单（`article.md` 第 26.9 节）：提交号、工具版本、硬件配置、ELF 与命令、种子、日志路径、`rg -n 'PASS:|FAIL:|FAILED|SUCCESS|Entrypoint' <log>` 的输出。负向实验：至少一个测试临时 `return 7;`，证明回归能报 FAIL（`article.md` 第 6.6 节）。超时：`TIMEOUT_NS` 未被 testbench 读取，用 `timeout 300s make ...` 兜底，或按 `article.md` 第 20.4 节加入 watchdog 并用一个刻意不结束的测试验证它。

### 2.8 风险与未覆盖项

显式列出：未切换的配置（AXI-RT / CLIC / vCLIC）、未验证的加载方式（`PRELMODE=0/2/3`）、未验证的启动模式（`BOOTMODE=2/3`）、外部内存只是 `axi_sim_mem` 功能模型（不是 DDR 时序）、Serial Link 远端只是 AXI 从设备模型（不是第二颗 Cheshire）、覆盖率流程未验证、依赖 Bender 锁定修订等。每条给出「如果要覆盖需要什么」。

## 3. 输出

- 路径：`docs/vplan/<feature>.md`（kebab-case，例如 `baseline-regression.md`、`dma-1d-boundaries.md`）。模板：`.github/skills/cheshire-vplan/templates/vplan-template.md`，复制后逐节填写，不留占位符。
- 范例：`docs/vplan/baseline-regression.md`（六项基础回归）。
- 若希望出现在文档站点，在 `mkdocs.yml` 的 `Verification Plans` 导航下加一行；链接仓库源码时用 `https://github.com/dv365lab/dv365-cheshire/blob/main/<path>` 绝对地址（`docs/` 之外的相对链接会让 MkDocs 报警）。
- Markdown 不加许可证头；正文中文，标识符 / 命令 / 路径英文；UTF-8 无 BOM、LF。

## 4. 完成前自检

- [ ] 每个特性都有来源引用；每个测试都映射到真实存在的 ELF 名称（`sw/tests/` 中有对应源文件）或标注「待编写」。
- [ ] 所有 `make` 目标、变量名、日志关键字都能在 `Makefile.xcelium` / `vip_cheshire_soc.sv` 中 grep 到。
- [ ] 「通过判据」包含三层证据与负向实验；「风险」包含 `SELCFG`、`TIMEOUT_NS`、模型边界。
- [ ] 没有写任何未经日志支撑的「已通过」；状态列区分「已有通过记录（引用来源）」与「待验证」。
- [ ] 执行环境说明：哪些可在 CI / 云端完成（构建、lint），哪些必须在许可证机器完成（仿真、覆盖率）。

## 相关 skills

- `cheshire-regress`：执行测试列表、读日志。
- `cheshire-verify-change`：修改后应重跑哪些测试。
- `sv-assertions-coverage`：断言与 covergroup 的写法与放置。
- `test-gap-audit`：先找缺口再写计划。
- `breakdown-test`：仅作章节骨架参考。
