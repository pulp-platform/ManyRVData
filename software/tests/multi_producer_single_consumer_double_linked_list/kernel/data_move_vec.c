#include <stddef.h>
#include <stdint.h>
#include "printf.h"
#include "printf_lock.h"


void __attribute__((noinline)) scalar_memcpy32_8bit(void* dst, const void* src, size_t len_bytes) {
    uint8_t*  d = (uint8_t*)dst;
    const uint8_t* s = (const uint8_t*)src;
    for (size_t i = 0; i < len_bytes; ++i) {
        d[i] = s[i];
    }
}

void __attribute__((noinline)) scalar_memcpy32_32bit(void* dst, const void* src, size_t len_bytes) {
    uint32_t*      d32   = (uint32_t*)dst;
    const uint32_t* s32   = (const uint32_t*)src;
    size_t         word_size = sizeof(uint32_t);
    size_t         n_words   = len_bytes / word_size;
    size_t         i;

    // 1) Copy full 32-bit words
    for (i = 0; i < n_words; ++i) {
        d32[i] = s32[i];
    }

    // 2) Copy remaining bytes
    uint8_t*      d8 = (uint8_t*)(d32 + n_words);
    const uint8_t* s8 = (const uint8_t*)(s32 + n_words);
    size_t         tail = len_bytes - n_words * word_size;

    for (i = 0; i < tail; ++i) {
        d8[i] = s8[i];
    }
}


void scalar_memcpy32_32bit_unrolled(void* dst, const void* src, size_t len_bytes) {
    uint32_t*       d32      = (uint32_t*)dst;
    const uint32_t* s32      = (const uint32_t*)src;
    const size_t    word_size= sizeof(uint32_t);

    size_t n_words = len_bytes / word_size;
    size_t blocks  = n_words / 4;    // how many 4-word groups
    size_t rem_w   = n_words % 4;    // leftover words
    size_t i;

    // 1) copy blocks of 4 words
    while (blocks--) {
        d32[0] = s32[0];
        d32[1] = s32[1];
        d32[2] = s32[2];
        d32[3] = s32[3];
        d32 += 4;
        s32 += 4;
    }

    // 2) copy remaining 1–3 words
    for (i = 0; i < rem_w; ++i) {
        d32[i] = s32[i];
    }
    d32 += rem_w;
    s32 += rem_w;

    // 3) copy final 0–3 bytes
    {
        uint8_t*       d8    = (uint8_t*)d32;
        const uint8_t* s8    = (const uint8_t*)s32;
        size_t         tail  = len_bytes - n_words * word_size;
        for (i = 0; i < tail; ++i) {
            d8[i] = s8[i];
        }
    }
}




