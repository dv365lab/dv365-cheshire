---
name: cheshire-verify-change
description: 在修改 dv365-cheshire 的 RTL、testbench、裸机软件、链接脚本、SystemRDL / HJSON 描述、Bender 依赖或构建 / 仿真脚本之后，决定「改了什么就重建什么」（hw / sw / sim 三条依赖线）、本地要跑哪些 lint（许可证头、Verible、clang-format 14、tclint）、至少运行哪一条相关 ELF 的 Xcelium 仿真，并收集日志证据后才能宣称完成；没有 Xcelium 时给出 build + lint 的降级策略与明确的「未仿真」声明。当用户说「验证我的修改」「改完了要跑什么」「提交前检查」「PR 前自检」「这个改动安全吗」时使用。
---

# 修改后的验证：重建、lint、仿真、证据

依据：`article.md` 第 26.1 / 26.2 节、`.github/workflows/build.yml` 与 `lint.yml`、`Makefile.xcelium`、`cheshire.mk`、`sw/sw.mk`。原则：**改了什么就重建什么 → 静态检查 → 至少一条相关仿真 → 附证据**。没有证据的「完成」只能写成「已 build / lint，未仿真」。

## 1. 三条依赖线（`article.md` 第 26.1 节）

```text
硬件依赖线：Bender.yml → Bender.lock → bender checkout → make hw-all（PeakRDL / regtool 生成）→ xrun-flist → xrun-compile（展开成快照）
软件依赖线：sw/tests/*.c|*.S、sw/lib、sw/include → %.o → sw/lib/libcheshire.a → sw/link/*.ld + cheshire_addrs.ldh → %.<spm|dram|rom>.elf
工具依赖线：pyproject.toml → uv.lock → PeakRDL、regtool、hjson、mako、tclint
```

只固定主仓库提交不等于固定全部环境；记录仿真器与交叉编译器版本。

## 2. 「改了什么就重建什么」矩阵（`article.md` 第 26.2 节 + 具体命令）

| 修改 | 先重建 | 再验证 |
| --- | --- | --- |
| `sw/tests/<t>.c` / `.S` | `make -j4 "$PWD/sw/tests/<t>.spm.elf"`（文件名带 `.spm` / `.dram` 只生成该模式） | `make -f Makefile.xcelium xrun-run BINARY=sw/tests/<t>.spm.elf` |
| `sw/include/*.h`、`sw/include/dif/*.h`、`sw/lib/*.c|*.S` | 相关 `.o`、`sw/lib/libcheshire.a`、所有受影响 ELF；`sw/sw.mk` 的头文件依赖跟踪不足（`TODO: track headers with gcc -MM`），稳妥做法是删除相关 `.o` / `.a` 后重建 | 涉及该接口的测试 + 快速层（`helloworld.spm`、`dma_1d.spm`） |
| `sw/link/*.ld`、`common.ldh` | 对应链接模式的全部 ELF | `riscv64-unknown-elf-readelf -l <elf>` 核对入口 / 加载地址（SPM `0x10000000`，DRAM `0x80000000`）+ 运行对应 ELF |
| `hw/*.sv`、`hw/include/`、Bender 依赖 RTL | `make -f Makefile.xcelium xrun-all`（文件列表未变时只重新编译；改了 `Bender.yml` / `models.mk` 会重新生成 `cheshire_soc.f`） | 六项基础回归 + 相关专项 |
| `hw/cheshire.rdl`、`hw/regs/*.rdl`、`hw/rv_plic.cfg.hjson`、依赖的 `.hjson` | `make hw-all`（生成 `hw/cheshire_addrmap_pkg.sv`、`hw/regs/cheshire_soc_regs*.sv` 等）+ 对应软件头文件（`sw/include/regs/*.h`、`sw/link/cheshire_addrs.ldh` 随 ELF 构建触发）→ `xrun-all` | 软硬件一致性：寄存器读写测试 + 基础回归；提交生成文件 |
| 生成参数（`SLINK_NUM_LANES`、`CLINT_CORES`、`AXIRT_NUM_*`） | 对应生成目标与类型 → `hw-all` → `xrun-all` | 参数组合专项测试 |
| `hw/bootrom/*.S|*.c|*.ld` | `make bootrom-all`（受编译器版本影响，`hw-all` 不会做） | 对比重建前后 `hw/bootrom/cheshire_bootrom.sv` 的差异（`cheshire_bootrom.dump` 是构建产物，不提交）+ 启动回归 |
| `Bender.yml` / `Bender.lock` | `bender checkout` → `make hw-all` → `xrun-flist` → `xrun-all` | 完整基础回归；单独分支、单独说明（`article.md` 第 26.8 节） |
| `target/sim/src/*.sv`、`elfloader.cpp`、`run.xcelium.tcl`、`Makefile.xcelium`、`target/sim/models.mk` | `xrun-all`（改了 Makefile / models.mk 会触发 `cheshire_soc.f` 重新生成） | 参数是否实际生效（`xrun` 命令行回显）+ 退出判定 + 基础回归 |
| `pyproject.toml` / `uv.lock` | `uv sync --locked` → `make hw-all` | 生成文件无差异（`git status --porcelain`） |
| `cheshire.mk` / `sw/sw.mk` / `Makefile` | 受影响目标 | `make help` 目标列表 + CI 等价命令 `uv run --locked make hw-all`、`sw-all`、`sim-all` |
| `.github/workflows/*.yml`、`copilot-setup-steps.yml` | — | YAML 可解析、许可证头、触发条件未改变；`copilot-setup-steps` job 名不变 |
| 文档 / `SKILL.md` / `AGENTS.md` | — | 链接与锚点存在；命令和路径能在仓库中 grep 到；Markdown 不加许可证头 |

