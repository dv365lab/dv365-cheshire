---
name: sv-assertions-coverage
description: 在 dv365-cheshire 的 Xcelium testbench 中添加 SystemVerilog 断言（SVA）与功能覆盖率（covergroup）：写哪些接口契约、放在 target/sim/src 的哪个文件（fixture_cheshire_soc.sv / vip_cheshire_soc.sv / 新文件 + bind）、如何加入 Makefile.xcelium 的文件列表、断言失败如何体现在日志与 PASS/FAIL 判定里、covergroup 如何与 xrun-cov / imc 配合。当用户要「加断言」「检查 AXI 握手」「写 covergroup」「覆盖率怎么收」时使用。只提供写法与放置位置；是否真的通过要看许可证机器上的仿真日志。
---

# 在 Cheshire testbench 中使用断言与功能覆盖率

依据：`article.md` 第 19.2、20.7、20.8、20.10 节；`target/sim/src/fixture_cheshire_soc.sv`、`vip_cheshire_soc.sv`、`Makefile.xcelium`。

## 1. 先决定断言要描述什么

断言描述**局部时序契约**，不代替参考模型或软件自检（数据最终是否正确仍由 `sw/tests/*.c` 的逐字节比较与返回码判断）。对 AXI 五条通道（AW / W / B / AR / R）常见的契约：

| 契约 | 含义 |
| --- | --- |
| VALID 不撤销 | `VALID && !READY` 之后下一拍 `VALID` 仍为 1 |
| 载荷稳定 | 背压期间 `aw` / `w` / `ar` 结构体内容 `$stable` |
| 复位后无 VALID | `!rst_n` 期间或复位释放首拍 `*_valid == 0` |
| 响应有对应请求 | `b_valid` / `r_valid` 的 ID 必须属于未完成事务（需要记分板，复杂度高，按需） |
| 不跨 4 KiB | `aw.addr` 到页末的字节数 ≥ burst 总字节数（`article.md` 第 19.4 节） |
| 错误响应可见 | `b.resp` / `r.resp` 为 `SLVERR` / `DECERR` 时记录并可选 `$error`（`article.md` 第 19.6 节） |

## 2. 放在哪里

本仓库 testbench 可直接观察的信号在 `target/sim/src/fixture_cheshire_soc.sv`：时钟 `clk`、复位 `rst_n`，DUT 对外部 LLC / DRAM 的 AXI 主端口 `axi_llc_mst_req` / `axi_llc_mst_rsp`（类型 `axi_llc_req_t` / `axi_llc_rsp_t`，由 `CHESHIRE_TYPEDEF_ALL` 生成，字段遵循 pulp `axi/typedef.svh`：`aw_valid aw w_valid w b_ready ar_valid ar r_ready` 与 `aw_ready w_ready b_valid b ar_ready r_valid r`）。

| 方式 | 适用 | 代价 |
| --- | --- | --- |
| A. 直接写在 `fixture_cheshire_soc.sv` 的 VIP 实例之后 | 只看 fixture 层已有信号（外部 AXI 端口、UART、JTAG、Serial Link 线） | 最小：不改文件列表 |
| B. 新文件 `target/sim/src/<name>_sva.sv` 定义 checker 模块，在 fixture 里 `bind` 到 `cheshire_soc` 或依赖 IP 的实例 | 要看 DUT 内部接口（crossbar、iDMA、LLC 端口） | 需把新文件加入 `Makefile.xcelium` 的 `$(XRUN_FLIST)` 规则（`printf '%s\n' ... >> $@.tmp` 列表，放在 `fixture_cheshire_soc.sv` 之前）和 `Bender.yml` 的 `target: any(simulation, test)` 文件组，供 vsim / vcs 流程使用 |
| C. 写在 `vip_cheshire_soc.sv` 的驱动 task 里（立即断言 / `$error`） | 协议驱动侧的检查（已有 `[SLINK] - Write error response` 等先例） | 与现有风格一致 |

新 `.sv` 文件需要许可证头（`// Copyright 2026 DV365 Lab.` + Solderpad 0.51 或 Apache-2.0 三行），并遵守 Verible 风格（CI 只 lint `hw/`，但保持一致）。

## 3. 示例：外部 AXI 端口的 AW 通道稳定性（方式 A）

放在 `fixture_cheshire_soc.sv` 中 `vip_cheshire_soc ... vip (.*);` 之后、`endmodule` 之前：

