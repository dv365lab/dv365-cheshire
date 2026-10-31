---
name: cheshire-env-setup
description: 为 dv365-cheshire（PULP Cheshire RISC-V SoC）从零搭建或恢复 RTL 仿真开发环境：Git 子模块、uv / Python 3.11、Bender、RISC-V 裸机交叉工具链、Cadence Xcelium 与许可证、Bender 硬件依赖检出与 hw-all 生成，并提供只读体检脚本 scripts/env_doctor.sh。当用户要「搭建环境」「装工具链」「配 Xcelium」「新终端恢复环境」「环境体检」，或报错「找不到 bender / riscv64-unknown-elf-gcc / xrun / peakrdl / hjson / printf.c」「Bender E31 模型不存在」时使用。不要在没有 Xcelium 许可证的机器（CI、云端 Copilot coding agent、Windows 会话）上尝试安装或运行 EDA 工具。
---

# Cheshire 仿真环境搭建与恢复

本 skill 把 `article.md` 第 4 章、`README.md` 第 2–4 节、`.github/Dockerfile` 与 `.github/workflows/build.yml` 中的环境事实整理成可执行的步骤。所有命令在仓库根目录、Linux x86_64 上执行；Windows 只能做文本工作，不能构建或仿真。

## 0. 先判断你在哪种环境

| 环境 | 能做什么 | 不能做什么 |
| --- | --- | --- |
| 有 Xcelium 许可证的 Linux 工作站 / 服务器 | 本 skill 全部步骤，含六项基础回归 | — |
| GitHub Actions / 云端 Copilot coding agent（`copilot-setup-steps.yml` 已预装 uv、RISC-V GCC、Bender 并跑过 `make hw-all sw-all`） | build、lint、单个 ELF、文档 | 安装或运行 Xcelium / IMC；宣称任何仿真结果 |
| Windows / macOS 会话 | 阅读、编辑、写文档 | 构建、仿真 |

云端或 CI 中遇到「需要仿真才能验收」的任务，写明「需在有许可证的机器上执行以下命令」并给出命令，不要尝试 `pip install` / `apt install` 任何 EDA 工具。

## 1. 工具与版本清单

| 工具 | CI 组合（`build.yml` / `Dockerfile`） | README 实测组合（2026-10-04） | 基础回归是否必需 | 作用 |
| --- | --- | --- | --- | --- |
| Git、GNU Make、gcc/g++、curl、wget、unzip、tar、xz、binutils、`flock`（util-linux） | 运行器自带 | Rocky 8.10 系统包 | 是 | 获取源码、调度构建、编译 DPI-C、下载模型 |
| uv + Python | `astral-sh/setup-uv@v6`，`python-version: "3.11"`，`uv run --locked` | uv + Python 3.11.16（`uv sync --locked`） | 是 | PeakRDL 1.5.0 / regblock / rawheader、hjson、mako、regtool |
| Bender | 0.31.0（`pulp-platform/pulp-actions/bender-install@v2.4.4`） | 0.32.1（官方发布包） | 是 | 按 `Bender.lock` 检出 IP，生成源文件列表 |
| RISC-V 裸机 GCC | riscv-collab nightly `2023.03.14`，`ubuntu-22.04`，`riscv64-elf`（命令前缀 `riscv64-unknown-elf-`）；Dockerfile 用 SiFive 8.3.0-2020.04.0 | xPack 15.2.0-1（前缀 `riscv-none-elf-`，需做别名） | 是 | `-march=rv64gc_zifencei -mabi=lp64d`，LTO；`sw/sw.mk` 通过 `-print-prog-name=liblto_plugin.so` 找插件 |
| 主机 G++ | 自带 | 8.5.0 | 是 | 编译 `target/sim/src/elfloader.cpp` |
| Cadence Xcelium（`xrun`）+ IMC（`imc`） | 不可用 | `26.03-a071` | 仿真必需 | 编译、展开、运行、覆盖率；默认参数含 `-debug_opts verisium_pp` |
| slang | v2.0（仅 Dockerfile 源码编译） | — | 否 | 可选 SV 语法检查 |
| `dtc`、`sgdisk`（gdisk） | 完整 `sw-all` / Linux 镜像需要 | 按需 | 否 | 设备树、GPT 镜像 |
| CMake ≥ 3.24、SystemC | — | 按需 | 否 | DRAMSys（`make dramsys-all`，仍需接入顶层参数） |
| Vivado / OpenOCD / GDB | — | 按需 | 否 | FPGA 与上板调试 |

两组组合都通过过各自的流程（CI：build + lint；README：六项 Xcelium 回归）。记录环境时写清用的是哪一组、具体版本号。

