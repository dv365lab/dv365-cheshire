---
name: cheshire-regress
description: 在有 Cadence Xcelium 许可证的 Linux 机器上构建并运行 dv365-cheshire 的回归：六项基础回归（helloworld.spm / dma_1d.spm / dma_2d.spm / dma_slink.spm / spm_uncached.spm / helloworld.dram）、单个用例、覆盖率与波形；解释 Makefile.xcelium 的目标与变量、日志 / 波形 / 覆盖率目录、PASS / FAIL 判定与证据要求、SEED 与超时、并行时的工作目录隔离。当用户要「跑回归」「跑 helloworld」「xrun-regress」「看日志」「为什么 FAIL」「怎么并行跑」「怎么看覆盖率 / 波形」时使用。在没有 xrun 的环境（CI、云端 Copilot coding agent、Windows）只能给出命令与预期证据，不能执行也不能宣称结果。
---

# 运行 Cheshire 的 Xcelium 回归

依据：`Makefile.xcelium`、`article.md` 第 6 章（`#ch06`）与第 26 章（`#ch26`）、`README.md` 第 5–8 节、`docs/tg/xcelium_zh.md` 第 8–11 节。所有命令在仓库根目录执行；环境未就绪先用 `cheshire-env-setup`。

## 1. 回归分层（`article.md` 第 26.5 节）

| 层 | 内容 | 何时跑 |
| --- | --- | --- |
| 快速层 | `helloworld.spm.elf` + 一个小 DMA（`dma_1d.spm.elf`） | 开发中每次改动后 |
| 基础层 | 下面六项明确配置的已有测试 | 提交前、RTL / 构建系统改动后 |
| 专项层 | 新外设、中断、AXI-RT、多核、Linux 等对应配置 | 按特性 vPlan |

专项通过不能替代基础层，基础层也不能替代专项层。

## 2. 六项基础回归（`article.md` 第 6.1 节）

| 测试 | 主要验证点 |
| --- | --- |
| `helloworld.spm.elf` | SPM 执行、频率测量、UART |
| `dma_1d.spm.elf` | 一维搬运、目标尾部保护和逐字节比较 |
| `dma_2d.spm.elf` | 二维地址生成、步长和重叠覆盖 |
| `dma_slink.spm.elf` | CPU 远端写与 DMA 远端读回 |
| `spm_uncached.spm.elf` | DMA 修改代码后从非缓存别名取指 |
| `helloworld.dram.elf` | 从外部 AXI 内存模型执行 |

全部使用默认 SoC 配置（`SelectedCfg=0`）、`BOOTMODE=0 PRELMODE=1 SEED=1`。已有通过记录：2026-10-04，Xcelium `26.03-a071`（`README.md` 第 1、6 节；`docs/tg/xcelium_zh.md` 第 8.6 节）。

## 3. 标准流程

### 3.1 恢复环境

```bash
cd /path/to/dv365-cheshire
export PATH="$HOME/.local/bin:$HOME/.local/opt/cheshire/riscv-bin:$PATH"
source .venv/bin/activate
# 加载 Xcelium 环境 / 许可证
bash .github/skills/cheshire-env-setup/scripts/env_doctor.sh
```

### 3.2 生成硬件

```bash
bender checkout
git submodule update --init --recursive sw/deps/printf
make -j4 hw-all
```

### 3.3 构建全部指定 ELF（`article.md` 第 6.2 节）

```bash
make -j4 \
  "$PWD/sw/tests/helloworld.spm.elf" \
  "$PWD/sw/tests/dma_1d.spm.elf" \
  "$PWD/sw/tests/dma_2d.spm.elf" \
  "$PWD/sw/tests/dma_slink.spm.elf" \
  "$PWD/sw/tests/spm_uncached.spm.elf" \
  "$PWD/sw/tests/helloworld.dram.elf"
```

`xrun-regress` **不编译 ELF**，这一步不能省。`make sw-all` 会额外构建 AXI-RT / CLIC 专用 ELF 与镜像（需要 `sgdisk` / `dtc`）。

### 3.4 编译与展开 RTL