void __attribute__((noinline)) vector_memcpy32_m4_opt(void* dst,
                                                     const void* src,
                                                     size_t len_bytes) {
  uint32_t* d32 = (uint32_t*)dst;
  const uint32_t* s32 = (const uint32_t*)src;

  const size_t word_size       = sizeof(uint32_t);   
  const size_t VLEN_BITS       = 512;
  const size_t M               = 4;
  const size_t elems_per_vreg  = (VLEN_BITS * M) / (8 * word_size); // 2048/32 = 64
  const size_t big_regs        = 8;                                // v0,4,…,28
  const size_t big_chunk_words = elems_per_vreg * big_regs;        // 64*8 = 512 words
  size_t vl, avl;

  size_t word_count = len_bytes / word_size;
  size_t copied     = 0;

  // 1. Big unrolled chunks
  while (word_count - copied >= big_chunk_words) {
    avl = big_chunk_words;
    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(avl));

    // printf_lock_acquire(&printf_lock);
    // printf("[core %u][vector_memcpy32_m4_opt vec_big] vl = %d, avl = %d, copied = %d, word_count = %d, copied_byte_count = %d/%d\n", 
    //     snrt_cluster_core_idx(),
    //     vl, avl, copied, word_count, copied * word_size, len_bytes);
    // printf_lock_release(&printf_lock);

    // pipeline 8 loads
    asm volatile("vle32.v v0,  (%0)" :: "r"(s32 + copied + 0*elems_per_vreg));
    asm volatile("vle32.v v4,  (%0)" :: "r"(s32 + copied + 1*elems_per_vreg));
    asm volatile("vle32.v v8,  (%0)" :: "r"(s32 + copied + 2*elems_per_vreg));
    asm volatile("vle32.v v12, (%0)" :: "r"(s32 + copied + 3*elems_per_vreg));
    asm volatile("vle32.v v16, (%0)" :: "r"(s32 + copied + 4*elems_per_vreg));
    asm volatile("vle32.v v20, (%0)" :: "r"(s32 + copied + 5*elems_per_vreg));
    asm volatile("vle32.v v24, (%0)" :: "r"(s32 + copied + 6*elems_per_vreg));
    asm volatile("vle32.v v28, (%0)" :: "r"(s32 + copied + 7*elems_per_vreg));

    // pipeline 8 stores
    asm volatile("vse32.v v0,  (%0)" :: "r"(d32 + copied + 0*elems_per_vreg));
    asm volatile("vse32.v v4,  (%0)" :: "r"(d32 + copied + 1*elems_per_vreg));
    asm volatile("vse32.v v8,  (%0)" :: "r"(d32 + copied + 2*elems_per_vreg));
    asm volatile("vse32.v v12, (%0)" :: "r"(d32 + copied + 3*elems_per_vreg));
    asm volatile("vse32.v v16, (%0)" :: "r"(d32 + copied + 4*elems_per_vreg));
    asm volatile("vse32.v v20, (%0)" :: "r"(d32 + copied + 5*elems_per_vreg));
    asm volatile("vse32.v v24, (%0)" :: "r"(d32 + copied + 6*elems_per_vreg));
    asm volatile("vse32.v v28, (%0)" :: "r"(d32 + copied + 7*elems_per_vreg));

    copied += big_chunk_words;
  }

  // 2. Medium smaller vector chunks (up to VL, rounded to multiple of 4)
  while (word_count - copied >= 4) {
    size_t rem      = word_count - copied;
    avl      = rem > elems_per_vreg ? elems_per_vreg : (rem & ~((size_t)3));
    if (!avl) break;

    asm volatile("vsetvli %0, %1, e32, m4, ta, ma" : "=r"(vl) : "r"(avl));

    // printf_lock_acquire(&printf_lock);
    // printf("[core %u][vector_memcpy32_m4_opt vec_med] vl = %d, avl = %d, copied = %d, word_count = %d, copied_byte_count = %d/%d\n", 
    //     snrt_cluster_core_idx(),
    //     vl, avl, copied, word_count, copied * word_size, len_bytes);
    // printf_lock_release(&printf_lock);

    asm volatile("vle32.v v0, (%0)" :: "r"(s32 + copied));
    asm volatile("vse32.v v0, (%0)" :: "r"(d32 + copied));

    copied += avl;
  }

  // 3. Scalar tail for final <4 words and <word_size bytes
//   printf_lock_acquire(&printf_lock);
//   printf("[core %u][vector_memcpy32_m4_opt sca_32b] copied_byte_count = %d/%d\n", 
//         snrt_cluster_core_idx(),
//         copied * word_size, len_bytes);
//   printf_lock_release(&printf_lock);

  for (; copied < word_count; ++copied) {
    d32[copied] = s32[copied];
  }
  // byte‐wise remainder
  uint8_t* d8 = (uint8_t*)(d32 + copied);
  const uint8_t* s8 = (const uint8_t*)(s32 + copied);
  size_t tail = len_bytes - word_count * word_size;

//   printf_lock_acquire(&printf_lock);
//   printf("[core %u][vector_memcpy32_m4_opt sca_8b] tail = %d, copied_byte_count = %d/%d\n", 
//         snrt_cluster_core_idx(),
//         tail, copied * word_size, len_bytes);
//   printf_lock_release(&printf_lock);

  for (size_t i = 0; i < tail; ++i) {
    d8[i] = s8[i];
  }
}



