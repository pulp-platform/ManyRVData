# Configs and kernel suffixes (without prefix)

CONFIGS="cachepool_fpu_2g cachepool_fpu_4g"

KERNELS="spin-lock fdotp-32b_M65536 gemv-opt_M1024_N128_K32 gemv_M1024_N128_K32 fmatmul-32b_M64_N64_K64 multi_producer_single_consumer_double_linked_list_M1_N1350_K100 byte-enable"

PREFIX="test-cachepool-"  # common prefix for all kernels
ROOT_PATH=../..           # adjust if needed (path to repo root)
