# Configs and kernel suffixes (without prefix)
# CONFIGS="cachepool_fpu_512"
# KERNELS="spin-lock fdotp-32b_M32768"
CONFIGS="cachepool_fpu_128 cachepool_fpu_256 cachepool_fpu_512"
KERNELS="spin-lock fdotp-32b_M32768 gemv-col_M256_N128_K32 fmatmul-32b_M32_N32_K32 fmatmul-32b_M64_N64_K64"
PREFIX="test-cachepool-"  # common prefix for all kernels
ROOT_PATH=../..           # adjust if needed (path to repo root)