## 2. 安装顺序

每一步后面都有「验证」命令；上一步没有通过不要进入下一步。

### 2.1 Linux 基础命令

```bash
# Ubuntu / Debian
sudo apt-get update
sudo apt-get install -y git make gcc g++ curl wget unzip tar xz-utils binutils util-linux ca-certificates
# Rocky / RHEL 8
sudo dnf install -y git make gcc gcc-c++ curl wget unzip tar xz binutils util-linux ca-certificates
# 按需：GPT 镜像与设备树
sudo apt-get install -y gdisk device-tree-compiler    # 或 sudo dnf install -y gdisk dtc
```

验证：`command -v git make gcc g++ curl wget unzip tar flock readelf`。

### 2.2 克隆与子模块

```bash
git clone https://github.com/dv365lab/dv365-cheshire.git
cd dv365-cheshire
git submodule update --init --recursive sw/deps/printf
```

验证：`test -s sw/deps/printf/printf.c && git rev-parse --short HEAD`。`sw/deps/cva6-sdk` 只在构建 Linux 镜像时初始化。保留 `Bender.lock` 与 `uv.lock`。

### 2.3 Python 环境（二选一）

```bash
# 方式 A：uv（推荐，与 CI 一致）
curl -LsSf https://astral.sh/uv/install.sh -o /tmp/cheshire-uv-install.sh && sh /tmp/cheshire-uv-install.sh
export PATH="$HOME/.local/bin:$PATH"
uv python install 3.11
uv sync --locked --python 3.11
source .venv/bin/activate

# 方式 B：已有 Python 3.11 的 pip 路径（不按 uv.lock 锁定）
python3.11 -m venv .venv && source .venv/bin/activate && python -m pip install .
```

验证：

```bash
python --version                                   # >= 3.11
python -c 'import hjson, mako, yaml; print("Python dependencies OK")'
peakrdl --version
```

每次新开终端都要重新 `source .venv/bin/activate`；或者不激活，统一用 `uv run --locked make <target>`。

### 2.4 Bender

```bash
# README 实测版本 0.32.1（Linux x86_64 发布包，含校验）
chs_tools_dir="$HOME/.local/opt/cheshire"
mkdir -p "$chs_tools_dir" "$HOME/.local/bin"
curl -fL --retry 3 \
  https://github.com/pulp-platform/bender/releases/download/v0.32.1/bender-x86_64-unknown-linux-gnu.tar.xz \
  -o "$chs_tools_dir/bender-0.32.1.tar.xz"
printf '%s  %s\n' 59a36723b056a06b266dc68d4ceedcd0aa17a1c096e8c2ea512af264ff6a13f6 \
  "$chs_tools_dir/bender-0.32.1.tar.xz" | sha256sum -c -
tar -xJf "$chs_tools_dir/bender-0.32.1.tar.xz" -C "$chs_tools_dir"
ln -sfn "$chs_tools_dir/bender-x86_64-unknown-linux-gnu/bender" "$HOME/.local/bin/bender"
export PATH="$HOME/.local/bin:$PATH"
```

CI 组合用 `https://pulp-platform.github.io/bender/init | bash -s -- 0.31.0`（见 `.github/Dockerfile`）。验证：`bender --version`。

### 2.5 RISC-V 裸机工具链

`sw/sw.mk` 默认寻找 `riscv64-unknown-elf-gcc`（`CHS_SW_GCC_BINROOT ?= $(dir $(shell which riscv64-unknown-elf-gcc))`）。

```bash
# README 实测：xPack 15.2.0-1，前缀 riscv-none-elf-，需要别名
chs_tools_dir="$HOME/.local/opt/cheshire"
mkdir -p "$chs_tools_dir" "$chs_tools_dir/riscv-bin"
curl -fL --retry 3 \
  https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz \
  -o "$chs_tools_dir/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz"
printf '%s  %s\n' aaaa8060c914851a3e5ee1ba82cc3d6f80972f90638a05c6e823a37557a33758 \
  "$chs_tools_dir/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz" | sha256sum -c -
tar -xzf "$chs_tools_dir/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz" -C "$chs_tools_dir"
chs_riscv_bin="$chs_tools_dir/xpack-riscv-none-elf-gcc-15.2.0-1/bin"
for tool in gcc ar objcopy objdump readelf; do
  ln -sfn "$chs_riscv_bin/riscv-none-elf-$tool" "$chs_tools_dir/riscv-bin/riscv64-unknown-elf-$tool"
done
export PATH="$chs_tools_dir/riscv-bin:$PATH"
```