CI 在 `hw-all` / `sw-all` / `sim-all` 之后要求 `git status --porcelain --ignore-submodules` 为空：生成文件改了就提交，构建产物不要提交。

## 3. 本地静态检查（与 `.github/workflows/lint.yml` 等价）

### 3.1 许可证头（`lint-license`，lowRISC `licence-checker`）

- 检查对象：git 跟踪的文件，按扩展名识别注释风格：`.sv .svh`（`//`）、`.tcl .sdc .mk Makefile .py .sh .yml .yaml .toml Dockerfile .waiver`（`#`）、`.c .h .cc .cpp .def .rs .go`（`//`）、`.S`（`//` 或 `/* */`）、`.s .ld .css`（`/* */`）、`.hjson`（`//`）等；`.md .html .f` **不检查**。排除：`sw/include/regs/*.h`、`.github/skills/test-gap-audit/scripts/coverage_map.py`。
- 头必须是文件开头第一个注释块里的连续三行（shebang 可在首行）；每行用 `fullmatch` 匹配 `<注释前缀> <正则行>`：

  ```text
  Copyright (\d{4}(-\d{4})?\s)?(ETH Zurich and University of Bologna|lowRISC contributors|DV365 Lab).
  (Solderpad Hardware License, Version 0.51|Licensed under the Apache License, Version 2.0), see LICENSE for details.
  SPDX-License-Identifier: (SHL-0.51|Apache-2.0)
  ```

- 新文件写法（`#` 风格；`//` 风格同理）：

  ```text
  # Copyright 2026 DV365 Lab.
  # Licensed under the Apache License, Version 2.0, see LICENSE for details.
  # SPDX-License-Identifier: Apache-2.0
  ```

- 快速本地核对（只看前 5 行是否出现三行头）：

  ```bash
  for f in $(git diff --cached --name-only --diff-filter=AM | grep -E '\.(sv|svh|tcl|mk|py|sh|yml|yaml|toml|c|h|cpp|S|ld|hjson)$|(^|/)(Makefile|Dockerfile)$'); do
    head -n 5 "$f" | grep -Eq 'Copyright ([0-9]{4}(-[0-9]{4})? )?(ETH Zurich and University of Bologna|lowRISC contributors|DV365 Lab)\.' \
      && head -n 6 "$f" | grep -q 'SPDX-License-Identifier: \(SHL-0.51\|Apache-2.0\)' \
      || echo "MISSING LICENSE HEADER: $f"
  done
  ```

  完整检查用 lowRISC 的 `licence-checker.py --config`（`pulp-platform/pulp-actions/lint-license@v2.4.4` 会生成配置）。

### 3.2 SystemVerilog（`lint-sv`）

```bash
verible-verilog-lint --waiver_files .github/verible.waiver $(git ls-files 'hw/*.sv' 'hw/*.svh' | grep -v '^hw/future/UsbOhciAxi4.v')
```

CI 只 lint `hw/`（排除 `hw/future/UsbOhciAxi4.v`），豁免见 `.github/verible.waiver`。`target/sim/src/*.sv` 不在 CI 范围内，但新代码仍按同样风格写。

### 3.3 C / C++（`lint-cxx`）

```bash
clang-format-14 --dry-run --Werror $(git ls-files 'sw/*.c' 'sw/*.h' 'target/*.cpp' 'hw/bootrom/*.c' 'hw/bootrom/*.h' | grep -v -e '^sw/include/regs/' -e '^target/sim/src/elfloader.cpp$')
```

必须是 **clang-format 14**（其他大版本格式可能不同），配置 `.clang-format`。

### 3.4 Tcl（`lint-tcl`）