```bash
make -f Makefile.xcelium xrun-flist    # 下载 target/sim/models/{s25fs512s.v,24FC1025.v}，生成 target/sim/xrun/cheshire_soc.f
make -f Makefile.xcelium xrun-all      # xrun -elaborate → target/sim/xrun/work/xcelium.d，日志 logs/compile.log
```

Bender 目标：`-t sim -t rtl -t cva6 -t cv64a6_imafdchsclic_sv39 -t simulation`（`CHS_SIM_TARGETS`）。不要为了「拿到更多 RTL」加 `-t test`，那会引入依赖的自测 testbench。

### 3.5 顺序运行并保存汇总（`article.md` 第 6.3 节）

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

预期汇总（六行，顺序一致，`make` 退出码 0）：

```text
PASS: helloworld.spm
PASS: dma_1d.spm
PASS: dma_2d.spm
PASS: dma_slink.spm
PASS: spm_uncached.spm
PASS: helloworld.dram
```

- `set -o pipefail` 让 `tee` 不吞掉上游失败。
- `xrun-regress` 对每个 ELF 调用一次 `xrun-run`，某项失败后继续其余项，最后 `exit $fail`。
- **必须显式指定 `REGRESS_ELFS`**（`article.md` 第 6.4 节）：默认值是已存在的全部 `sw/tests/*.spm.elf`，跑过 `sw-all` 后会混入需要 AXI-RT / CLIC 配置的 ELF；默认通配也不含 `.dram.elf`。

### 3.6 单独运行一个用例

```bash
make -f Makefile.xcelium xrun-run BINARY=sw/tests/dma_1d.spm.elf BOOTMODE=0 PRELMODE=1 SEED=1
```

`xrun-run` 依赖 `xrun-compile`，会先检查快照是否需要重编，再检查 `BINARY` 可读，然后以 `-R` 运行已有快照。`.rom.elf` 的加载地址与运行地址不同，不能用于 `PRELMODE=1` 预加载。

## 4. 输出在哪里（`article.md` 第 6.5 节、`Makefile.xcelium` 路径变量）

| 产物 | 路径 | 变量 |
| --- | --- | --- |
| 源码文件列表 | `target/sim/xrun/cheshire_soc.f` | `XRUN_FLIST` |
| 工作库 / 快照 | `target/sim/xrun/work/xcelium.d/` | `XRUN_LIB` |
| 编译日志 | `target/sim/xrun/work/logs/compile.log` | `XRUN_LOGS` |
| 单项日志 | `target/sim/xrun/work/logs/<ELF 去掉 .elf>.log`，如 `dma_2d.spm.log`（`TEST_NAME`） | `XRUN_LOGS` |
| 回归汇总 | `target/sim/xrun/work/logs/regression-known.log`（由上面的 `tee` 产生） | — |
| 覆盖率 | `target/sim/xrun/work/cov_work/`、`logs/<名>.cov.log`、`target/sim/xrun/work/cov_summary.txt` | `XRUN_COV` |
| 波形 | Verisium：`target/sim/xrun/work/ida.db`（`vdebug_probe.tcl` 的相对路径）；`XRUN_WAVES=target/sim/xrun/work/waves` 仅 `xrun-gui` 使用 | `XRUN_WAVES` |

快速查看：

```bash
rg -n 'PASS:|FAIL:|FAILED|SUCCESS|Entrypoint' target/sim/xrun/work/logs/regression-known.log
tail -n 60 target/sim/xrun/work/logs/helloworld.spm.log
```

## 5. 通过 / 失败判定

Makefile 判定（`xrun-run`）：日志中 grep 到 `\[PASS\]` / `SUCCESS` / `exit code 0` 之一 → 打印 `PASS: <name>`；否则 `FAIL: <name> (see <log>)` 并退出 1。这只是辅助判断（`article.md` 第 20.10 节），人工复核要看三层：