CI 组合由 `pulp-platform/pulp-actions/riscv-gcc-install@v2.4.4` 下载 `riscv64-elf-ubuntu-22.04-nightly-2023.03.14-nightly.tar.gz`，命令前缀已经是 `riscv64-unknown-elf-`，无需别名。

验证：

```bash
riscv64-unknown-elf-gcc --version
chs_lto_plugin=$(riscv64-unknown-elf-gcc -print-prog-name=liblto_plugin.so)
test -f "$chs_lto_plugin" && echo "LTO plugin: $chs_lto_plugin"
```

`gcc`、`ar` 与 LTO 插件必须来自同一套工具链；`riscv64-linux-gnu-gcc` 是 Linux 用户态工具链，不是这里要的。已有标准前缀工具链时可以只指定目录：`make "$PWD/sw/tests/helloworld.spm.elf" CHS_SW_GCC_BINROOT=/path/to/bin`（只改目录，不改前缀）。

### 2.6 Xcelium 与许可证

加载组织提供的 EDA 环境脚本；手工配置的占位写法：

```bash
export PATH="/path/to/xcelium/tools/bin:$PATH"
export CDS_LIC_FILE="5280@your-license-server"      # 也可能是 LM_LICENSE_FILE，以组织配置为准
command -v xrun imc
xrun -version
command -v g++
```

- `xrun -version` 成功只说明程序能启动；真正编译 / 仿真才占用许可证，`Makefile.xcelium` 的 `-licqueue` 会让工具排队等待可用许可证。
- 默认参数含 `-debug_opts verisium_pp`，旧版工具若不支持，通过 `XRUN_FLAGS` / 覆盖 `XRUN_RUN_FLAGS` 调整，不要改动已验证的默认值。
- Xcelium 不能通过 pip、apt、Docker Hub 公共镜像获得。

### 2.7 检出硬件依赖并生成 RTL

```bash
source .venv/bin/activate
bender checkout                                     # 复现用 checkout；bender update 会改 Bender.lock
git submodule update --init --recursive sw/deps/printf
bender path cva6 && bender path axi && bender path idma && bender path register_interface
make -j4 hw-all                                     # 不重建 Boot ROM；bootrom-all 是单独目标
```

依赖位于 `.bender/git/checkouts/<ip>-<hash>/`，脚本必须用 `bender path <ip>` 查询，不要写死后缀。Bender 0.32.1 默认检出依赖自身的 Git 子模块（如 CVA6 的缓存依赖），不要设置 `BENDER_GIT_SUBMODULES=false`。`cheshire.mk` 会在首次 Make 时自动执行 `bender checkout` 与 `printf` 子模块初始化（`$(BENDER_ROOT)/.chs_deps`）。

### 2.8 冒烟测试（有 Xcelium 时）

```bash
make -j4 "$PWD/sw/tests/helloworld.spm.elf"
make -f Makefile.xcelium xrun-flist                 # 下载 s25fs512s.v、24FC1025.v，生成 cheshire_soc.f
test -s target/sim/models/s25fs512s.v && test -s target/sim/models/24FC1025.v && test -s target/sim/xrun/cheshire_soc.f
make -f Makefile.xcelium xrun-all
make -f Makefile.xcelium xrun-run BINARY=sw/tests/helloworld.spm.elf BOOTMODE=0 PRELMODE=1 SEED=1
```

预期日志末尾出现 `[ELF] INFO: Entrypoint at 0x10000000`、`[UART] Hello World!`、`[SLINK] SUCCESS`、`PASS: helloworld.spm`，且 Make 退出码为 0。之后按 `cheshire-regress` 跑六项基础回归。

## 3. 新终端的恢复步骤

```bash
cd /path/to/dv365-cheshire
export PATH="$HOME/.local/bin:$HOME/.local/opt/cheshire/riscv-bin:$PATH"
source .venv/bin/activate
# 此处加载实际的 Xcelium 环境脚本 / 许可证变量
command -v bender python peakrdl riscv64-unknown-elf-gcc riscv64-unknown-elf-ar g++ xrun
bash .github/skills/cheshire-env-setup/scripts/env_doctor.sh
```

把 PATH 设置写进 shell 启动文件可以免去重复操作。仓库目录移动后要重新生成 `target/sim/xrun/cheshire_soc.f`（含绝对路径）。

## 4. 体检脚本 `scripts/env_doctor.sh`

```bash
bash .github/skills/cheshire-env-setup/scripts/env_doctor.sh            # 在仓库任意子目录执行均可
bash .github/skills/cheshire-env-setup/scripts/env_doctor.sh --strict   # WARN 也计为失败
bash .github/skills/cheshire-env-setup/scripts/env_doctor.sh --no-xcelium   # 明确声明本机不做仿真，xrun/imc 缺失只记 INFO
```

