// Use vector lsu to move data between two memory locations
#include <stddef.h>
#include <stdint.h>
#include "printf.h"
#include "printf_lock.h"

void __attribute__((noinline)) vector_memcpy32_safe(void* dst, const void* src, size_t len_bytes) {
  uint32_t* d32 = (uint32_t*)dst;
  const uint32_t* s32 = (const uint32_t*)src;

  const size_t word_size = sizeof(uint32_t);
  const size_t VL_MAX = 64;
  size_t word_count = len_bytes / word_size;
  size_t copied = 0;

  // 1. Vectorized copy of word-aligned chunks
  while (copied < word_count) {
    size_t vl, avl = word_count - copied;

    if (avl >= VL_MAX) {
      avl = VL_MAX;
    } else {
      avl = avl & ~((size_t)3);  // round down to multiple of 4
      if (avl == 0) {
        break;  // fallback to scalar if too small
      }
    }

    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(avl));

    printf_lock_acquire(&printf_lock);
    printf("[vector_memcpy32_safe] vl = %d, avl = %d, copied = %d, word_count = %d\n", 
          vl, avl, copied, word_count);
    printf_lock_release(&printf_lock);


    asm volatile("vle32.v v0, (%0)" :: "r"(s32 + copied));
    asm volatile("vse32.v v0, (%0)" :: "r"(d32 + copied));

    copied += vl;
  }

  // // 2. Scalar copy of remaining bytes
  // uint8_t* d8 = ((uint8_t*)d32) + (copied * word_size);
  // const uint8_t* s8 = ((const uint8_t*)s32) + (copied * word_size);
  // size_t tail = len_bytes - word_count * word_size;

  // for (size_t i = 0; i < tail; i++) {
  //   d8[i] = s8[i];
  // }
}