1. **加载**：`[ELF] INFO: Entrypoint at 0x10000000`（SPM）或 `0x80000000`（DRAM）、`[SLINK] Preloading section at ...`、`Preload complete`。
2. **行为**：`[UART] Hello World!` 等文本，或软件自检（DMA 类测试没有 UART 文本，靠逐字节比较与返回码）。
3. **结束**：`[SLINK] SUCCESS`（返回码 0；非零时为 `[SLINK] FAILED: return code N`）、`Simulation complete via $finish(1) at time ...`（括号里的 1 **不是** shell 退出码）、`PASS: <name>`、`make` 退出码 0。

返回码协议：`main()` 返回值经 CRT0 写成 `scratch[2] = (ret << 1) | 1`，VIP 轮询 bit 0 后右移得到返回值（`docs/tg/xcelium_zh.md` 第 6.6 节）。

### 5.1 失败也要能证明（`article.md` 第 6.6 节）

把一个测试临时改成 `return 7;`，重新构建该 ELF 并运行，预期日志出现 `FAILED: return code 7`、Makefile 打印 `FAIL:`、`make` 退出码非零。改回后重新构建并确认 PASS。新增测试与修改判定逻辑后都要做一次。

### 5.2 证据清单（写进 PR / 实验记录）

- 提交号 `git rev-parse --short HEAD`，工作树是否干净。
- 工具版本：`bender --version`、`riscv64-unknown-elf-gcc --version | head -1`、`xrun -version`。
- 硬件配置（默认 `SelectedCfg=0`）、运行参数（`BOOTMODE PRELMODE SEED`）。
- 完整命令、`REGRESS_ELFS` 列表。
- 日志路径与 `rg -n 'PASS:|FAIL:|FAILED|SUCCESS|Entrypoint' <log>` 输出、`make` 退出码。
- 范围声明：功能模型（`axi_sim_mem`、AXI 从设备模型作为 Serial Link 远端），不是 DDR 时序或第二颗芯片。

## 6. SEED 与超时

- `SEED`（默认 1）→ `xrun -svseed $(SEED)`，只影响 SV 侧随机（VIP 延迟等）；裸机程序是确定性的。换种子跑同一测试时在日志名里体现，例如 `XRUN_WORK` 换目录或自行重命名日志，避免覆盖。
- `TIMEOUT_NS` 会生成 `+TIMEOUT_NS=`，但 `tb_cheshire_soc.sv` **没有读取它**，不是有效 watchdog（`article.md` 第 20.4 节）。主机侧用：

  ```bash
  timeout 300s make -f Makefile.xcelium xrun-run BINARY=sw/tests/helloworld.spm.elf
  ```

  它限制整个命令（含编译与许可证排队）的墙钟时间，首次编译要放宽。要仿真时间 watchdog，按 `article.md` 第 20.4 节在顶层加 `$value$plusargs("TIMEOUT_NS=%d", ...)` + `$fatal`，并用一个刻意不结束的测试验证它触发。

## 7. 并行运行时隔离工作目录（`article.md` 第 26.7 节）

不同仿真进程不要共用同一个 `XRUN_WORK`：

```bash
make -f Makefile.xcelium xrun-run \
  XRUN_WORK="$PWD/target/sim/xrun/work-dma-check" \
  BINARY=sw/tests/dma_1d.spm.elf
```

`XRUN_LIB`、`XRUN_LOGS`、`XRUN_WAVES`、`XRUN_COV` 都从 `XRUN_WORK` 派生，因此每个独立目录都要先编译一次快照。基础回归顺序执行、复用一个工作库最容易解释日志对应关系。

## 8. 覆盖率（入口已有，流程未作为基线验证）

```bash
make -f Makefile.xcelium xrun-cov BINARY=sw/tests/dma_1d.spm.elf      # -coverage all -covdut cheshire_soc -covtest <name>，日志 logs/<name>.cov.log
make -f Makefile.xcelium xrun-cov-report                                # imc merge target/sim/xrun/work/cov_work/scope/* → cov_summary.txt
```

