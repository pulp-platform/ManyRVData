// Copyright 2025 ETH Zurich and University of Bologna.
//
// SPDX-License-Identifier: Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Author: Zexin Fu     <zexifu@iis.ee.ethz.ch>

// Use vector lsu to move data between two memory locations
#ifndef VECTOR_MEMCPY_H
#define VECTOR_MEMCPY_H

/**
 * @brief Naïve byte‐by‐byte memory copy baseline.
 *
 * Copies len_bytes from src to dst one uint8_t at a time.
 *
 * @param dst        Destination pointer
 * @param src        Source pointer
 * @param len_bytes  Number of bytes to copy
 */
void __attribute__((noinline)) scalar_memcpy32_8bit(void* dst, const void* src, size_t len_bytes);


/**
 * @brief Scalar memory copy: 32-bit chunks + 8-bit tail.
 *
 * Copies len_bytes from src to dst using:
 *   1) 4-byte (uint32_t) transfers for as many full words as possible,
 *   2) single-byte transfers for the remaining 0–3 bytes.
 *
 * @param dst        Destination pointer
 * @param src        Source pointer
 * @param len_bytes  Number of bytes to copy
 */
void __attribute__((noinline)) scalar_memcpy32_32bit(void* dst, const void* src, size_t len_bytes);


/**
 * @brief Unrolled scalar copy: 4×32-bit chunks + byte tail.
 *
 * Copies len_bytes from src to dst by:
 *   1) 4-word (4×uint32_t) copies per loop,
 *   2) remaining 1–3 words,
 *   3) remaining 0–3 bytes.
 *
 * @param dst        Destination pointer (must be 32-bit aligned)
 * @param src        Source pointer (must be 32-bit aligned)
 * @param len_bytes  Number of bytes to copy
 */
void __attribute__((noinline)) scalar_memcpy32_32bit_unrolled(void* dst, const void* src, size_t len_bytes);

/**
 * @brief Optimized vector memory copy using RVV with e32 and m4 setting.
 *
 * Copies 32-bit data using vector instructions with m4 grouping,
 * exploiting 8 vector register groups (v0, v4, ..., v28) to overlap loads/stores
 * and maximize throughput on systems with 512-bit VLEN.
 *
 * @param dst        Destination memory address (must be 32-bit aligned)
 * @param src        Source memory address (must be 32-bit aligned)
 * @param len_bytes  Total number of bytes to copy
 */
void vector_memcpy32_m4_opt(void* dst, const void* src, size_t len_bytes);


/**
 * @brief Optimized vector memory copy using RVV with e32 and m8 setting.
 *
 * Copies 32-bit data using vector instructions with m8 grouping,
 * using 4 vector register groups (v0, v8, v16, v24) to maximize throughput
 * and exploit wider register bandwidth when available.
 *
 * @param dst        Destination memory address (must be 32-bit aligned)
 * @param src        Source memory address (must be 32-bit aligned)
 * @param len_bytes  Total number of bytes to copy
 */
void vector_memcpy32_m8_opt(void* dst, const void* src, size_t len_bytes);


/**
 * @brief   RVV‐accelerated memcpy for 32‐bit words, fully unrolled tail.
 * @param   dst        Destination buffer (32‐bit aligned)
 * @param   src        Source buffer      (32‐bit aligned)
 * @param   len_bytes  Number of bytes to copy
 */
void vector_memcpy32_m4_general_opt (void* dst, const void* src, size_t len_bytes);


/**
 * @brief RVV‐accelerated memcpy for 32‐bit words with m8→m4 fallback.
 *
 * 1) Try big‐chunk unroll with e32,m8 (4 × 128‐word groups)  
 * 2) Then big‐chunk with e32,m4 (8 × 64‐word groups)  
 * 3) Medium chunk for ≥4 words  
 * 4) Inline‐asm unrolled word‐tail (0–3 words)  
 * 5) Inline‐asm unrolled byte‐tail (0–3 bytes)
 */
void vector_memcpy32_m8_m4_general_opt(void* dst, const void* src, size_t len_bytes);

#endif // VECTOR_MEMCPY_H
