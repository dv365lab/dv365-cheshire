#!/usr/bin/env bash
# Copyright 2026 DV365 Lab.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# env_doctor.sh -- read-only health check for the dv365-cheshire simulation
# environment (see .github/skills/cheshire-env-setup/SKILL.md).
#
# It never installs, downloads or modifies anything and never triggers a Make
# rule: it only inspects PATH, tool versions, environment variables and files
# that should already exist. Run it from anywhere inside the checkout.
#
# Exit codes: 0 = no FAIL item, 1 = at least one FAIL (or WARN with --strict),
#             2 = usage error / not inside a git repository.

set -u
export LC_ALL=C

usage() {
  cat <<'EOF'
Usage: bash .github/skills/cheshire-env-setup/scripts/env_doctor.sh [OPTIONS]

Read-only health check for the Cheshire build and Xcelium simulation environment.

Options:
  --strict       treat WARN items as failures (non-zero exit code)
  --no-xcelium   this machine is build/lint only: a missing xrun/imc/licence is
                 reported as INFO instead of WARN
  -h, --help     show this help and exit

Result lines are prefixed with PASS / WARN / FAIL / INFO and a summary is
printed at the end. Exit code 0 means no FAIL item was found.
EOF
}

STRICT=0
NO_XCELIUM=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    --no-xcelium) NO_XCELIUM=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "env_doctor: unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

n_pass=0
n_warn=0
n_fail=0
n_info=0
pass() { n_pass=$((n_pass + 1)); printf 'PASS  %s\n' "$*"; }
warn() { n_warn=$((n_warn + 1)); printf 'WARN  %s\n' "$*"; }
fail() { n_fail=$((n_fail + 1)); printf 'FAIL  %s\n' "$*"; }
info() { n_info=$((n_info + 1)); printf 'INFO  %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
first_line() { "$@" 2>/dev/null | head -n 1; }

if ! ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "env_doctor: not inside a git repository -- run it from the dv365-cheshire checkout" >&2
  exit 2
fi
cd "$ROOT" || exit 2

printf 'env_doctor: %s on %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(hostname 2>/dev/null || echo unknown)"

##############
# Repository #
##############
section "Repository ($ROOT)"
if [[ -f Makefile.xcelium && -f cheshire.mk && -f Bender.yml ]]; then
  pass "Cheshire root detected, HEAD $(git rev-parse --short HEAD 2>/dev/null || echo '?')"
else
  fail "Makefile.xcelium / cheshire.mk / Bender.yml not found in $ROOT -- is this dv365-cheshire?"
fi
if [[ -f Bender.lock ]]; then
  pass "Bender.lock present"
else
  fail "Bender.lock missing (keep the lock file; it pins the IP revisions)"
fi
if [[ -f uv.lock ]]; then
  pass "uv.lock present"
else
  fail "uv.lock missing (keep the lock file; CI uses uv run --locked)"
fi
if [[ -s sw/deps/printf/printf.c ]]; then
  pass "submodule sw/deps/printf initialised"
else
  fail "sw/deps/printf/printf.c missing -> git submodule update --init --recursive sw/deps/printf"
fi
if [[ -n "$(ls -A sw/deps/cva6-sdk 2>/dev/null)" ]]; then
  info "submodule sw/deps/cva6-sdk initialised (only needed for Linux images)"
else
  info "submodule sw/deps/cva6-sdk not initialised (fine: the six baseline tests do not need it)"
fi
if git status --porcelain --ignore-submodules 2>/dev/null | grep -q .; then
  info "working tree has local changes (git status --porcelain is not empty)"
else
  pass "working tree clean"
fi

##############
# Host tools #
##############
section "Host tools"
for tool in git make gcc g++ curl tar flock; do
  if have "$tool"; then
    pass "$tool: $(command -v "$tool")"
  else
    fail "$tool not found in PATH (needed for cloning, building, DPI-C and generation rules)"
  fi
done
for tool in wget unzip; do
  if have "$tool"; then
    pass "$tool: $(command -v "$tool")"
  else
    warn "$tool not found (target/sim/models.mk needs wget + unzip to fetch the Flash/EEPROM models)"
  fi
done
if have readelf; then
  pass "readelf: $(command -v readelf)"
else
  warn "readelf not found (binutils; used to inspect ELF load addresses)"
fi
for tool in dtc sgdisk; do
  if have "$tool"; then
    info "$tool: $(command -v "$tool") (needed only by make sw-all / Linux images)"
  else
    info "$tool not found (only make sw-all / Linux images need it)"
  fi
done

###############
# Python / uv #
###############
section "Python / uv"
if have uv; then
  pass "uv: $(first_line uv --version)"
else
  info "uv not found (optional; a plain Python 3.11 venv with pip install . also works)"
fi
PY=""
if [[ -x .venv/bin/python ]]; then
  PY=".venv/bin/python"
  if [[ -n "${VIRTUAL_ENV:-}" ]]; then
    pass ".venv present and activated (VIRTUAL_ENV=$VIRTUAL_ENV)"
  else
    warn ".venv present but not activated -> source .venv/bin/activate (or use uv run --locked make ...)"
  fi
elif have python3; then
  PY="python3"
  warn "no .venv in the repo root; checking $(command -v python3) instead -> uv sync --locked --python 3.11"
elif have python; then
  PY="python"
  warn "no .venv in the repo root; checking $(command -v python) instead -> uv sync --locked --python 3.11"
else
  fail "no python interpreter found (pyproject.toml requires Python >= 3.11)"
fi
if [[ -n "$PY" ]]; then
  pyver=$("$PY" -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || true)
  if [[ -z "$pyver" ]]; then
    fail "$PY cannot report its version"
  elif "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
    pass "python $pyver (>= 3.11) via $PY"
  else
    fail "python $pyver is older than 3.11 (pyproject.toml requires >= 3.11)"
  fi
  if "$PY" -c 'import hjson, mako, yaml' 2>/dev/null; then
    pass "python modules hjson, mako, yaml importable"
  else
    fail "python modules hjson / mako / yaml missing -> uv sync --locked --python 3.11 && source .venv/bin/activate"
  fi
fi
if have peakrdl; then
  pass "peakrdl: $(first_line peakrdl --version)"
elif [[ -x .venv/bin/peakrdl ]]; then
  warn "peakrdl only found in .venv/bin (activate the venv or use uv run --locked make ...)"
else
  fail "peakrdl not found (PeakRDL generates hw/cheshire_addrmap_pkg.sv, hw/regs/*.sv and sw/include/regs/cheshire.h)"
fi

##########
# Bender #
##########
section "Bender"
if have bender; then
  bver=$(first_line bender --version)
  case "$bver" in
    *0.31.0*|*0.32.1*) pass "bender: $bver (known-good: 0.31.0 in CI, 0.32.1 in README)" ;;
    *) warn "bender: ${bver:-unknown version} (known-good versions are 0.31.0 and 0.32.1; others are untested)" ;;
  esac
