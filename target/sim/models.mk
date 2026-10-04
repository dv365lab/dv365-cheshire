# Copyright 2022 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Shared external simulation models for the standard and standalone simulator flows.
ifndef CHS_SIM_MODELS_INCLUDED
CHS_SIM_MODELS_INCLUDED := 1

.PRECIOUS: $(CHS_ROOT)/target/sim/models
$(CHS_ROOT)/target/sim/models:
	mkdir -p $@

# Download (partially non-free) simulation models from publicly available sources;
# running these targets accepts their terms (see docs/gs.md).
# Stage downloads so a failed transfer cannot leave an incomplete model target.
$(CHS_ROOT)/target/sim/models/s25fs512s.v: $(CHS_ROOT)/Bender.yml | $(CHS_ROOT)/target/sim/models
	set -e; \
	  trap 'rm -f "$@.tmp"' EXIT; \
	  wget --no-check-certificate --timeout=30 --tries=2 \
	    https://freemodelfoundry.com/fmf_vlog_models/flash/s25fs512s.v -O "$@.tmp"; \
	  test -s "$@.tmp"; \
	  touch "$@.tmp"; \
	  mv "$@.tmp" "$@"

$(CHS_ROOT)/target/sim/models/24FC1025.v: $(CHS_ROOT)/Bender.yml | $(CHS_ROOT)/target/sim/models
	set -e; \
	  trap 'rm -f "$@.zip.tmp" "$@.tmp"' EXIT; \
	  wget --timeout=30 --tries=2 \
	    https://ww1.microchip.com/downloads/en/DeviceDoc/24xx1025_Verilog_Model.zip \
	    -O "$@.zip.tmp"; \
	  unzip -p "$@.zip.tmp" 24FC1025.v > "$@.tmp"; \
	  test -s "$@.tmp"; \
	  mv "$@.tmp" "$@"

CHS_SIM_MODELS_ALL += $(CHS_ROOT)/target/sim/models/s25fs512s.v
CHS_SIM_MODELS_ALL += $(CHS_ROOT)/target/sim/models/24FC1025.v

endif