注意（`article.md` 第 20.8 节、`docs/tg/xcelium_zh.md` 第 10.3 节）：`xrun-cov` 同时带编译参数与 `XRUN_RUN_FLAGS`（默认含 `-R`），要确认是否按覆盖率模式重新插桩、运行是否用到该快照、`-covdut cheshire_soc` scope 是否正确、IMC 合并路径是否匹配。首次使用时先用 Hello World 验证整条流程，把结果记录为「覆盖率流程验证」，再用于计划中的覆盖率问题。覆盖率高不等于检查有效。

## 9. 波形

```bash
make -f Makefile.xcelium xrun-run \
  BINARY=sw/tests/helloworld.spm.elf \
  XRUN_RUN_INPUT=vdebug_probe.tcl
```

`vdebug_probe.tcl` 在工具工作目录（`target/sim/xrun/work/`）生成 Verisium 数据库 `ida.db`，探测全层次（`-all -depth all -memories`），运行与存储成本高，定位问题时缩小范围。`xrun-gui` 引用的 `target/sim/xrun/waves.tcl` 不存在，不能当作已验证的 GUI 流程。先围绕一个问题选信号：CPU 是否执行、某地址请求是否发出、响应是否错误、目标是否写入（`article.md` 第 20.9 节）。

## 10. 改动后要重跑什么

| 改了什么 | 先重建 | 再运行 |
| --- | --- | --- |
| 测试 C / S 源码 | 对应 ELF | 对应用例 |
| 软件头文件 / 库 / 链接脚本 | 相关对象与 ELF（当前头文件依赖跟踪不足，必要时删 `.o` 重编） | 涉及接口的测试；`readelf -l` 核对加载地址 |
| SoC RTL / testbench / 文件列表 | `xrun-all`（必要时 `xrun-clean`） | 六项基础回归 + 相关专项 |
| SystemRDL / HJSON | `make hw-all` + 对应软件头文件 | 软硬件一致性测试 |
| Bender 依赖 / 锁文件 | `bender checkout` → `hw-all` → `xrun-all` | 完整基础回归 |

详见 `cheshire-verify-change`。

## 11. 常见失败速查（`README.md` 第 8 节、`docs/tg/xcelium_zh.md` 第 11 节）

| 现象 | 先看 | 处理 |
| --- | --- | --- |
| Bender `E31` 模型不存在 | `target/sim/models/` | `xrun-flist`；不要造空文件 |
| `ERROR: set BINARY=<elf> or IMAGE=<img>` / `binary not found` | 命令行 `BINARY=` 与文件是否存在 | 先构建 ELF；路径相对仓库根目录 |
| 停在 `[SLINK] Wait for LLC configuration` | CPU / Boot ROM 是否在跑、AXI 响应、crossbar `Connectivity` | 波形定位请求在哪一层出错 |
| `DECERR` / 数据 `CA11AB1EBADCAB1E` | 地址译码、连接矩阵 | 这是错误从设备的固定返回，不是寄存器值 |
| ELF 加载完但无输出 | `riscv64-unknown-elf-readelf -l <elf>` 入口与加载地址 | 是否误用 `.rom.elf`；再查 CPU 异常 |
| 软件报「功能不存在」 | 默认配置是否含该 IP（AXI-RT / CLIC） | 需真正切换 `SelectedCfg` 并重新展开，不是加 `SELCFG=` |
| 只有 `SUCCESS` 没有 UART 文本 | 测试本身是否打印 | DMA 测试正常如此 |
| 回归混入 AXI-RT / CLIC 用例 | `REGRESS_ELFS` | 显式列表 |
| 仓库移动后路径错误 | `cheshire_soc.f` 中的绝对路径 | 重新 `xrun-flist`；必要时 `xrun-clean` |
| 许可证排队 | `-licqueue`、许可证服务器 | 与 EDA 管理员确认 |

`xrun-clean` 删除工作库、文件列表与日志，先保留需要的诊断证据再清理。`make clean-deps` 还会删除 `.bender/`、模型与子模块，范围更大，慎用。

## 12. 在没有 Xcelium 的环境里

写出需要在许可证机器上执行的完整命令块（第 3 节）与预期证据（第 5 节），并明确声明「本环境未执行仿真」。不要用 `make sw-all` 成功代替仿真通过。