```systemverilog
  //////////////////////////////////////
  //  Protocol assertions (TB only)   //
  //////////////////////////////////////

  // AW channel: once VALID is asserted without READY, VALID stays high and the
  // payload is stable until the handshake completes (article.md 19.2 / 20.7).
  property p_llc_aw_stable;
    @(posedge clk) disable iff (!rst_n)
      (axi_llc_mst_req.aw_valid && !axi_llc_mst_rsp.aw_ready)
      |=> (axi_llc_mst_req.aw_valid && $stable(axi_llc_mst_req.aw));
  endproperty
  a_llc_aw_stable: assert property (p_llc_aw_stable)
    else $error("[SVA] LLC AXI AW payload changed or VALID dropped under backpressure");

  // AR channel: same contract.
  property p_llc_ar_stable;
    @(posedge clk) disable iff (!rst_n)
      (axi_llc_mst_req.ar_valid && !axi_llc_mst_rsp.ar_ready)
      |=> (axi_llc_mst_req.ar_valid && $stable(axi_llc_mst_req.ar));
  endproperty
  a_llc_ar_stable: assert property (p_llc_ar_stable)
    else $error("[SVA] LLC AXI AR payload changed or VALID dropped under backpressure");

  // Error responses on the external memory path are never expected in the
  // six baseline tests; make them visible in the log.
  a_llc_b_okay: assert property (@(posedge clk) disable iff (!rst_n)
      (axi_llc_mst_rsp.b_valid && axi_llc_mst_req.b_ready) |-> (axi_llc_mst_rsp.b.resp == 2'b00))
    else $error("[SVA] LLC AXI write response 0x%0h", axi_llc_mst_rsp.b.resp);
```

W 通道同理（`w_valid` / `w_ready` / `w`）。信号名以实际模块连接为准；`axi_pkg::RESP_OKAY` 等常量在 `axi_pkg` 中。

## 4. 断言失败如何进入判定（重要）

- Xcelium 中并发断言失败通常以 `*E,ASRTST` 行报告，默认**不会**终止仿真；`$error` 也不会。
- `Makefile.xcelium` 的 `xrun-run` 只 grep `[PASS]` / `SUCCESS` / `exit code 0` 来打印 `PASS:`，**不看断言失败**。因此一个有断言失败但返回码为 0 的运行会被标成 PASS（`article.md` 第 20.10 节提醒的「先成功后出错」问题）。
- 处理办法（任选，写进 vPlan 的「通过判据」）：
  1. 在 action block 里用 `$fatal(1, ...)` 代替 `$error`，让失败立即结束且 `SUCCESS` 不会出现；
  2. 保留 `$error`，但在证据收集时额外执行 `rg -n '\*E,|ASRTST|\[SVA\]' target/sim/xrun/work/logs/<name>.log` 并要求为空；
  3. 需要断言统计时查阅工具自带帮助（`xrun -helpall | grep -i assert`）选择选项，通过 `XRUN_FLAGS` 传入，不改 Makefile 默认值。
- 新断言先用一个刻意违反契约的改动（或在 VIP 中注入错误响应）证明它会触发，再并入回归（与 `article.md` 第 6.6 节「失败也要能证明」同理）。

## 5. 功能覆盖率：先写问题，再写 covergroup

问题举例（`article.md` 第 20.8 节）：外部内存访问的 burst 长度与大小分布？地址对齐是否覆盖了非对齐情况？是否出现过错误响应？读写是否并发？

```systemverilog
  // Sample every accepted AW on the external LLC/DRAM port.
  covergroup cg_llc_aw @(posedge clk iff (rst_n && axi_llc_mst_req.aw_valid && axi_llc_mst_rsp.aw_ready));
    option.per_instance = 1;
    cp_len : coverpoint axi_llc_mst_req.aw.len {
      bins single   = {0};
      bins short_b  = {[1:3]};
      bins medium_b = {[4:15]};
      bins long_b   = {[16:255]};
    }
    cp_size : coverpoint axi_llc_mst_req.aw.size;
    cp_align : coverpoint axi_llc_mst_req.aw.addr[5:0] {
      bins aligned64 = {0};
      bins other     = default;
    }
    cx_len_size : cross cp_len, cp_size;
  endgroup
  cg_llc_aw i_cg_llc_aw = new();
```

- 收集：`make -f Makefile.xcelium xrun-cov BINARY=<elf>`（`-coverage all -covdut cheshire_soc -covworkdir target/sim/xrun/work/cov_work -covtest <name>`），合并与报告 `make -f Makefile.xcelium xrun-cov-report`（`imc` → `target/sim/xrun/work/cov_summary.txt`）。覆盖率流程**尚未作为基线验证**（`README.md` 第 7.2 节），首次使用先用 Hello World 走通整条链再下结论；注意 `xrun-cov` 组合了编译参数与带 `-R` 的运行参数。
- 不设数字门槛；覆盖率用于回答「哪些场景被执行过」，与检查有效性无关。
- 需要 DUT 内部信号（如 iDMA 请求长度）时用方式 B 的 `bind`，不要在 RTL 里加 TB 代码。

## 6. 提交前

- 断言 / covergroup 只在 testbench 文件中，不进入 `hw/`。
- 跑过快速层（`helloworld.spm`、`dma_1d.spm`）确认没有误报；若触发真实问题，记录日志行并按 `cheshire-verify-change` 处理。
- vPlan（`cheshire-vplan`）的第 5、6 节引用这些断言名与 covergroup 名。