void __attribute__((noinline)) vector_memcpy32_m8_opt(void* dst,
                                                     const void* src,
                                                     size_t len_bytes) {
  uint32_t* d32 = (uint32_t*)dst;
  const uint32_t* s32 = (const uint32_t*)src;

  const size_t word_size       = sizeof(uint32_t);
  const size_t VLEN_BITS       = 512;
  const size_t M               = 8;
  const size_t elems_per_vreg  = (VLEN_BITS * M) / (8 * word_size); // 4096/32 = 128
  const size_t big_regs        = 4;                                 // v0,8,16,24
  const size_t big_chunk_words = elems_per_vreg * big_regs;         // 128*4 = 512 words
  size_t vl, avl;

  size_t word_count = len_bytes / word_size;
  size_t copied     = 0;

  // 1. Big unrolled chunks
  while (word_count - copied >= big_chunk_words) {
    avl = big_chunk_words;
    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));

    asm volatile("vle32.v v0,  (%0)" :: "r"(s32 + copied + 0*elems_per_vreg));
    asm volatile("vle32.v v8,  (%0)" :: "r"(s32 + copied + 1*elems_per_vreg));
    asm volatile("vle32.v v16, (%0)" :: "r"(s32 + copied + 2*elems_per_vreg));
    asm volatile("vle32.v v24, (%0)" :: "r"(s32 + copied + 3*elems_per_vreg));

    asm volatile("vse32.v v0,  (%0)" :: "r"(d32 + copied + 0*elems_per_vreg));
    asm volatile("vse32.v v8,  (%0)" :: "r"(d32 + copied + 1*elems_per_vreg));
    asm volatile("vse32.v v16, (%0)" :: "r"(d32 + copied + 2*elems_per_vreg));
    asm volatile("vse32.v v24, (%0)" :: "r"(d32 + copied + 3*elems_per_vreg));

    copied += big_chunk_words;
  }

  // 2. Medium smaller vector chunks
  while (word_count - copied >= 4) {
    size_t rem      = word_count - copied;
    avl      = rem > elems_per_vreg ? elems_per_vreg : (rem & ~((size_t)3));
    if (!avl) break;

    asm volatile("vsetvli %0, %1, e32, m8, ta, ma" : "=r"(vl) : "r"(avl));
    asm volatile("vle32.v v0, (%0)" :: "r"(s32 + copied));
    asm volatile("vse32.v v0, (%0)" :: "r"(d32 + copied));

    copied += avl;
  }

  // 3. Scalar tail
  for (; copied < word_count; ++copied) {
    d32[copied] = s32[copied];
  }
  uint8_t* d8 = (uint8_t*)(d32 + copied);
  const uint8_t* s8 = (const uint8_t*)(s32 + copied);
  size_t tail = len_bytes - word_count * word_size;
  for (size_t i = 0; i < tail; ++i) {
    d8[i] = s8[i];
  }
}



