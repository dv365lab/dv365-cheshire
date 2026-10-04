# Copyright 2026 DV365 Lab.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

ida_database -open -name=./ida.db
ida_probe -log -wave \
    -wave_probe_args="[scope -tops] -all -depth all -memories -dynamic" \
    -tb_dut_access -wave_glitch_recording
#ida_probe -wave -wave_probe_args="$uvm:{uvm_test_top} -all -depth all"
run
exit
