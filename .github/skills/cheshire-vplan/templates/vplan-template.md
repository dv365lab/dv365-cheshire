# 验证计划：《特性名称》

> 使用说明：复制本模板到 `docs/vplan/<feature>.md`，按 `.github/skills/cheshire-vplan/SKILL.md` 的流程逐节填写，删除所有《》占位与本段说明。Markdown 不加许可证头；正文中文，标识符 / 命令 / 路径英文。

## 0. 元数据

| 项 | 值 |
| --- | --- |
| 特性 / 数据通路 | 《例如：一维 DMA 边界场景》 |
| 版本 / 日期 | 《v0.1 / YYYY-MM-DD》 |
| 作者 | 《姓名或团队》 |
| 基线提交 | 《`git rev-parse --short HEAD`》 |
| 硬件配置 | 《`DefaultCfg`（`SelectedCfg=0`）或说明如何切换》 |
| 工具组合 | 《Bender / Python / RISC-V GCC / Xcelium 版本；CI 组合或 README 组合》 |
| 状态 | 《草稿 / 评审中 / 已执行（引用日志）》 |
| 执行环境 | 《哪些步骤只能在有 Xcelium 许可证的机器上完成》 |

## 1. 目标与范围

《一两段：要证明什么、不证明什么；与六项基础回归的关系（`docs/vplan/baseline-regression.md`）。》

## 2. 特性清单

| ID | 特性 | 来源（文件:行 / 章节） | 数据通路 | 优先级 |
| --- | --- | --- | --- | --- |
| F-01 | 《…》 | 《`hw/cheshire_pkg.sv:…`》 | 《取指 / 数据 / DMA / 远端 / 外设 / 中断 / 启动》 | 《高 / 中 / 低》 |

## 3. 激励策略

### 3.1 定向场景

| 场景 | 初始状态 | 触发操作 | 独立预期结果 | 完成条件 | 失败条件 |
| --- | --- | --- | --- | --- | --- |
| 《S-01》 | 《…》 | 《…》 | 《来自源数据与地址公式》 | 《…》 | 《内容不一致 / 保护区变化 / 超时》 |

### 3.2 随机化（如适用）

《随机的维度与顺序（长度 → 地址低位 → 区域 → 背压 → 并发）、参考模型、种子如何保存与复现（`SEED=` 只影响 SV 随机；软件侧种子如何打印）。》

### 3.3 参数与配置

《涉及的宏 / 模块参数 / plusarg 各是什么、在哪里被读取；若需要非默认 `SelectedCfg`，写明如何真正切换并重新展开。》

## 4. 检查器与 scoreboard

| 检查对象 | 机制 | 位置 | 现有 / 新增 |
| --- | --- | --- | --- |
| 《数据内容》 | 《软件逐字节比较，返回不一致字节数》 | 《`sw/tests/<name>.c`》 | 《现有》 |
| 《结束与返回码》 | 《`scratch[2]` 协议，VIP `*_wait_for_eoc`》 | 《`sw/lib/crt0.S`、`target/sim/src/vip_cheshire_soc.sv`》 | 现有 |

## 5. 接口断言（SVA）

| 接口 | 断言内容 | 放置位置 | 状态 |
| --- | --- | --- | --- |
| 《AXI AW 通道》 | 《背压期间 VALID 不撤销、载荷稳定》 | 《`target/sim/src/fixture_cheshire_soc.sv` 或 bind 文件》 | 《待写》 |

## 6. 覆盖率要回答的问题

| 问题 | 覆盖点 / 分箱 | 收集方式 | 备注 |
| --- | --- | --- | --- |
| 《哪些长度区间被搬运过》 | 《1、2–7、8、9–63、64、>64、跨 4 KiB》 | 《covergroup / 日志统计》 | 《`xrun-cov` 流程需先验证可用》 |

## 7. 测试列表

| ID | 特性 | ELF | TB 配置 | 参数 | 预期证据 | 日志 | 状态 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| T-01 | F-01 | `sw/tests/<name>.spm.elf` | `SelectedCfg=0` | `BOOTMODE=0 PRELMODE=1 SEED=1` | 《`Entrypoint at 0x10000000`、`[SLINK] SUCCESS`、`PASS: <name>.spm`》 | `target/sim/xrun/work/logs/<name>.spm.log` | 《已有 / 待写 / 待验证》 |

回归命令：

```bash
make -f Makefile.xcelium xrun-regress BOOTMODE=0 PRELMODE=1 SEED=1 \
  REGRESS_ELFS="sw/tests/<a>.spm.elf sw/tests/<b>.spm.elf"
```

## 8. 通过判据与证据

1. 加载：《`[ELF] INFO: Entrypoint at ...`、`Preloading section at ...`》
2. 行为：《UART 文本 / 数据比较 / 寄存器值》
3. 结束：《`[SLINK] SUCCESS`、`PASS: <name>`、`make` 退出码 0》

证据清单：提交号、工具版本、配置、命令、种子、日志路径、`rg -n 'PASS:|FAIL:|FAILED|SUCCESS|Entrypoint' <log>` 输出。
负向实验：《哪个测试临时 `return 7;`，预期 `FAIL:` 与非零退出码》。
超时：《`timeout 300s make ...` 或新增 watchdog 的验证方式》。

## 9. 风险与未覆盖项

| 项 | 为什么没覆盖 | 若要覆盖需要什么 |
| --- | --- | --- |
| 《AXI-RT / CLIC 配置》 | 《`SELCFG` 宏未接到 `SelectedCfg`》 | 《接通参数并重新展开》 |
| 《外部内存时序》 | 《`axi_sim_mem` 是功能模型》 | 《DRAMSys 接入》 |

## 10. 参考

- 《`article.md` 章节、`README.md` 节、`docs/tg/xcelium_zh.md` 节、源码路径》