```bash
uv run --locked tclint . --style-spaces-in-braces --style-line-length 100
```

### 3.5 构建与干净工作树（`build.yml`）

```bash
uv run --locked make hw-all && uv run --locked make sw-all && uv run --locked make sim-all
git status --porcelain --ignore-submodules     # 必须为空
```

## 4. 仿真证据（有 Xcelium 时必做）

### 4.1 至少运行一条相关 ELF

| 改动涉及 | 最少要跑 |
| --- | --- |
| 取指 / 启动 / UART / CLINT | `helloworld.spm.elf` |
| iDMA 一维 / 二维 | `dma_1d.spm.elf`、`dma_2d.spm.elf` |
| Serial Link / 远端访问 | `dma_slink.spm.elf` |
| 缓存 / SPM 别名 / 自修改代码 | `spm_uncached.spm.elf` |
| 外部 AXI 内存 / LLC / DRAM 链接 | `helloworld.dram.elf` |
| SoC 互连、地址地图、配置包、testbench、构建 / 仿真脚本、依赖版本 | 六项基础回归（`cheshire-regress` 第 3.5 节） |
| 新测试 | 新测试本身 + 快速层；并做负向实验（临时 `return 7;` 应 FAIL） |

```bash
make -f Makefile.xcelium xrun-run BINARY=sw/tests/<name>.spm.elf BOOTMODE=0 PRELMODE=1 SEED=1
rg -n 'PASS:|FAIL:|FAILED|SUCCESS|Entrypoint' target/sim/xrun/work/logs/<name>.spm.log
```

### 4.2 证据要写什么

```text
Commit:   <git rev-parse --short HEAD>（工作树干净 / 有未提交改动）
Tools:    bender X.Y.Z, riscv64-unknown-elf-gcc N, xrun <version>
Config:   SelectedCfg=0 (DefaultCfg), BOOTMODE=0 PRELMODE=1 SEED=1
Rebuilt:  <目标列表>
Lint:     license OK / verible OK / clang-format-14 OK / tclint OK
Command:  make -f Makefile.xcelium xrun-regress ... REGRESS_ELFS="..."
Logs:     target/sim/xrun/work/logs/<name>.log（附 PASS: 行与 Entrypoint 行）
Exit:     make 退出码 0
Negative: <哪个测试的 return 7; 产生了 FAIL>
Scope:    功能模型（axi_sim_mem / AXI 从设备远端），未覆盖 AXI-RT / CLIC 配置
```

判定看三层（加载 / 行为 / 结束），`$finish(1)` 的 1 不是退出码；DMA 测试没有 UART 文本属正常（`cheshire-regress` 第 5 节）。

## 5. 没有 Xcelium 时的降级策略

适用：GitHub Actions、云端 Copilot coding agent、Windows / macOS 会话、未加载 EDA 环境的机器。

1. 完成第 2 节的重建与第 3 节的全部静态检查，并确认 `git status --porcelain --ignore-submodules` 为空。
2. 在 PR 描述 / 回复中使用如下声明，不得省略：

   ```text
   验证范围声明：本改动在无 Xcelium 许可证的环境中完成，只执行了
   - uv run --locked make hw-all / sw-all（通过）
   - 许可证头 / Verible / clang-format 14 / tclint（通过）
   未执行任何 RTL 仿真。合并前需在有许可证的机器上运行：
     make -f Makefile.xcelium xrun-all
     make -f Makefile.xcelium xrun-regress BOOTMODE=0 PRELMODE=1 SEED=1 REGRESS_ELFS="<列表>"
   预期证据：六行 PASS:，make 退出码 0，日志 target/sim/xrun/work/logs/<name>.log。
   ```

3. 不要用「软件能编译」「lint 通过」暗示「仿真通过」；不要尝试安装 EDA 工具或伪造日志。
4. 改动若只涉及文档 / skill / 工作流配置，写明「不影响 RTL 与软件产物，无需仿真」，并给出理由（例如 `git diff --stat` 只有 `.md` / `.yml`）。

## 6. 提交前清单

- [ ] 按矩阵重建了全部受影响产物；生成文件已提交，构建产物未提交。
- [ ] 新增非 Markdown 文件有三行许可证头；Markdown / `SKILL.md` 没有加头。
- [ ] Verible / clang-format 14 / tclint 通过（或说明未触及对应文件类型）。
- [ ] 至少一条相关 ELF 仿真 PASS，日志路径与 `PASS:` 行已附；或已写出第 5 节的降级声明。
- [ ] 新测试做过负向实验。
- [ ] 提交信息（英文）写明改了什么、为什么、如何验证；涉及仿真结果的句子注明机器 / 版本 / 命令。
- [ ] 没有改动既有工作流的触发条件与检查强度；没有 `bender update`。