void __attribute__((noinline))
vector_memcpy32_m4_general_opt (void*       dst,
                                const void* src,
                                size_t      len_bytes)
{
    uint32_t*       d32            = (uint32_t*)dst;
    const uint32_t* s32            = (const uint32_t*)src;
    const size_t    word_size      = sizeof(uint32_t);
    const size_t    VLEN_BITS      = 512;
    const size_t    M              = 4;      // m4 grouping
    const size_t    elems_per_vreg = (VLEN_BITS * M) / (8 * word_size); // = 64 words
    const size_t    max_groups     = 32 / M;  // 8 register groups (v0…v28)

    size_t word_count = len_bytes / word_size;
    size_t copied     = 0;
    size_t vl;    // will hold the actual VL returned by vsetvli

    // 1) Big‐chunk unroll
    size_t big_chunks = word_count / elems_per_vreg;
    if (big_chunks > max_groups) big_chunks = max_groups;
    size_t big_chunk_w = big_chunks * elems_per_vreg;

    if (big_chunk_w) {
      while (word_count - copied >= big_chunk_w) {
        // configure VL = big_chunk_w (multiple of elems_per_vreg, hence of 4)
        asm volatile("vsetvli %0, %1, e32, m4, ta, ma"
                     : "=r"(vl) : "r"(big_chunk_w));

        // pipeline loads into v0, v4, … v((big_chunks-1)*4)
        if (big_chunks > 0)  asm volatile("vle32.v v0,  (%0)" :: "r"(s32 + copied + 0*elems_per_vreg));
        if (big_chunks > 1)  asm volatile("vle32.v v4,  (%0)" :: "r"(s32 + copied + 1*elems_per_vreg));
        if (big_chunks > 2)  asm volatile("vle32.v v8,  (%0)" :: "r"(s32 + copied + 2*elems_per_vreg));
        if (big_chunks > 3)  asm volatile("vle32.v v12, (%0)" :: "r"(s32 + copied + 3*elems_per_vreg));
        if (big_chunks > 4)  asm volatile("vle32.v v16, (%0)" :: "r"(s32 + copied + 4*elems_per_vreg));
        if (big_chunks > 5)  asm volatile("vle32.v v20, (%0)" :: "r"(s32 + copied + 5*elems_per_vreg));
        if (big_chunks > 6)  asm volatile("vle32.v v24, (%0)" :: "r"(s32 + copied + 6*elems_per_vreg));
        if (big_chunks > 7)  asm volatile("vle32.v v28, (%0)" :: "r"(s32 + copied + 7*elems_per_vreg));

        // pipeline stores from those same registers
        if (big_chunks > 0)  asm volatile("vse32.v v0,  (%0)" :: "r"(d32 + copied + 0*elems_per_vreg));
        if (big_chunks > 1)  asm volatile("vse32.v v4,  (%0)" :: "r"(d32 + copied + 1*elems_per_vreg));
        if (big_chunks > 2)  asm volatile("vse32.v v8,  (%0)" :: "r"(d32 + copied + 2*elems_per_vreg));
        if (big_chunks > 3)  asm volatile("vse32.v v12, (%0)" :: "r"(d32 + copied + 3*elems_per_vreg));
        if (big_chunks > 4)  asm volatile("vse32.v v16, (%0)" :: "r"(d32 + copied + 4*elems_per_vreg));
        if (big_chunks > 5)  asm volatile("vse32.v v20, (%0)" :: "r"(d32 + copied + 5*elems_per_vreg));
        if (big_chunks > 6)  asm volatile("vse32.v v24, (%0)" :: "r"(d32 + copied + 6*elems_per_vreg));
        if (big_chunks > 7)  asm volatile("vse32.v v28, (%0)" :: "r"(d32 + copied + 7*elems_per_vreg));

        copied += big_chunk_w;
      }
    }

    // 2) Medium chunks ≥4 words
    while (word_count - copied >= 4) {
      size_t rem = word_count - copied;
      // round down to multiple of 4, up to elems_per_vreg
      size_t avl = rem > elems_per_vreg ? elems_per_vreg
                                        : (rem & ~((size_t)3));
      if (!avl) break;

      asm volatile("vsetvli %0, %1, e32, m4, ta, ma"
                   : "=r"(vl) : "r"(avl));
      asm volatile("vle32.v v0, (%0)" :: "r"(s32 + copied));
      asm volatile("vse32.v v0, (%0)" :: "r"(d32 + copied));
      copied += avl;
    }

    // 3) Inline‐asm unrolled word‐tail (0–3 words)
    {
      size_t word_tail = word_count - copied;
      switch (word_tail) {
        case 3:
          asm volatile(
            "lw t0,  0(%[s])\n"
            "lw t1,  4(%[s])\n"
            "lw t2,  8(%[s])\n"
            "sw t0,  0(%[d])\n"
            "sw t1,  4(%[d])\n"
            "sw t2,  8(%[d])\n"
            :
            : [s]"r"(s32 + copied), [d]"r"(d32 + copied)
            : "t0","t1","t2","memory"
          );
          copied += 3;
          break;
        case 2:
          asm volatile(
            "lw t0, 0(%[s])\n"
            "lw t1, 4(%[s])\n"
            "sw t0, 0(%[d])\n"
            "sw t1, 4(%[d])\n"
            :
            : [s]"r"(s32 + copied), [d]"r"(d32 + copied)
            : "t0","t1","memory"
          );
          copied += 2;
          break;
        case 1:
          asm volatile(
            "lw t0, 0(%[s])\n"
            "sw t0, 0(%[d])\n"
            :
            : [s]"r"(s32 + copied), [d]"r"(d32 + copied)
            : "t0","memory"
          );
          copied += 1;
          break;
        default:
          break;
      }
    }

    // 4) Inline‐asm unrolled byte‐tail (0–3 bytes)
    {
      uint8_t*       d8        = (uint8_t*)(d32 + copied);
      const uint8_t* s8        = (const uint8_t*)(s32 + copied);
      size_t         byte_tail = len_bytes - word_count * word_size;
      switch (byte_tail) {
        case 3:
          asm volatile(
            "lb t0, 0(%[s])\n"
            "lb t1, 1(%[s])\n"
            "lb t2, 2(%[s])\n"
            "sb t0, 0(%[d])\n"
            "sb t1, 1(%[d])\n"
            "sb t2, 2(%[d])\n"
            :
            : [s]"r"(s8), [d]"r"(d8)
            : "t0","t1","t2","memory"
          );
          break;
        case 2:
          asm volatile(
            "lb t0, 0(%[s])\n"
            "lb t1, 1(%[s])\n"
            "sb t0, 0(%[d])\n"
            "sb t1, 1(%[d])\n"
            :
            : [s]"r"(s8), [d]"r"(d8)
            : "t0","t1","memory"
          );
          break;
        case 1:
          asm volatile(
            "lb t0, 0(%[s])\n"
            "sb t0, 0(%[d])\n"
            :
            : [s]"r"(s8), [d]"r"(d8)
            : "t0","memory"
          );
          break;
        default:
          break;
      }
    }
}