else
  fail "bender not found in PATH -> see SKILL.md section 2.4"
fi
if [[ -f .bender/.chs_deps ]]; then
  pass "hardware dependencies checked out (.bender/.chs_deps present)"
else
  warn "hardware dependencies not checked out yet (.bender/.chs_deps missing) -> bender checkout (the first make also does it)"
fi
for dep in cva6 axi idma register_interface; do
  if compgen -G ".bender/git/checkouts/${dep}-*" >/dev/null; then
    pass "dependency checkout present: ${dep}"
  else
    warn "dependency checkout missing: .bender/git/checkouts/${dep}-* (use 'bender path ${dep}' after bender checkout; never hard-code the suffix)"
  fi
done

###########################
# RISC-V bare-metal tools #
###########################
section "RISC-V bare-metal toolchain (riscv64-unknown-elf-*)"
binroot="${CHS_SW_GCC_BINROOT:-}"
if [[ -n "$binroot" ]]; then
  info "CHS_SW_GCC_BINROOT=$binroot is set; sw/sw.mk looks for the tools there"
fi
rvgcc=""
rv_missing=0
for tool in gcc ar objcopy objdump; do
  t="riscv64-unknown-elf-$tool"
  if [[ -n "$binroot" && -x "$binroot/$t" ]]; then
    pass "$t: $binroot/$t"
    [[ $tool == gcc ]] && rvgcc="$binroot/$t"
  elif have "$t"; then
    pass "$t: $(command -v "$t")"
    [[ $tool == gcc ]] && rvgcc="$(command -v "$t")"
  else
    fail "$t not found (sw/sw.mk needs riscv64-unknown-elf-{gcc,ar,objcopy,objdump}; xPack users need the aliases from SKILL.md section 2.5)"
    rv_missing=1
  fi
done
if have riscv64-unknown-elf-readelf; then
  pass "riscv64-unknown-elf-readelf: $(command -v riscv64-unknown-elf-readelf)"
else
  info "riscv64-unknown-elf-readelf not found (only used for manual ELF inspection; host readelf also works)"
fi
if [[ $rv_missing -eq 0 && -n "$rvgcc" ]]; then
  pass "gcc version: $(first_line "$rvgcc" --version)"
  lto=$("$rvgcc" -print-prog-name=liblto_plugin.so 2>/dev/null || true)
  if [[ -n "$lto" && -f "$lto" ]]; then
    pass "LTO plugin: $lto"
  else
    fail "LTO plugin not found via -print-prog-name=liblto_plugin.so (got '${lto:-}'); sw/sw.mk passes it to ar --plugin -- do not mix toolchains, or set CHS_SW_LTOPLUG"
  fi
  if "$rvgcc" -march=rv64gc_zifencei -mabi=lp64d -E -x c /dev/null >/dev/null 2>&1; then
    pass "gcc accepts -march=rv64gc_zifencei -mabi=lp64d (CHS_SW_FLAGS)"
  else
    warn "gcc rejected -march=rv64gc_zifencei -mabi=lp64d (used by CHS_SW_FLAGS in sw/sw.mk); the toolchain is probably too old"
  fi
