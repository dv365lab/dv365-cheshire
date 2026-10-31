# Copilot 工作说明（精简版）

完整版见仓库根目录 [`AGENTS.md`](../AGENTS.md)；本文件只保留最常用的事实与规则，两者冲突时以 `AGENTS.md` 为准。正文中文，标识符 / 命令 / 路径保持英文。

## 这是什么仓库

PULP **Cheshire** RISC-V SoC（CVA6 + AXI + LLC/SPM + iDMA + UART + Serial Link）。SystemVerilog RTL + 裸机 C + Make/Bender/Python 生成工具。DV365 Lab 的 fork 增加了 Cadence Xcelium 流程（`Makefile.xcelium`）和中文文档（`README.md`、`docs/tg/xcelium_zh.md`、`article.md`）。

「验证计划」= 硬件 DV 的 vPlan；「搭建环境」= RTL 仿真环境。已验证基线是**六项基础回归**（默认配置，`BOOTMODE=0 PRELMODE=1 SEED=1`）。

## 仓库地图

`hw/`（RTL、`cheshire.rdl` 地址地图、`regs/` 生成寄存器、`bootrom/`）· `sw/`（`sw.mk`、`tests/`、`link/`、`lib/`、`deps/printf` 子模块）· `target/sim/src/`（`tb_cheshire_soc.sv` → `fixture_cheshire_soc.sv` → `vip_cheshire_soc.sv`，`elfloader.cpp`，`run.xcelium.tcl`）· `target/sim/models.mk` · `target/xilinx/` · `util/` · `docs/`（MkDocs，`docs/vplan/` 放验证计划）· `article.md`（教程，锚点 `#chNN`）· `Makefile` / `cheshire.mk` / `Makefile.xcelium` · `Bender.yml` / `Bender.lock` · `pyproject.toml` / `uv.lock`。

## 命令速查（仓库根目录，Linux）

```bash
git submodule update --init --recursive sw/deps/printf
uv sync --locked --python 3.11 && source .venv/bin/activate     # 或 uv run --locked make <target>
bender checkout
make -j4 hw-all
make -j4 "$PWD/sw/tests/helloworld.spm.elf" "$PWD/sw/tests/dma_1d.spm.elf" \
  "$PWD/sw/tests/dma_2d.spm.elf" "$PWD/sw/tests/dma_slink.spm.elf" \
  "$PWD/sw/tests/spm_uncached.spm.elf" "$PWD/sw/tests/helloworld.dram.elf"
make -f Makefile.xcelium xrun-all
make -f Makefile.xcelium xrun-run BINARY=sw/tests/helloworld.spm.elf BOOTMODE=0 PRELMODE=1 SEED=1
make -f Makefile.xcelium xrun-regress BOOTMODE=0 PRELMODE=1 SEED=1 REGRESS_ELFS="<显式 ELF 列表>"
make -f Makefile.xcelium xrun-cov BINARY=<elf> ; make -f Makefile.xcelium xrun-cov-report
make -f Makefile.xcelium xrun-run BINARY=<elf> XRUN_RUN_INPUT=vdebug_probe.tcl   # Verisium 波形
```

输出：`target/sim/xrun/cheshire_soc.f`、`target/sim/xrun/work/xcelium.d/`、`target/sim/xrun/work/logs/compile.log`、`target/sim/xrun/work/logs/<ELF 去掉 .elf>.log`、`target/sim/xrun/work/cov_work/`。

边界：`REGRESS_ELFS` 必须显式指定（默认通配混入 AXI-RT/CLIC 的 `.spm.elf`，且不含 `.dram.elf`）；`SELCFG` 宏未接到 `SelectedCfg` 参数；`TIMEOUT_NS` 未被 testbench 读取（用 `timeout 300s make ...`）；`xrun-gui` 的 `waves.tcl` 不存在；`xrun-cov` 流程未作为基线验证。

## 规范

- **许可证头**：git 跟踪的 `.sv .tcl .mk .c .h .cpp .S .ld .py .sh .yml .toml` 等必须有三行头（`lint.yml` 正则）；**Markdown 不加头**（`SKILL.md` 的 frontmatter 必须从第 1 行开始）。新文件用 `Copyright 2026 DV365 Lab.` / `Licensed under the Apache License, Version 2.0, see LICENSE for details.` / `SPDX-License-Identifier: Apache-2.0`（硬件文件可用 Solderpad 0.51 / `SHL-0.51`）。
- **lint**：Verible（`hw/`，豁免 `.github/verible.waiver`，排除 `hw/future/UsbOhciAxi4.v`）；clang-format 14（`c,h,cpp`，排除 `sw/include/regs/*.h`、`target/sim/src/elfloader.cpp`）；`uv run --locked tclint . --style-spaces-in-braces --style-line-length 100`。
- **生成文件**（`hw/regs/*.sv`、`hw/cheshire_addrmap_pkg.sv`、`sw/include/regs/*.h`、`sw/link/cheshire_addrs.ldh`）只能通过改描述源 + `make hw-all` 更新；CI 要求构建后 `git status --porcelain --ignore-submodules` 为空。
- 不提交构建产物；不用 `bender update` 修复缺文件；保留 `Bender.lock` / `uv.lock`；新文件 UTF-8（无 BOM）+ LF；提交信息英文。

## 验证与证据（最重要）

- Xcelium 是专有工具：**GitHub Actions 与云端 Copilot coding agent 只能 build + lint，不能仿真。** 任何仿真 / 覆盖率结论必须注明「在有 Xcelium 许可证的机器上、用哪条命令、哪个提交得到」；云端只能写「已 build / lint，未仿真」并给出需要人工执行的命令。
- 通过判定看三层：`[ELF] INFO: Entrypoint at ...` 正确、预期行为（UART 文本或数据比较）、返回码 0（`[SLINK] SUCCESS`、`PASS: <名>`、Make 退出码 0）。`$finish(1)` 的数字不是退出码。DMA 测试可能没有 UART 文本。
- 改动后按 `.github/skills/cheshire-verify-change/SKILL.md`：重建对应产物 → lint → 至少跑一条相关 ELF → 附日志证据。新测试要做负向实验（`return 7;`）。

## Skills（`.github/skills/<name>/SKILL.md`）

| skill | 触发场景 |
| --- | --- |
| `cheshire-env-setup` | 搭建 / 恢复环境、工具版本、`scripts/env_doctor.sh` 体检、找不到 bender / gcc / xrun / peakrdl |
| `cheshire-vplan` | 写硬件验证计划 → `docs/vplan/<feature>.md`（模板 `templates/vplan-template.md`，范例 `docs/vplan/baseline-regression.md`） |
| `cheshire-regress` | 构建 / 运行六项基础回归或单项用例，读日志，判定与证据，SEED / 超时 / 并行 / 覆盖率 / 波形 |
| `cheshire-verify-change` | 改完 RTL / 软件 / 脚本后要重建什么、跑什么、怎么写证据；无 Xcelium 的降级声明 |
| `sv-assertions-coverage` | 接口 SVA 断言与功能覆盖率的写法与放置位置 |
| `test-gap-audit` / `breakdown-test` / `create-implementation-plan` | 第三方通用 skill（MIT，见 `skills/THIRD_PARTY_LICENSES.md`）：测试缺口审计 / 测试策略骨架 / 实施计划 |
