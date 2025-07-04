// Use vector lsu to move data between two memory locations
#ifndef VECTOR_MEMCPY_H
#define VECTOR_MEMCPY_H

#include <stddef.h>

/**
 * @brief Vectorized memory copy using RISC-V Vector Extension (RVV)
 * 
 * This function copies `len_bytes` from `src` to `dst`, using vector
 * instructions with 32-bit element size (`e32`). Remaining bytes that do not
 * align to 4 bytes are copied with a scalar loop.
 * 
 * @param dst        Pointer to destination memory
 * @param src        Pointer to source memory
 * @param len_bytes  Number of bytes to copy
 */
void vector_memcpy32_safe(void* dst, const void* src, size_t len_bytes);

#endif // VECTOR_MEMCPY_H
