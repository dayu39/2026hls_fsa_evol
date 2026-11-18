#!/usr/bin/env bash
# Run only inside this isolated candidate directory on the Vitis HLS 2024.2 host.
set -eo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"
if [[ -d hls/fsa_stream_split_d/build || -d hls/fsa_stream_split_d/fsa_stream_split_d_build ]]; then
    echo 'Existing HLS build found; preserve it before starting a new run.' >&2
    exit 2
fi
source /opt/Xilinx_2024.2/Vitis/2024.2/settings64.sh
set -u
export RUN_CSIM=1 RUN_COSIM=0 EXPORT_IP=0
export FSA_SPLIT_D_PE_DIM=16 FSA_SPLIT_D_HEAD_DIM=128 FSA_SPLIT_D_LONG_CSIM_TEST=0
mkdir -p logs
printf 'BASE_COMMIT=%s\nSTART=%s\n' "$(cat BASE_COMMIT.txt)" "$(date --iso-8601=seconds)" | tee logs/validation.log
timeout -s TERM -k 30s 150m ./run_hls.sh fsa_stream_split_d 2>&1 | tee -a logs/validation.log
printf 'END=%s\n' "$(date --iso-8601=seconds)" | tee -a logs/validation.log