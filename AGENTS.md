# dv365-cheshire：面向 AI 代理与贡献者的工作说明

本文件是本仓库给 GitHub Copilot（coding agent、CLI、Chat）以及其他 AI 代理的统一说明。
`.github/copilot-instructions.md` 是它的精简版；两者内容应保持一致，冲突时以本文件为准。
正文使用中文，标识符、命令、路径、工具名保持英文原样。

## 1. 这个仓库是什么

- **PULP Cheshire**：围绕 [CVA6](https://github.com/openhwgroup/cva6) 的 64 位 RISC-V SoC，含 AXI 互连、LLC/SPM、iDMA、UART、Serial Link、JTAG 调试模块、CLINT/PLIC/CLIC、VGA、USB 等。源码形态：SystemVerilog RTL + 裸机 C/汇编 + Make/Bender/Python 生成工具 + Tcl 仿真脚本。
- **本 fork（DV365 Lab）在上游基础上增加**：Cadence Xcelium 仿真流程（`Makefile.xcelium`）、中文复现文档（`README.md`、`docs/tg/xcelium_zh.md`）、中文教程（`article.md`，29 章）。
- **语境约定**：仓库里说的「验证计划」指硬件 DV 的 vPlan（verification plan），不是软件 QA 测试计划；「搭建环境」指 RTL 仿真环境（Bender + RISC-V GCC + Python 生成工具 + Xcelium）。
- **已验证基线**：六项基础回归在默认 SoC 配置、`BOOTMODE=0 PRELMODE=1 SEED=1` 下于 Xcelium 全部 PASS（`README.md` 第 6 节、`article.md` 第 6 章、`docs/tg/xcelium_zh.md` 第 8 节）。AXI-RT / CLIC / vCLIC 专用测试**没有**通过记录，原因见第 4.4 节。

## 2. 仓库地图

| 路径 | 内容 | 备注 |
| --- | --- | --- |
| `hw/` | SoC RTL：`cheshire_soc.sv`、`cheshire_pkg.sv`（`DefaultCfg`、地址规则）、`cheshire.rdl`（地址地图 SystemRDL）、`regs/`（SoC 寄存器描述与生成结果）、`bootrom/`、`include/cheshire/` | 受 Verible lint；`hw/regs/*` 与 `cheshire_addrmap_pkg.sv` 是生成文件 |
| `sw/` | `sw.mk`（软件构建规则）、`include/`、`lib/`（CRT0、驱动）、`link/`（`spm.ld`、`dram.ld`、`rom.ld`）、`tests/`（裸机测试）、`boot/`、`deps/`（`printf`、`cva6-sdk` 子模块） | `sw/include/regs/*.h` 是生成文件 |
| `target/sim/src/` | `tb_cheshire_soc.sv`（顶层）、`fixture_cheshire_soc.sv`、`vip_cheshire_soc.sv`、`tb_cheshire_pkg.sv`、`elfloader.cpp`（DPI-C）、`run.xcelium.tcl` | 三层 testbench 结构见 `article.md` 第 20.1 节 |
| `target/sim/` | `models.mk`（下载 Flash/EEPROM 模型）、`vsim/`、`vcs/` | QuestaSim/VCS 入口未计入实测 |
| `target/xilinx/` | FPGA 顶层、约束、构建脚本 | 本说明不涉及 |
| `util/` | Boot ROM 生成、OpenOCD 等工具 | |
| `docs/` | MkDocs 站点：`gs.md`、`tg/`（含 `xcelium_zh.md`）、`um/`、`vplan/`（验证计划） | 导航在 `mkdocs.yml` |
| `article.md` | 中文教程；章节锚点形如 `#ch06` | 第 4 / 6 / 20 / 26 章是环境、回归、验证方法、工程化的主要依据 |
| `Makefile` / `cheshire.mk` | 根构建入口；`cheshire.mk` 可被外部工程 include，目标带 `chs-` 前缀，根 `Makefile` 提供去前缀转发（`make help` 列出） | |
| `Makefile.xcelium` | Xcelium 专用流程（`xrun-*` 目标） | 头部注释给出用法 |
| `Bender.yml` / `Bender.lock` | 硬件依赖与源文件组 / 锁定修订 | 不要随手 `bender update` |
| `pyproject.toml` / `uv.lock` | Python 生成工具依赖（PeakRDL、hjson、mako、tclint、mkdocs 等） | CI 用 `uv run --locked` |
| `.github/` | `workflows/`（`build.yml`、`lint.yml`、`publish-docs.yml`、`docker-image.yml`、`copilot-setup-steps.yml`）、`Dockerfile`、`verible.waiver`、`skills/` | |
| `vdebug_probe.tcl` / `command.txt` | Verisium 波形探测脚本 / 已验证的 Hello World 命令 | |

本地目录 `.bender/`、`.venv/`、`target/sim/models/`、`target/sim/xrun/` 均被 `.gitignore` 忽略；仓库里没有某个生成文件不等于源码缺失，先确认它应从哪里生成（`article.md` 第 2.1 节）。

## 3. 工具与版本

存在两组已知可用组合；写文档或脚本时要说明依据哪一组，不要混写。

| 工具 | CI 组合（`.github/workflows/build.yml`、`.github/Dockerfile`） | README 实测组合（2026-10-04，Rocky Linux 8.10） | 用途 |
| --- | --- | --- | --- |
| Bender | 0.31.0（`pulp-platform/pulp-actions/bender-install@v2.4.4`） | 0.32.1 | 检出硬件 IP，生成源文件列表 |
| Python | 3.11（`astral-sh/setup-uv@v6`，`uv run --locked`） | 3.11.16 | PeakRDL、regtool、模板工具 |
| RISC-V GCC | `riscv-gcc-install@v2.4.4`：nightly `2023.03.14`，distro `ubuntu-22.04`，target `riscv64-elf`（前缀 `riscv64-unknown-elf-`）；Dockerfile 用 SiFive 8.3.0-2020.04.0 | xPack 15.2.0-1（前缀 `riscv-none-elf-`，需建立 `riscv64-unknown-elf-*` 别名） | 交叉编译裸机程序，`-march=rv64gc_zifencei -mabi=lp64d`，LTO |
| 主机 G++ | 运行器自带 | 8.5.0 | 编译 `elfloader.cpp`（DPI-C） |
| slang | v2.0（仅 Dockerfile） | — | 可选的 SV 语法检查 |
| Cadence Xcelium + IMC | **不可用** | `26.03-a071` | RTL 编译、展开、仿真、覆盖率 |
| `dtc` / `sgdisk` | 完整 `sw-all` 需要 | 按需 | 设备树 / GPT 镜像 |

Xcelium 是专有工具，只存在于有许可证的机器上。GitHub Actions 与云端 Copilot coding agent **只能做 build 与 lint，不能仿真**。

## 4. 命令速查

所有构建与仿真命令都在仓库根目录执行（Linux）。

### 4.1 一次性准备

```bash
git submodule update --init --recursive sw/deps/printf   # 基础回归只需要 printf；cva6-sdk 仅 Linux 镜像需要
uv python install 3.11 && uv sync --locked --python 3.11 && source .venv/bin/activate
bender checkout                                           # 复现用 checkout，不要用 update
make -j4 hw-all                                           # 生成寄存器 RTL、地址包、iDMA 等；不重建 Boot ROM
```

无本地 venv 时，CI 的等价写法是 `uv run --locked make <target>`。

### 4.2 构建软件

```bash
# 六项基础回归所需 ELF（显式列表，使用 "$PWD/..." 绝对路径）
make -j4 \
  "$PWD/sw/tests/helloworld.spm.elf" \
  "$PWD/sw/tests/dma_1d.spm.elf" \
  "$PWD/sw/tests/dma_2d.spm.elf" \
  "$PWD/sw/tests/dma_slink.spm.elf" \
  "$PWD/sw/tests/spm_uncached.spm.elf" \
  "$PWD/sw/tests/helloworld.dram.elf"

make -j4 sw-all        # 全部软件与镜像；需要 sgdisk / dtc
make bootrom-all       # 单独重建 Boot ROM；受编译器版本影响，首次复现不要跑
make sim-all           # QuestaSim / VCS 脚本与模型；Xcelium 不依赖它
```

### 4.3 Xcelium 仿真（需要许可证）

```bash
make -f Makefile.xcelium xrun-help                      # 列出目标与变量
make -f Makefile.xcelium xrun-flist                     # 下载模型 + 生成 target/sim/xrun/cheshire_soc.f
make -f Makefile.xcelium xrun-all                       # xrun-flist + xrun-compile（编译、展开成快照）
make -f Makefile.xcelium xrun-run BINARY=sw/tests/helloworld.spm.elf BOOTMODE=0 PRELMODE=1 SEED=1
make -f Makefile.xcelium xrun-regress BOOTMODE=0 PRELMODE=1 SEED=1 REGRESS_ELFS="<显式 ELF 列表>"
make -f Makefile.xcelium xrun-cov BINARY=<elf>          # 覆盖率运行（流程未作为基线验证）
make -f Makefile.xcelium xrun-cov-report                # imc 合并 → target/sim/xrun/work/cov_summary.txt
make -f Makefile.xcelium xrun-run BINARY=<elf> XRUN_RUN_INPUT=vdebug_probe.tcl   # Verisium 波形数据库
make -f Makefile.xcelium xrun-clean                     # 删除工作库、文件列表与日志
```

- `xrun-run` 成功判据：日志中出现 `[PASS]` / `SUCCESS` / `exit code 0` 之一则打印 `PASS: <测试名>`，否则 `FAIL:` 并返回非零。
- `xrun-regress` 在某项失败后继续运行其余项，最后返回非零；它**不编译 ELF**。
- 默认 `REGRESS_ELFS` 是已存在的全部 `sw/tests/*.spm.elf`，会混入 AXI-RT/CLIC 专用 ELF，且不含 `.dram.elf`，所以**必须显式指定列表**。
- 需要主机侧超时时用 `timeout 300s make -f Makefile.xcelium xrun-run ...`。

### 4.4 运行期参数（`Makefile.xcelium`）

| 变量 | 默认 | 含义与边界 |
| --- | --- | --- |
| `BINARY` / `IMAGE` | 空 | 预加载 ELF / 启动镜像，经 plusarg `+BINARY=` `+IMAGE=` 传入 `tb_cheshire_soc` |
| `BOOTMODE` | 0 | 0 = 等待外部预加载；1 = SD Card（testbench 直接 `$fatal`）；2/3 = 自主启动，未端到端验证 |
| `PRELMODE` | 1 | 0 = JTAG，1 = Serial Link（六项实测使用），2 = UART，3 = MEMH |
| `SEED` | 1 | 传给 `-svseed`，只影响 SV 随机化 |
| `SELCFG` | 0 | 只传 `+define+SELCFG=`，顶层实际使用模块参数 `SelectedCfg`，两者**未连接**；设 1/2/3 不会切换到 AXI-RT/CLIC/vCLIC 配置 |
| `USE_DRAMSYS` | 0 | SystemC/库路径仍有 TODO，`UseDramSys` 参数需另行接入 |
| `TIMEOUT_NS` | 空 | 生成 `+TIMEOUT_NS=`，但 testbench **没有读取它**，不是有效 watchdog |
| `XRUN_WORK` | `target/sim/xrun/work` | 并行运行时每个进程用独立目录（`article.md` 第 26.7 节） |
| `XRUN_RUN_INPUT` | `target/sim/src/run.xcelium.tcl` | 运行脚本；可换成 `vdebug_probe.tcl` |
| `REGRESS_ELFS` | `sw/tests/*.spm.elf` | 回归列表 |

`xrun-gui` 引用的 `target/sim/xrun/waves.tcl` 不存在，不能当作已验证的 GUI 流程。

### 4.5 输出目录

| 产物 | 路径 |
| --- | --- |
| 源文件列表 | `target/sim/xrun/cheshire_soc.f` |
| 工作库 / 快照 | `target/sim/xrun/work/xcelium.d/` |
| 编译日志 | `target/sim/xrun/work/logs/compile.log` |
| 单项日志 | `target/sim/xrun/work/logs/<ELF 去掉 .elf>.log`，如 `dma_1d.spm.log`；覆盖率为 `<名>.cov.log` |
| 覆盖率数据库 / 汇总 | `target/sim/xrun/work/cov_work/`、`target/sim/xrun/work/cov_summary.txt` |
| 外设模型 | `target/sim/models/s25fs512s.v`、`target/sim/models/24FC1025.v` |

## 5. 编码与提交规范

1. **许可证头**（`.github/workflows/lint.yml` 的 `lint-license`，lowRISC 检查器）。检查范围是 git 跟踪的 `.sv .svh .v .tcl .mk Makefile .c .h .cpp .S .ld .py .sh .yml .yaml .toml .hjson .cfg Dockerfile` 等；**Markdown 不检查**（`README.md`、`docs/*.md`、`article.md`、`SKILL.md` 均无头）。`sw/include/regs/*.h` 与 `.github/skills/test-gap-audit/scripts/coverage_map.py`（第三方 MIT 文件）被排除。新文件统一使用三行头，首行可以是 shebang：

   ```text
   # Copyright 2026 DV365 Lab.
   # Licensed under the Apache License, Version 2.0, see LICENSE for details.
   # SPDX-License-Identifier: Apache-2.0
   ```

   RTL / testbench 等硬件文件用 `//` 注释，可改用 `Solderpad Hardware License, Version 0.51, see LICENSE for details.` + `SPDX-License-Identifier: SHL-0.51`。匹配正则见 `lint.yml`。
2. **SystemVerilog**：Verible lint 作用于 `hw/`，排除 `hw/future/UsbOhciAxi4.v`，豁免见 `.github/verible.waiver`（生成的 `hw/regs/*`、`hw/cheshire_addrmap_pkg.sv` 与 `hw/cheshire_pkg.sv` 的行长）。
3. **C/C++**：clang-format **14**，扩展名 `c,h,cpp`，排除 `./sw/include/regs/*.h` 与 `./target/sim/src/elfloader.cpp`；配置在 `.clang-format`。
4. **Tcl**：`uv run --locked tclint . --style-spaces-in-braces --style-line-length 100`（`tclint==0.4.2`）。
5. **生成文件**：`hw/regs/cheshire_soc_regs*.sv`、`hw/cheshire_addrmap_pkg.sv`、`sw/include/regs/*.h`、`sw/link/cheshire_addrs.ldh` 由 `hw/cheshire.rdl`、`hw/regs/cheshire_soc_regs.rdl` 等生成，改描述源再 `make hw-all` / 对应软件目标；CI 会在构建后检查 `git status --porcelain --ignore-submodules` 为空。
6. **不要提交**构建产物（`*.elf *.o *.a *.dump *.memh`、`target/sim/xrun/`、`.bender/`、`.venv/`，见 `.gitignore`）。
7. **依赖**：复现用 `bender checkout`；`bender update` 属于依赖升级，要单独分支、单独说明（`article.md` 第 26.8 节）。保留 `Bender.lock` 与 `uv.lock`。
8. **文档语言**：中文正文；标识符、命令、路径、工具名、日志关键字保持英文。新文件使用 UTF-8（无 BOM）、LF 换行。
9. **提交信息**：英文祈使句，说明改了什么、为什么、如何验证。

## 6. 验证与证据要求

- 「完成」的定义见 `.github/skills/cheshire-verify-change/SKILL.md`：改了什么就重建什么 → lint → 至少运行一条相关 ELF 的仿真 → 附证据（命令、提交号、工具版本、日志路径、`PASS:` 行、退出码）。
- 判定一次仿真通过要同时看三层：ELF 入口与加载地址正确（`[ELF] INFO: Entrypoint at ...`）、程序出现预期行为（UART 文本或数据比较）、返回码为 0（`[SLINK] SUCCESS` 等）且 Make 退出码为 0。`Simulation complete via $finish(1)` 里的数字不是 shell 退出码。
- 没有 UART 输出的 DMA 测试依靠数据比较与返回码判定，不能因为没有文本就判失败。
- **涉及仿真结果的任何结论，必须注明是在有 Xcelium 许可证的机器上、用哪条命令、哪个提交得到的。** 在 CI 或云端 coding agent 里只能写「已完成 build / lint，未仿真」。
- 新增测试要做一次负向实验（例如临时 `return 7;`）证明回归能识别失败（`article.md` 第 6.6 节）。
- 性能或覆盖率数字要注明计时范围、模型（`axi_sim_mem` 不是 DDR 时序模型）和工具版本。

## 7. 云端 Copilot coding agent / GitHub Actions 的能力边界

- `.github/workflows/copilot-setup-steps.yml` 预装：子模块、uv + Python 3.11、RISC-V GCC（CI 组合）、Bender 0.31.0，并运行 `uv run --locked make hw-all sw-all`。
- 云端可以：读代码、改代码、`make hw-all` / `sw-all` / 单个 ELF、运行四类 lint、检查 `git status` 干净、生成文档。
- 云端不能：安装或运行 Xcelium / IMC / QuestaSim / VCS / Vivado，不能宣称任何仿真或覆盖率结果。遇到需要仿真的验收项，明确写出「需在有许可证的机器上执行以下命令」并给出命令与预期证据。
- 不要尝试用 pip / apt 安装 EDA 工具，不要创建空的模型文件（`s25fs512s.v`、`24FC1025.v`）来绕过缺失。

## 8. 可用 skills 与触发场景

| skill（`.github/skills/<name>/SKILL.md`） | 何时使用 |
| --- | --- |
| `cheshire-env-setup` | 从零搭建或恢复仿真环境、核对工具版本、新终端恢复步骤、`scripts/env_doctor.sh` 只读体检、排查「找不到 bender / gcc / xrun / peakrdl」 |
| `cheshire-vplan` | 为某个特性或数据通路编写硬件验证计划（vPlan），输出到 `docs/vplan/<feature>.md`；含空白模板 `templates/vplan-template.md`，范例 `docs/vplan/baseline-regression.md` |
| `cheshire-regress` | 构建并运行六项基础回归或单个用例，解释日志、判定与证据，SEED / 超时 / 并行工作目录 / 覆盖率 / 波形 |
| `cheshire-verify-change` | 修改 RTL / 软件 / 链接脚本 / 生成描述 / 构建脚本之后，决定重建什么、跑哪些 lint 与仿真，以及无 Xcelium 时的降级声明 |
| `sv-assertions-coverage` | 为接口添加 SVA 断言与功能覆盖率，在本仓库的放置位置与编译方式 |
| `test-gap-audit`（第三方，MIT） | 只读审计缺失、薄弱、过时的测试覆盖；在本仓库中「测试」= `sw/tests/*.elf` + testbench 检查 |
| `breakdown-test`（第三方，MIT） | 需要 ISTQB / ISO 25010 风格的测试策略章节骨架时作参考 |
| `create-implementation-plan`（第三方，MIT） | 为较大的改动先写可执行的实施计划 |

第三方 skill 的来源与许可证见 `.github/skills/THIRD_PARTY_LICENSES.md`。

## 9. 不要做的事

- 不要把「软件能编译」写成「RTL 仿真已通过」；不要把默认配置回归的 PASS 外推到 AXI-RT / CLIC / vCLIC。
- 不要依赖 `TIMEOUT_NS` 作为超时；不要把 `xrun-gui`、`xrun-cov` 写成已验证流程。
- 不要修改生成文件而不改描述源；不要手改 `hw/regs/*.sv`、`sw/include/regs/*.h`。
- 不要用 `bender update` 修复缺文件；不要删除模型实例或创建空模型文件。
- 不要在 Markdown 文件上加许可证头（会破坏 `SKILL.md` 的 YAML frontmatter，也非仓库约定）。
- 不要改动既有工作流的触发条件与检查强度。
