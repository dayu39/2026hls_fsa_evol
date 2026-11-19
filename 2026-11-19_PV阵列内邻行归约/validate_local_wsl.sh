#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"
vitis_include="${VITIS_INCLUDE:-/mnt/d/01_Software/xilinx/Vitis/2024.2/include}"
test -f "$vitis_include/ap_int.h"
mkdir -p build/local_split_d_check
g++ -std=c++14 -O0 -Wall -Wextra -Wno-unknown-pragmas -Wno-unused-parameter \
  -Iinclude -isystem "$vitis_include" -pthread \
  -DFSA_LOCAL_MATH_STUBS -DHLS_NO_XIL_FPO_LIB \
  -DFSA_SPLIT_D_PE_DIM=16 -DFSA_SPLIT_D_HEAD_DIM=128 \
  src/stream/split_d/split_d_dma.cpp \
  src/stream/split_d/split_d_compute.cpp \
  src/stream/split_d/split_d_controller.cpp \
  src/stream/split_d/fsa_stream_split_d.cpp \
  src/stream/arithmetic.cpp src/stream/local_math_stubs.cpp \
  src/stream/dma.cpp src/stream/accumulator.cpp \
  src/stream/pe_raw_fma.cpp src/stream/fp32_raw_fma.cpp \
  tests/stream/test_fsa_stream_split_d.cpp \
  -o build/local_split_d_check/split_d_check_16x128
build/local_split_d_check/split_d_check_16x128