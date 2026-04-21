# Configs and kernel suffixes (without prefix)
CONFIGS="cachepool_fpu_512"
KERNELS="spin-lock load-store_M16 fdotp-32b_M32768 gemv-opt_M512_N128_K32 fmatmul-32b_M32_N32_K32 fft-32b_M1024_N16 multi_producer_single_consumer_double_linked_list_M1_N1350_K10 byte-enable"
PREFIX="test-cachepool-"  # common prefix for all kernels
ROOT_PATH=../..           # adjust if needed (path to repo root)