- 只读：不安装、不下载、不修改任何文件，不触发 Make 规则。
- 检查项：仓库根目录与锁文件；`printf` 子模块；基础命令；Python ≥ 3.11 与 `hjson` / `mako` / `yaml` / `peakrdl`；Bender 版本（0.31.0 或 0.32.1 之外给 WARN）；`riscv64-unknown-elf-{gcc,ar,objcopy,objdump,readelf}` 与 LTO 插件；主机 `g++`；`xrun` / `imc` 与 `CDS_LIC_FILE` / `LM_LICENSE_FILE`；Bender 依赖是否检出（`.bender/.chs_deps`、`bender path cva6`）；外设模型与文件列表是否存在；`target/sim/src/run.xcelium.tcl` 是否存在；可选的 `dtc` / `sgdisk`。
- 输出：每项 `PASS` / `WARN` / `FAIL` / `INFO`，末尾汇总计数。退出码 0 = 没有 FAIL；1 = 有 FAIL（`--strict` 时含 WARN）；2 = 参数错误或不在 git 仓库内。
- 把脚本输出贴进实验记录或 PR，作为「环境已核对」的证据。

## 5. 常见故障与排查

| 现象 | 优先检查 | 处理 |
| --- | --- | --- |
| `bender` / `riscv64-unknown-elf-gcc` / `xrun` 找不到 | `command -v`、PATH、是否新开终端 | 按第 3 节恢复 PATH 与 EDA 环境 |
| `hjson` / `mako` 缺失、`peakrdl` 找不到 | `python --version`、`.venv` 是否激活 | `source .venv/bin/activate` 或 `uv run --locked make ...` |
| `printf.c` 缺失 | `test -s sw/deps/printf/printf.c` | `git submodule update --init --recursive sw/deps/printf` |
| Bender `E31`：`target/sim/models/s25fs512s.v` 不存在 | 模型是否下载、网络、ZIP 解压 | `make -f Makefile.xcelium xrun-flist`；不要创建空文件或删除模型实例 |
| CVA6 / HPDcache 等 IP 源文件缺失 | `bender checkout` 是否成功、依赖子模块是否被禁用 | 重新 `bender checkout`；保留 `Bender.lock`；不要用 `bender update` |
| 生成的寄存器 RTL / 头文件缺失 | Python 环境、`make -j4 hw-all` 的第一个错误 | 修正环境后重跑 `hw-all` |
| `ar` / LTO 插件错误 | `riscv64-unknown-elf-gcc -print-prog-name=liblto_plugin.so` 是否存在 | 不要混用不同工具链的 `gcc` 与 `ar`；必要时覆盖 `CHS_SW_LTOPLUG` |
| Xcelium 无法取得许可证 / 长时间排队 | 许可证服务器、`CDS_LIC_FILE` / `LM_LICENSE_FILE` | 与 EDA 管理员确认；`-licqueue` 会等待 |
| `SVNSTP` 常量函数错误 | `hw/cheshire_soc.sv` 是否为当前版本 | 地址规则结构体已改为显式位宽，确认没有回退 |
| 停在 `[SLINK] Wait for LLC configuration` | CPU / Boot ROM 活动、AXI 响应、交叉开关 `Connectivity` | 见 `docs/tg/xcelium_zh.md` 第 4.4 / 11 节 |
| 仓库移动后引用旧路径 | `target/sim/xrun/cheshire_soc.f` 内的绝对路径 | 重新 `xrun-flist`；必要时 `xrun-clean` 后重编 |

`make clean-deps` 会删除 `.bender/`、模型与子模块检出，范围很大；一个 Python 或寄存器生成错误不需要从全部依赖重来。

## 6. 记录要求

第一次配置成功后，把下面内容写进实验记录（`article.md` 第 26.9 节）：Bender、Python、PeakRDL、交叉编译器、主机 G++、Xcelium 的版本；采用的是 CI 组合还是 README 组合；`git rev-parse --short HEAD`；`env_doctor.sh` 输出。换机器时先比较环境，再比较日志。

## 相关文件

- `article.md` 第 4 章（`#ch04`）、第 21.8 节、第 28.5 节
- `README.md` 第 2–4、8 节
- `docs/tg/xcelium_zh.md` 第 5、11 节
- `.github/Dockerfile`、`.github/workflows/build.yml`、`.github/workflows/copilot-setup-steps.yml`
- `cheshire.mk`（`.chs_deps` 规则）、`sw/sw.mk`（工具链变量）、`target/sim/models.mk`、`Makefile.xcelium`