fi

###################
# Cadence Xcelium #
###################
section "Cadence Xcelium"
for var in CDS_INST_DIR XCELIUMHOME XCELIUM_HOME; do
  if [[ -n "${!var:-}" ]]; then
    info "$var=${!var}"
  fi
done
if have xrun; then
  pass "xrun: $(command -v xrun)"
  # Run -version outside the repo: Cadence tools may drop xrun.log/xrun.history in the cwd.
  xv=$(cd "${TMPDIR:-/tmp}" 2>/dev/null && xrun -version 2>/dev/null | head -n 1)
  if [[ -n "$xv" ]]; then
    pass "xrun -version: $xv (README-verified release: 26.03-a071)"
  else
    warn "xrun found but 'xrun -version' printed nothing (EDA environment script not loaded?)"
  fi
  if have imc; then
    pass "imc: $(command -v imc)"
  else
    warn "imc not found (needed only for make -f Makefile.xcelium xrun-cov-report)"
  fi
  if [[ -n "${CDS_LIC_FILE:-}" || -n "${LM_LICENSE_FILE:-}" ]]; then
    pass "licence variable set (CDS_LIC_FILE='${CDS_LIC_FILE:-}' LM_LICENSE_FILE='${LM_LICENSE_FILE:-}')"
  else
    warn "neither CDS_LIC_FILE nor LM_LICENSE_FILE is set; xrun will queue (-licqueue) or fail when compiling"
  fi
  info "xrun -version only proves the binary starts; a licence is consumed at compile/run time"
else
  if [[ $NO_XCELIUM -eq 1 ]]; then
    info "xrun not found and --no-xcelium given: this machine can build and lint but cannot simulate"
  else
    warn "xrun not found: simulation is NOT possible here (build/lint only); load the EDA environment or pass --no-xcelium"
  fi
fi

########################
# Simulation artefacts #
########################
section "Simulation artefacts (informational; produced by make targets)"
if [[ -f target/sim/src/run.xcelium.tcl ]]; then
  pass "default run script target/sim/src/run.xcelium.tcl present"
else
  fail "target/sim/src/run.xcelium.tcl missing (default XRUN_RUN_INPUT of Makefile.xcelium)"
fi
if [[ -f vdebug_probe.tcl ]]; then
  pass "Verisium probe script vdebug_probe.tcl present"
else
  warn "vdebug_probe.tcl missing (optional waveform entry: XRUN_RUN_INPUT=vdebug_probe.tcl)"
fi
for m in target/sim/models/s25fs512s.v target/sim/models/24FC1025.v; do
  if [[ -s "$m" ]]; then
    pass "model present: $m"
  elif [[ -e "$m" ]]; then
    fail "model exists but is EMPTY: $m (never create empty model files; rerun make -f Makefile.xcelium xrun-flist)"
  else
    info "model not downloaded yet: $m (make -f Makefile.xcelium xrun-flist fetches it)"
  fi
done
if [[ -s target/sim/xrun/cheshire_soc.f ]]; then
  if grep -q -- "$ROOT/" target/sim/xrun/cheshire_soc.f; then
    pass "file list present and refers to this checkout: target/sim/xrun/cheshire_soc.f"
  else
    warn "file list present but does not mention $ROOT/ (repository moved?) -> regenerate with make -f Makefile.xcelium xrun-flist"
  fi
else
  info "file list not generated yet: target/sim/xrun/cheshire_soc.f (make -f Makefile.xcelium xrun-flist)"
fi
if [[ -d target/sim/xrun/work/xcelium.d ]]; then
  info "Xcelium work library exists: target/sim/xrun/work/xcelium.d (snapshot may be stale after RTL changes)"
else
  info "no Xcelium work library yet (make -f Makefile.xcelium xrun-all)"
fi
if [[ -f sw/tests/helloworld.spm.elf ]]; then
  info "sw/tests/helloworld.spm.elf exists (rebuild after source changes)"
else
  info "sw/tests/helloworld.spm.elf not built yet (make -j4 \"\$PWD/sw/tests/helloworld.spm.elf\")"
fi

###########
# Summary #
###########
section "Summary"
printf 'PASS=%d WARN=%d FAIL=%d INFO=%d\n' "$n_pass" "$n_warn" "$n_fail" "$n_info"
if [[ $n_fail -gt 0 ]]; then
  echo "RESULT: FAIL -- fix the FAIL items above before building (see .github/skills/cheshire-env-setup/SKILL.md)"
  exit 1
fi
if [[ $STRICT -eq 1 && $n_warn -gt 0 ]]; then
  echo "RESULT: FAIL (--strict) -- WARN items present"
  exit 1
fi
if have xrun; then
  echo "RESULT: OK -- build and simulation prerequisites look complete"
else
  echo "RESULT: OK (build/lint only) -- xrun not available; simulation must run on a licensed machine"
fi
exit 0
