# DV365 Cheshire

项目仓库：[dv365lab/dv365-cheshire](https://github.com/dv365lab/dv365-cheshire)。

Cheshire 是一个围绕 RISC-V [CVA6](https://github.com/openhwgroup/cva6) 处理器构建的可配置 SoC，包含 AXI 总线、片上存储、DMA、UART、Serial Link 等模块。平台具备运行 Linux 的能力；本文的快速复现运行的是**裸机软件与真实 RTL 仿真**，不涉及 Linux 启动。

Cheshire 的原始硬件和软件来自 ETH Zurich 与 University of Bologna 联合开展的 PULP 项目。本仓库保留原有许可证与作者声明。

本文直接给出从 `git clone` 到 Xcelium 回归通过的完整步骤。实际文件名是 **`Makefile.xcelium`**，Linux 区分大小写，请按本文的文件名执行命令。除工具安装命令外，所有构建与仿真命令都在仓库根目录执行。

## 1. 已验证的环境与结果

2026 年 10 月 4 日，在 Rocky Linux 8.10、Linux x86_64 环境中，以下组合已完成六项 RTL 仿真并全部通过：

| 工具 | 已验证版本 | 用途 |
| --- | --- | --- |
| GNU Make | 4.2.1 | 调度依赖、生成与编译任务 |
| Bender | 0.32.1 | 按锁文件检出硬件 IP，生成源文件列表 |
| Python | 3.11.16 | 执行寄存器、模板和地址映射生成工具 |
| PeakRDL / regblock / rawheader | 1.5.0 / 1.3.1 / 0.2.8 | 从 SystemRDL 生成 RTL、头文件和地址定义 |
| RISC-V GCC | xPack 15.2.0-1 | 交叉编译运行在 CVA6 上的程序 |
| 主机 G++ | 8.5.0 | 编译 ELF 加载器的 DPI-C 代码 |
| Cadence Xcelium | `26.03-a071` | 编译、展开并运行 SystemVerilog |

这是一组实测成功的版本，不代表其他版本都不能使用。项目要求 Python >= 3.11；首次复现建议使用下文明确的 Bender 和 GCC 版本，并保留仓库的 `Bender.lock` 与 `uv.lock`。

六项已通过的用例见第 6 节。AXI-RT、CLIC 等专用测试还需要不同的硬件配置，其现状单独列在第 7 节，不能把“软件能够编译”视为“RTL 仿真已经通过”。

## 2. 克隆项目与安装基础工具

### 2.1 获取仓库

```bash
git clone https://github.com/dv365lab/dv365-cheshire.git
cd dv365-cheshire
git submodule update --init --recursive sw/deps/printf
```

`printf` 是裸机软件使用的 Git 子模块，普通 `git clone` 不会填充其内容。硬件 IP 由 Bender 管理，不能只靠 `git submodule update` 获取完整 RTL。

`sw/deps/cva6-sdk` 用于额外的 Linux 镜像构建，**运行本文六个裸机用例不需要初始化它**。如果以后构建 Linux，再执行：

```bash
git submodule update --init --recursive sw/deps/cva6-sdk
```

### 2.2 安装 Linux 基础命令

Rocky Linux 8 / RHEL 8 系列：

```bash
sudo dnf install -y git make gcc gcc-c++ curl wget unzip tar xz binutils util-linux ca-certificates
```

Ubuntu / Debian 系列：

```bash
sudo apt-get update
sudo apt-get install -y git make gcc g++ curl wget unzip tar xz-utils binutils util-linux ca-certificates
```

这些命令提供主机编译器、下载/解压工具、`readelf` 与 `flock`。主机 GCC/G++ 编译的是 Linux 上的生成工具或 DPI-C 代码，与后面编译 RISC-V 程序的交叉编译器不同。

如果还要执行完整的 `make sw-all` 或 `make all`，应安装磁盘镜像工具 `sgdisk`；构建设备树还需要 `dtc`：

```bash
# Rocky Linux：按需安装。
sudo dnf install -y gdisk dtc

# Ubuntu / Debian：按需安装。
sudo apt-get install -y gdisk device-tree-compiler
```

本文按需构建六个 ELF，不依赖设备树或完整 Linux 镜像。默认外部内存模型也不需要 DRAMSys/SystemC；后续若构建 DRAMSys，应另行准备 CMake >= 3.24 及其依赖。

## 3. 配置 Python、Bender、RISC-V GCC 和 Xcelium

### 3.1 Python 环境：推荐使用仓库锁文件

推荐用 [uv](https://docs.astral.sh/uv/getting-started/installation/) 安装独立 Python，并按 `uv.lock` 恢复依赖。这样不必替换 Rocky Linux 自带的系统 Python。

```bash
# 已有 uv 时跳过安装步骤。
curl -LsSf https://astral.sh/uv/install.sh -o /tmp/cheshire-uv-install.sh
sh /tmp/cheshire-uv-install.sh
export PATH="$HOME/.local/bin:$PATH"

# 在仓库根目录执行。
uv python install 3.11
uv sync --locked --python 3.11
source .venv/bin/activate

python --version
python -c 'import hjson, mako, yaml; print("Python dependencies OK")'
peakrdl --version
```

`pyproject.toml` 声明所需包，`uv.lock` 固定解析后的版本；其中包含 PeakRDL、寄存器生成插件、HJSON、Mako 等依赖。GitHub 的构建流程也使用 `uv run --locked`。

如果已有 Python 3.11，也可采用本机六项仿真实测使用过的 pip 路径。与上面的 uv 路径**选择一种即可**：

```bash
python3.11 -m venv .venv
source .venv/bin/activate
python -m pip install .
```

pip 会安装 `pyproject.toml` 声明的依赖，但不会使用 `uv.lock` 固定版本。每次打开新终端运行 `make` 前，都应先 `source .venv/bin/activate`；仅安装包却忘记激活环境，仍可能出现 `hjson`、`mako` 或 `peakrdl` 找不到的错误。

### 3.2 安装 Bender 0.32.1

下面使用 [Bender 官方发布包](https://github.com/pulp-platform/bender/releases/tag/v0.32.1)，适用于本文已验证的 Linux x86_64 环境，无需安装 Rust 或取得系统管理员权限：

```bash
chs_tools_dir="$HOME/.local/opt/cheshire"
mkdir -p "$chs_tools_dir" "$HOME/.local/bin"

curl -fL --retry 3 \
  https://github.com/pulp-platform/bender/releases/download/v0.32.1/bender-x86_64-unknown-linux-gnu.tar.xz \
  -o "$chs_tools_dir/bender-0.32.1.tar.xz"

printf '%s  %s\n' \
  59a36723b056a06b266dc68d4ceedcd0aa17a1c096e8c2ea512af264ff6a13f6 \
  "$chs_tools_dir/bender-0.32.1.tar.xz" | sha256sum -c -

tar -xJf "$chs_tools_dir/bender-0.32.1.tar.xz" -C "$chs_tools_dir"
ln -sfn "$chs_tools_dir/bender-x86_64-unknown-linux-gnu/bender" "$HOME/.local/bin/bender"
export PATH="$HOME/.local/bin:$PATH"
bender --version
```

已有兼容 Bender 时可跳过安装。非 x86_64 主机应选择发布页对应的构建，不能直接套用上面的包名与校验值。

### 3.3 安装已验证的 RISC-V 裸机工具链

本项目需要 `riscv64-unknown-elf-gcc`、`ar`、`objcopy`、`objdump` 等工具；Linux 用户态的 `riscv64-linux-gnu-gcc` 不是这里使用的工具链。

下面安装 [xPack GNU RISC-V Embedded GCC 15.2.0-1](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/tag/v15.2.0-1)。该包的命令前缀为 `riscv-none-elf-`，因此还要提供项目要求的命令别名：

```bash
chs_tools_dir="$HOME/.local/opt/cheshire"
mkdir -p "$chs_tools_dir" "$chs_tools_dir/riscv-bin"

curl -fL --retry 3 \
  https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz \
  -o "$chs_tools_dir/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz"

printf '%s  %s\n' \
  aaaa8060c914851a3e5ee1ba82cc3d6f80972f90638a05c6e823a37557a33758 \
  "$chs_tools_dir/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz" | sha256sum -c -

tar -xzf "$chs_tools_dir/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz" -C "$chs_tools_dir"
chs_riscv_bin="$chs_tools_dir/xpack-riscv-none-elf-gcc-15.2.0-1/bin"

for tool in gcc ar objcopy objdump readelf; do
  ln -sfn "$chs_riscv_bin/riscv-none-elf-$tool" \
    "$chs_tools_dir/riscv-bin/riscv64-unknown-elf-$tool"
done

export PATH="$chs_tools_dir/riscv-bin:$PATH"
riscv64-unknown-elf-gcc --version
chs_lto_plugin=$(riscv64-unknown-elf-gcc -print-prog-name=liblto_plugin.so)
printf 'LTO plugin: %s\n' "$chs_lto_plugin"
test -f "$chs_lto_plugin"
```

软件构建采用 `-march=rv64gc_zifencei -mabi=lp64d`，并使用链接时优化 LTO。当前 [sw/sw.mk](sw/sw.mk) 会向 GCC 查询 LTO 插件位置，无需手工修改插件路径。

如果已有标准前缀的工具链，可以直接加入 PATH，也可以在构建时指定目录：

```bash
make -j4 "$PWD/sw/tests/helloworld.spm.elf" \
  CHS_SW_GCC_BINROOT=/path/to/riscv64-unknown-elf-toolchain/bin
```

`CHS_SW_GCC_BINROOT` 只修改目录，不修改命令前缀。直接把它指向只有 `riscv-none-elf-*` 的目录仍会找不到工具，应先建立上面的别名。

### 3.4 配置 Cadence Xcelium 和许可证

Xcelium 是商业仿真器，需要已有合法安装与可用许可证。本次使用 `26.03-a071`；不能通过安装 Python 包或克隆仓库获得它。

请加载所在组织提供的 EDA 环境脚本；若手工配置，可参考下面的写法，替换为实际安装目录与许可证服务器：

```bash
# 示例占位值，必须替换后再执行。
export PATH="/path/to/xcelium/tools/bin:$PATH"
export CDS_LIC_FILE="5280@your-license-server"

command -v xrun
xrun -version
command -v g++
```

许可证环境变量也可能由组织通过 `LM_LICENSE_FILE` 等方式配置，应以实际 EDA 环境为准。`xrun -version` 能确认程序可执行，但只有真正编译/仿真才能确认许可证可用。

默认 Makefile 含 `-debug_opts verisium_pp`，旧版工具可能不支持相同选项；首次复现优先使用已经验证的版本。

### 3.5 每次打开新终端后的环境检查

按本文安装工具后，新终端可以这样恢复环境；Xcelium 的环境仍需按上一节加载：

```bash
export PATH="$HOME/.local/bin:$HOME/.local/opt/cheshire/riscv-bin:$PATH"
# 进入自己实际克隆的仓库目录。
cd /path/to/dv365-cheshire
source .venv/bin/activate

command -v bender python peakrdl riscv64-unknown-elf-gcc riscv64-unknown-elf-ar g++ xrun
python --version
bender --version
riscv64-unknown-elf-gcc --version
xrun -version
```

若把 PATH 设置保存到自己的 shell 启动文件，就不必每次重复手工设置。仓库目录移动后，应重新生成第 4 节的文件列表，其中包含绝对路径。

## 4. 如何获取完整 RTL 与仿真依赖

### 4.1 分清源文件来自哪里

完整的可编译设计来自四部分，不是只有 `hw/` 中的文件：

| 来源 | 主要内容 | 获取或生成方式 |
| --- | --- | --- |
| 主仓库 | Cheshire SoC、Boot ROM RTL、封装、testbench、DPI 加载器 | `git clone` |
| Bender 硬件依赖 | CVA6、AXI、LLC、iDMA、Serial Link、CLINT、OpenTitan 外设等及传递依赖 | `bender checkout`，版本由 `Bender.lock` 固定 |
| 生成的 RTL 与软件头文件 | SoC/IP 寄存器、地址映射、iDMA 生成模块等 | 激活 Python 环境后运行 `make hw-all` 与所需软件目标 |
| 外设仿真模型 | SPI NOR Flash 和 I²C EEPROM 的 Verilog 行为模型 | `Makefile.xcelium` 包含的 [models.mk](target/sim/models.mk) 自动下载 |

`Bender.yml` 描述依赖与源文件组，`Bender.lock` 锁定实际修订版本；Bender 的检出目录位于 `.bender/git/checkouts/`。不同检出可能带不同目录后缀，应使用 `bender path` 查找，不要在脚本中写死后缀。

### 4.2 检出硬件 IP 与其子模块

```bash
source .venv/bin/activate
bender checkout
git submodule update --init --recursive sw/deps/printf

# 查询几个实际的硬件依赖目录。
bender path cva6
bender path idma
bender path register_interface
```

Bender 0.32.1 默认会检出硬件依赖自身的 Git 子模块，例如 CVA6 的缓存依赖。不要设置 `BENDER_GIT_SUBMODULES=false` 跳过它们；若需要明确开启，可使用 `bender --git-submodules true checkout`。

首次检出会访问多个第三方仓库，需要能连接对应 Git 托管服务。普通裸机仿真不需要 `make nonfree-init` 或访问内部私有仓库。

**复现时使用 `bender checkout`，不要用 `bender update` 修复缺失文件。** `update` 会重新解析依赖并可能改变锁文件，得到与已验证组合不同的 RTL。

### 4.3 生成所需 RTL

```bash
make -j4 hw-all
```

此步骤根据 SystemRDL/HJSON 等描述生成寄存器 RTL、地址映射和依赖 IP 的配置文件。硬件配置与软件寄存器定义必须一致，不能随意从其他版本复制一个生成文件来替代。

本文使用仓库已有的 `hw/bootrom/cheshire_bootrom.sv`；`hw-all` **不会重建 Boot ROM**。`make bootrom-all` 是额外目标，会受交叉编译器版本影响，首次复现不需要运行。

### 4.4 下载外设模型并生成 Xcelium 文件列表

```bash
make -f Makefile.xcelium xrun-flist

test -s target/sim/models/s25fs512s.v
test -s target/sim/models/24FC1025.v
test -s target/sim/xrun/cheshire_soc.f
```

该目标会在调用 Bender 生成列表前，先准备两个模型：

- `s25fs512s.v`：从 Free Model Foundry 下载，模块名为 `s25fs512s`。
- `24FC1025.v`：从 Microchip 的 ZIP 包解压，模块名为 `M24FC1025`。

来源地址和下载规则见 [target/sim/models.mk](target/sim/models.mk)。这些外部模型各有自己的使用条款，执行下载目标前请阅读 [Getting Started 的模型说明](docs/gs.md#building-cheshire)。它们不随主仓库发布，因此普通 `git clone` 后缺少这两个文件属于正常情况；`xrun-flist` 会获取它们。

生成文件 `target/sim/xrun/cheshire_soc.f` 包含源文件与 include 目录，并按依赖顺序组织本地 testbench。当前使用的 Bender 目标是：

```text
-t sim -t rtl -t cva6 -t cv64a6_imafdchsclic_sv39 -t simulation
```

Makefile 会补入 VIP 所需的少量 AXI/JTAG 辅助文件，再按 `tb_cheshire_pkg` → `vip_cheshire_soc` → `fixture_cheshire_soc` → `tb_cheshire_soc` 排列顶层文件。不要为了“获取更多 RTL”直接加入整个依赖树的 `-t test`，那会引入其他 IP 的独立自测环境。

可检查文件列表中的源文件是否都存在：

```bash
python - <<'PY'
from pathlib import Path
lines = Path('target/sim/xrun/cheshire_soc.f').read_text().splitlines()
files = [line.strip() for line in lines
         if line.strip() and not line.strip().startswith(('+', '-', '#', '//'))]
missing = [name for name in files if not Path(name).is_file()]
if missing:
    raise SystemExit('Missing sources:\n' + '\n'.join(missing))
print(f'All {len(files)} source-file entries exist.')
PY
```

最终是否能正确编译和展开，还要由下一节的 `xrun-all` 验证。`.bender/`、下载模型和 Xcelium 工作目录均被 Git 忽略；重新克隆后应重新准备，不能假定它们已经随仓库提交。

## 5. 编译软件并跑通第一个用例

### 5.1 构建六个已验证的 ELF

确认 Python 环境已激活、Bender/IP 与交叉编译器可用，然后执行：

```bash
make -j4 \
  "$PWD/sw/tests/helloworld.spm.elf" \
  "$PWD/sw/tests/dma_1d.spm.elf" \
  "$PWD/sw/tests/dma_2d.spm.elf" \
  "$PWD/sw/tests/dma_slink.spm.elf" \
  "$PWD/sw/tests/spm_uncached.spm.elf" \
  "$PWD/sw/tests/helloworld.dram.elf"
```

使用 `"$PWD/..."` 可以明确匹配构建系统中以绝对路径声明的目标。构建会生成相关软件头文件、编译 C/汇编、归档 `libcheshire.a`，再用相应链接脚本生成 RISC-V ELF。

如果需要编译全部软件与镜像，可在安装相应工具后运行 `make -j4 sw-all`；`make all` 还会准备标准仿真脚本和模型，但**不会自动执行 Xcelium 用例**。

### 5.2 编译和展开 RTL

```bash
make -f Makefile.xcelium xrun-all
```

`xrun-all` 依次准备文件列表并运行 `xrun-compile`。Xcelium 编译 SystemVerilog 与 `target/sim/src/elfloader.cpp`，再展开 `tb_cheshire_soc`，生成可运行的工作库与快照。

首次运行需要处理全部 IP，耗时通常比后续测试长。编译日志位于：

```text
target/sim/xrun/work/logs/compile.log
```

### 5.3 运行 SPM Hello World

```bash
make -f Makefile.xcelium xrun-run \
  BINARY=sw/tests/helloworld.spm.elf BOOTMODE=0 PRELMODE=1 SEED=1
```

这些值也是当前 Makefile 的默认运行配置。其工作过程是：

1. CPU 从 Boot ROM 启动，初始化 LLC/SPM，等待外部程序。
2. VIP 通过 DPI-C 解析 ELF 的加载区域和入口地址。
3. VIP 经 Serial Link/AXI 将代码与数据写入 SPM。
4. VIP 写入启动寄存器，Boot ROM 跳到 ELF 入口执行程序。
5. 软件通过 UART 输出，并把返回码交给 VIP；成功时 Makefile 输出 `PASS`。

典型成功标记包括：

```text
[ELF] INFO: Entrypoint at 0x10000000
[UART] Hello World!
[SLINK] SUCCESS
PASS: helloworld.spm
```

`xrun-run` 会先检查编译步骤、输入 ELF 的可读性，再启动仿真；默认 Tcl 脚本是 `target/sim/src/run.xcelium.tcl`，运行结束后自动退出。

这里应使用 **`.spm.elf`**。同一个 C 程序生成的 `.rom.elf` 用于另一种启动流程：其加载地址和运行地址不同。当前 DPI 加载器按 ELF `p_paddr` 写入，不能把 `.rom.elf` 直接替换到这条 SPM 预加载命令中。

DRAM 版本的入口位于 `0x80000000`，默认通过 `axi_sim_mem` 提供外部 AXI 内存；这不等于已配置 DRAMSys 或真实 DDR 时序模型。

## 6. 运行全部六个已通过的 case

### 6.1 用例与验证内容

| ELF：位于 `sw/tests/` | 验证内容 | 当前结果 |
| --- | --- | --- |
| `helloworld.spm.elf` | 从 SPM 执行、时钟测量与 UART 输出 | PASS |
| `dma_1d.spm.elf` | 一维 DMA 搬运与数据比较 | PASS |
| `dma_2d.spm.elf` | 二维 DMA 重复次数、步长与重叠搬运结果 | PASS |
| `dma_slink.spm.elf` | CPU 经 Serial Link 写入远端，DMA 读回并比较 | PASS |
| `spm_uncached.spm.elf` | DMA 修改指令后，经非缓存 SPM 地址执行新代码 | PASS |
| `helloworld.dram.elf` | 从外部 AXI 内存模型执行并输出 UART 文本 | PASS |

全部采用默认 SoC 配置、`BOOTMODE=0`、`PRELMODE=1`、`SEED=1`。某些 DMA 测试不打印 Hello World，其判断依据是数据比较和返回码，不能仅因没有 UART 文本就认定失败。

### 6.2 单独运行任意一个用例

把上表的 ELF 文件名传给 `BINARY` 即可，例如：

```bash
make -f Makefile.xcelium xrun-run BINARY=sw/tests/dma_1d.spm.elf
make -f Makefile.xcelium xrun-run BINARY=sw/tests/dma_2d.spm.elf
make -f Makefile.xcelium xrun-run BINARY=sw/tests/dma_slink.spm.elf
make -f Makefile.xcelium xrun-run BINARY=sw/tests/spm_uncached.spm.elf
make -f Makefile.xcelium xrun-run BINARY=sw/tests/helloworld.dram.elf
```

### 6.3 一次运行全部六个用例

先完成第 5.1 节的软件构建，再执行下面整段命令：

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
  BOOTMODE=0 PRELMODE=1 SEED=1 REGRESS_ELFS="$chs_known_cases" \
  2>&1 | tee target/sim/xrun/work/logs/regression-known.log
```

以上代码使用 Bash。`set -o pipefail` 让仿真失败时，即使经过 `tee` 保存日志，整个管道仍返回失败。全部通过时，退出码为 0，汇总输出为：

```text
PASS: helloworld.spm
PASS: dma_1d.spm
PASS: dma_2d.spm
PASS: dma_slink.spm
PASS: spm_uncached.spm
PASS: helloworld.dram
```

`xrun-regress` 按顺序调用各用例；某项失败后仍会继续后面的测试，最终汇总返回非零。它**不负责构建软件 ELF**，所以不能跳过第 5.1 节。

必须明确指定 `REGRESS_ELFS`：其默认值是所有已经存在的 `sw/tests/*.spm.elf`，可能混入第 7 节的专用测试，而且不会自动包含 `.dram.elf`。

### 6.4 日志、重复运行与清理

| 输出 | 路径 |
| --- | --- |
| 文件列表 | `target/sim/xrun/cheshire_soc.f` |
| Xcelium 工作库 | `target/sim/xrun/work/xcelium.d/` |
| 编译日志 | `target/sim/xrun/work/logs/compile.log` |
| 回归汇总 | `target/sim/xrun/work/logs/regression-known.log` |
| 单用例日志 | `target/sim/xrun/work/logs/<ELF 去掉 .elf>.log`，如 `dma_1d.spm.log` |

修改测试程序后，先重新构建对应 ELF，再执行 `xrun-run`。修改硬件/IP 配置后，重新运行 `make hw-all` 与 Xcelium 编译。多个仿真进程不能同时使用同一个 `XRUN_WORK`；上面的回归按顺序执行。

```bash
# 查看一个用例的结尾。
tail -n 60 target/sim/xrun/work/logs/helloworld.spm.log

# 查看 Makefile 提供的目标。
make -f Makefile.xcelium xrun-help

# 需要完整重编时再清理；此命令会删除工作库和现有日志。
make -f Makefile.xcelium xrun-clean
```

## 7. 其他已知用例与当前使用边界

### 7.1 仓库中的专用测试

除六个已通过的 ELF 外，仓库还有以下测试源码。它们能够被软件构建系统识别，但本次没有记录为 Xcelium 仿真通过：

| 源文件：位于 `sw/tests/` | 所需硬件能力 | 当前验证状态 |
| --- | --- | --- |
| `axirt_hello.spm.c` | AXI-RT | 未完成对应配置的仿真验证 |
| `axirt_budget.spm.c` | AXI-RT 与 DMA | 未完成对应配置的仿真验证 |
| `axirt_budget_isolate.spm.c` | AXI-RT、DMA 与预算隔离配置 | 未完成对应配置的仿真验证 |
| `clic_basic.spm.S` | CLIC | 未完成对应配置的仿真验证 |
| `clic_multiple.spm.S` | CLIC 的中断优先级与阈值 | 未完成对应配置的仿真验证 |
| `clic_smode.spm.S` | 支持 S-mode 的 CLIC 配置 | 未完成对应配置的仿真验证 |
| `clic_vsmode.spm.S` | 支持 VS-mode 的虚拟化 CLIC 配置 | 未完成对应配置的仿真验证 |

[tb_cheshire_pkg.sv](target/sim/src/tb_cheshire_pkg.sv) 定义了配置索引 0（默认）、1（AXI-RT）、2（CLIC）、3（vCLIC）。但当前 `Makefile.xcelium` 的 `SELCFG` 只传入同名预处理宏，顶层实际使用的是 `SelectedCfg` 模块参数，源码没有把两者连接起来。

因此，**仅添加 `SELCFG=1/2/3` 不会正确切换 SoC 配置**。要验证这些专用用例，需要先正确设置顶层模块参数，重新生成/展开相应硬件，并确认测试需要的 CPU 特权级与外设功能；不能直接把它们加入默认配置回归后声称全部通过。

### 7.2 其他仿真接口

| 接口 | 当前状态 |
| --- | --- |
| `PRELMODE=0/2/3` | 对应 JTAG/UART/MEMH 加载入口；六项实测回归使用的是 1，即 Serial Link |
| `BOOTMODE=2/3` | 对应外部启动路径，需要正确镜像；未完成端到端验证 |
| `BOOTMODE=1` | 当前 testbench 明确不支持 SD Card 启动 |
| `USE_DRAMSYS=1` | SystemC/库路径仍有 TODO；还需正确设置顶层 `UseDramSys` 参数 |
| `TIMEOUT_NS` | 当前 testbench 未读取该 plusarg，不能用它提供有效 watchdog |
| `xrun-gui` | 当前引用的 `target/sim/xrun/waves.tcl` 不存在，不能直接作为已验证 GUI 流程使用 |
| `xrun-cov` / `xrun-cov-report` | 已有入口，覆盖率运行与 IMC 报告流程尚未验证 |

调试时可以显式选择已有 Verisium 探测脚本；这属于可选波形入口，不计入六项批处理通过记录：

```bash
make -f Makefile.xcelium xrun-run \
  BINARY=sw/tests/helloworld.spm.elf XRUN_RUN_INPUT=vdebug_probe.tcl
```

若新测试可能一直等待，可以在主机层设置超时，而不是依赖尚未接入的 `TIMEOUT_NS`：

```bash
timeout 300s make -f Makefile.xcelium xrun-run BINARY=sw/tests/helloworld.spm.elf
```

这里限制的是整个主机命令的运行时间，包含编译和许可证等待；首次编译较慢时应延长限制。它不等于按 DUT 仿真时间计数的 watchdog。

## 8. 常见问题与排查顺序

| 现象 | 检查与处理 |
| --- | --- |
| `bender`、GCC 或 `xrun` 找不到 | 按第 3 节恢复 PATH，检查 `command -v`；重新开终端后不要忘记加载环境 |
| `hjson`、`mako` 缺失或 `peakrdl` 找不到 | 激活 `.venv`，检查 Python >= 3.11，并重新执行依赖安装 |
| `printf.c` 缺失 | 执行 `git submodule update --init --recursive sw/deps/printf` |
| Bender E31：Flash/EEPROM 模型不存在 | 执行 `make -f Makefile.xcelium xrun-flist`，检查下载或 ZIP 解压错误；不要创建空文件或删除模型实例 |
| CVA6、HPDcache 或其他 IP 源文件缺失 | 检查 `bender checkout` 是否成功，以及是否禁用了依赖子模块；保留 `Bender.lock` |
| 生成的寄存器 RTL 缺失 | 在正确 Python 环境中重新执行 `make -j4 hw-all`，检查生成工具的首个错误 |
| `ar` / LTO 插件错误 | 检查 GCC 命令别名与 `-print-prog-name=liblto_plugin.so` 返回的文件；不要混用不同工具链的 `gcc` 和 `ar` |
| Xcelium 无法取得许可证 | 检查 EDA 环境与许可证服务器；`-licqueue` 可能使工具等待可用许可证 |
| `SVNSTP` 常量函数错误 | 确认使用当前 `hw/cheshire_soc.sv`，其中地址规则结构体已改为显式位宽 |
| 停在 `[SLINK] Wait for LLC configuration` | 检查 CPU/Boot ROM 与 AXI 返回；当前 RTL 已修复交叉开关连接矩阵位宽问题 |
| 出现 `DECERR` / `CA11AB1EBADCAB1E` | 检查地址译码和 AXI crossbar 的 `Connectivity`；该值是错误响应，不是正常寄存器数据 |
| ELF 加载后无输出或跳转异常 | 用 `readelf -l` 检查加载地址与入口，确认没有把 `.rom.elf` 当作 `.spm.elf` 预加载 |
| 回归突然混入 AXI-RT/CLIC 测试 | 使用第 6.3 节的显式 `REGRESS_ELFS`，不要依赖全部 `.spm.elf` 的默认通配结果 |
| 仓库移动后仍引用旧路径 | 在新仓库根目录重新生成文件列表；必要时保留日志后运行 `xrun-clean` 再编译 |

修复模型缺失通常不需要删除全部硬件依赖。`make clean-deps` 会移除 `.bender/`、模型和子模块检出；只有确实需要重新准备这些内容时才使用。

## 9. 进一步阅读

- [Xcelium 中文调试实录](docs/tg/xcelium_zh.md)：修复原理、ELF 加载与启动协议、六项用例的详细检查内容。
- [Getting Started](docs/gs.md)：项目结构与其他构建目标。
- [Simulation](docs/tg/sim.md)：testbench 与其他仿真器流程。
- [Targets](docs/tg/index.md)：FPGA、仿真及集成目标。
- [User Manual](docs/um/index.md)：架构、寄存器和软件栈。

## License

Unless specified otherwise in the respective file headers, all code checked into this repository is made available under a permissive license. All hardware sources and tool scripts are licensed under the Solderpad Hardware License 0.51 (see `LICENSE`) or compatible licenses. Register file code (e.g. `hw/regs/*.sv`) is generated by a fork of lowRISC's [`regtool`](https://github.com/lowRISC/opentitan/blob/master/util/regtool.py) and licensed under Apache 2.0. The USB OHCI controller (`hw/future/UsbOhciAxi4.v`) is generated from the [SpinalHDL](https://github.com/SpinalHDL/SpinalHDL) library licensed under the MIT license. All software sources are licensed under Apache 2.0.

## Publication

If you use Cheshire in your work, you can cite the platform's publication:

```
@article{ottaviano2023cheshire,
      title   = {Cheshire: A Lightweight, Linux-Capable RISC-V Host
                 Platform for Domain-Specific Accelerator Plug-In},
      author  = {Alessandro Ottaviano and Thomas Benz and
                 Paul Scheffler and Luca Benini},
      journal = {IEEE Transactions on Circuits and Systems II: Express Briefs},
      year    = {2023},
      volume  = {70},
      number  = {10},
      pages   = {3777-3781},
      doi     = {10.1109/TCSII.2023.3289186}
}
```