void __attribute__((noinline))
vector_memcpy32_m8_m4_general_opt(void*       dst,
                                const void* src,
                                size_t      len_bytes)
{
    uint32_t*       d32            = (uint32_t*)dst;
    const uint32_t* s32            = (const uint32_t*)src;
    const size_t    word_size      = sizeof(uint32_t);
    const size_t    VLEN_BITS      = 512;
    const size_t    word_count     = len_bytes / word_size;
    size_t          copied         = 0;
    size_t          vl;    // capture VL from vsetvli

    // === 1) Big‐chunk unroll with m8 (4 groups of 128 words) ===
    {
      const size_t elems_vreg8  = (VLEN_BITS * 8) / (8 * word_size); // 128 words
      const size_t max_groups8  = 32 / 8;                            // 4 groups
      size_t       big_chunks8  = word_count / elems_vreg8;
      if (big_chunks8 > max_groups8) big_chunks8 = max_groups8;
      size_t       big_chunk_w8 = big_chunks8 * elems_vreg8;

      if (big_chunk_w8) {
        while (word_count - copied >= big_chunk_w8) {
          // set VL for e32,m8
          asm volatile("vsetvli %0, %1, e32, m8, ta, ma"
                       : "=r"(vl) : "r"(big_chunk_w8));

          // pipeline loads into v0, v8, v16, v24
          if (big_chunks8 > 0)  asm volatile("vle32.v v0,  (%0)"  :: "r"(s32 + copied + 0*elems_vreg8));
          if (big_chunks8 > 1)  asm volatile("vle32.v v8,  (%0)"  :: "r"(s32 + copied + 1*elems_vreg8));
          if (big_chunks8 > 2)  asm volatile("vle32.v v16, (%0)"  :: "r"(s32 + copied + 2*elems_vreg8));
          if (big_chunks8 > 3)  asm volatile("vle32.v v24, (%0)"  :: "r"(s32 + copied + 3*elems_vreg8));

          // pipeline stores
          if (big_chunks8 > 0)  asm volatile("vse32.v v0,  (%0)"  :: "r"(d32 + copied + 0*elems_vreg8));
          if (big_chunks8 > 1)  asm volatile("vse32.v v8,  (%0)"  :: "r"(d32 + copied + 1*elems_vreg8));
          if (big_chunks8 > 2)  asm volatile("vse32.v v16, (%0)"  :: "r"(d32 + copied + 2*elems_vreg8));
          if (big_chunks8 > 3)  asm volatile("vse32.v v24, (%0)"  :: "r"(d32 + copied + 3*elems_vreg8));

          copied += big_chunk_w8;
        }
      }
    }

    // === 2) Big‐chunk unroll with m4 (8 groups of 64 words) ===
    {
      const size_t elems_vreg4  = (VLEN_BITS * 4) / (8 * word_size); //  64 words
      const size_t max_groups4  = 32 / 4;                            //   8 groups
      size_t       big_chunks4  = (word_count - copied) / elems_vreg4;
      if (big_chunks4 > max_groups4) big_chunks4 = max_groups4;
      size_t       big_chunk_w4 = big_chunks4 * elems_vreg4;

      if (big_chunk_w4) {
        while (word_count - copied >= big_chunk_w4) {
          // set VL for e32,m4
          asm volatile("vsetvli %0, %1, e32, m4, ta, ma"
                       : "=r"(vl) : "r"(big_chunk_w4));

          // pipeline loads into v0, v4, … v((big_chunks4-1)*4)
          if (big_chunks4 > 0)  asm volatile("vle32.v v0,  (%0)"  :: "r"(s32 + copied + 0*elems_vreg4));
          if (big_chunks4 > 1)  asm volatile("vle32.v v4,  (%0)"  :: "r"(s32 + copied + 1*elems_vreg4));
          if (big_chunks4 > 2)  asm volatile("vle32.v v8,  (%0)"  :: "r"(s32 + copied + 2*elems_vreg4));
          if (big_chunks4 > 3)  asm volatile("vle32.v v12, (%0)"  :: "r"(s32 + copied + 3*elems_vreg4));
          if (big_chunks4 > 4)  asm volatile("vle32.v v16, (%0)"  :: "r"(s32 + copied + 4*elems_vreg4));
          if (big_chunks4 > 5)  asm volatile("vle32.v v20, (%0)"  :: "r"(s32 + copied + 5*elems_vreg4));
          if (big_chunks4 > 6)  asm volatile("vle32.v v24, (%0)"  :: "r"(s32 + copied + 6*elems_vreg4));
          if (big_chunks4 > 7)  asm volatile("vle32.v v28, (%0)"  :: "r"(s32 + copied + 7*elems_vreg4));

          // pipeline stores
          if (big_chunks4 > 0)  asm volatile("vse32.v v0,  (%0)"  :: "r"(d32 + copied + 0*elems_vreg4));
          if (big_chunks4 > 1)  asm volatile("vse32.v v4,  (%0)"  :: "r"(d32 + copied + 1*elems_vreg4));
          if (big_chunks4 > 2)  asm volatile("vse32.v v8,  (%0)"  :: "r"(d32 + copied + 2*elems_vreg4));
          if (big_chunks4 > 3)  asm volatile("vse32.v v12, (%0)"  :: "r"(d32 + copied + 3*elems_vreg4));
          if (big_chunks4 > 4)  asm volatile("vse32.v v16, (%0)"  :: "r"(d32 + copied + 4*elems_vreg4));
          if (big_chunks4 > 5)  asm volatile("vse32.v v20, (%0)"  :: "r"(d32 + copied + 5*elems_vreg4));
          if (big_chunks4 > 6)  asm volatile("vse32.v v24, (%0)"  :: "r"(d32 + copied + 6*elems_vreg4));
          if (big_chunks4 > 7)  asm volatile("vse32.v v28, (%0)"  :: "r"(d32 + copied + 7*elems_vreg4));

          copied += big_chunk_w4;
        }
      }
    }

    // === 3) Medium chunks ≥4 words with a single vreg ===
    {
      const size_t elems_vreg4 = (VLEN_BITS * 4) / (8 * word_size); // =64
      while (word_count - copied >= 4) {
        size_t rem = word_count - copied;
        size_t avl = rem > elems_vreg4 ? elems_vreg4
                                       : (rem & ~((size_t)3));
        if (!avl) break;
        asm volatile("vsetvli %0, %1, e32, m4, ta, ma"
                     : "=r"(vl) : "r"(avl));
        asm volatile("vle32.v v0, (%0)" :: "r"(s32 + copied));
        asm volatile("vse32.v v0, (%0)" :: "r"(d32 + copied));
        copied += avl;
      }
    }

    // === 4) Inline‐asm unrolled word‐tail (0–3 words) ===
    {
      size_t word_tail = word_count - copied;
      switch (word_tail) {
        case 3:
          asm volatile(
            "lw t0,  0(%[s])\n"
            "lw t1,  4(%[s])\n"
            "lw t2,  8(%[s])\n"
            "sw t0,  0(%[d])\n"
            "sw t1,  4(%[d])\n"
            "sw t2,  8(%[d])\n"
            :
            : [s]"r"(s32 + copied), [d]"r"(d32 + copied)
            : "t0","t1","t2","memory"
          );
          copied += 3;
          break;
        case 2:
          asm volatile(
            "lw t0, 0(%[s])\n"
            "lw t1, 4(%[s])\n"
            "sw t0, 0(%[d])\n"
            "sw t1, 4(%[d])\n"
            :
            : [s]"r"(s32 + copied), [d]"r"(d32 + copied)
            : "t0","t1","memory"
          );
          copied += 2;
          break;
        case 1:
          asm volatile(
            "lw t0, 0(%[s])\n"
            "sw t0, 0(%[d])\n"
            :
            : [s]"r"(s32 + copied), [d]"r"(d32 + copied)
            : "t0","memory"
          );
          copied += 1;
          break;
        default:
          break;
      }
    }

    // === 5) Inline‐asm unrolled byte‐tail (0–3 bytes) ===
    {
      uint8_t*       d8        = (uint8_t*)(d32 + copied);
      const uint8_t* s8        = (const uint8_t*)(s32 + copied);
      size_t         byte_tail = len_bytes - word_count * word_size;
      switch (byte_tail) {
        case 3:
          asm volatile(
            "lb t0, 0(%[s])\n"
            "lb t1, 1(%[s])\n"
            "lb t2, 2(%[s])\n"
            "sb t0, 0(%[d])\n"
            "sb t1, 1(%[d])\n"
            "sb t2, 2(%[d])\n"
            :
            : [s]"r"(s8), [d]"r"(d8)
            : "t0","t1","t2","memory"
          );
          break;
        case 2:
          asm volatile(
            "lb t0, 0(%[s])\n"
            "lb t1, 1(%[s])\n"
            "sb t0, 0(%[d])\n"
            "sb t1, 1(%[d])\n"
            :
            : [s]"r"(s8), [d]"r"(d8)
            : "t0","t1","memory"
          );
          break;
        case 1:
          asm volatile(
            "lb t0, 0(%[s])\n"
            "sb t0, 0(%[d])\n"
            :
            : [s]"r"(s8), [d]"r"(d8)
            : "t0","memory"
          );
          break;
        default:
          break;
      }
    }
}
