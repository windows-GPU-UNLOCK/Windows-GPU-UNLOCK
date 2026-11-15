/* SPDX-License-Identifier: GPL-2.0-only
 * Research-only arithmetic on already captured/synthetic integers.
 * Not included by any EFI target; does not read registers or admit a GPU.
 */
#ifndef GU_RESEARCH_TURING_LAYOUT_INPUTS_H
#define GU_RESEARCH_TURING_LAYOUT_INPUTS_H
#include <stdint.h>
#include <stdbool.h>
struct gu_turing_inputs {uint64_t usable_fb, vga_base;};
static bool gu_turing_layout_inputs(uint32_t range, uint32_t vga,
                                    struct gu_turing_inputs *out) {
    if (!out) return false;
    *out=(struct gu_turing_inputs){0};
    /* Only reviewed magnitude/scale/ECC fields. Unknown bits are a refusal,
     * stricter than the pinned Linux reader; no hardware samples qualify it. */
    if (range==UINT32_MAX || (range&0xffff0000U)==0xbadf0000U ||
        (range&~0x400003ffU) || vga==UINT32_MAX ||
        (vga&0xffff0000U)==0xbadf0000U) return false;
    uint32_t mag=(range>>4)&0x3fU, scale=range&0xfU;
    if (!mag) return false;
    uint64_t bytes=(uint64_t)mag<<(scale+20);
    if (range&(1U<<30)) bytes=bytes/16*15;
    if (bytes<(256ULL<<20)) return false;
    uint64_t base=bytes-(1ULL<<20);
    if (vga&(1U<<3)) {
        base=(uint64_t)(vga>>8)<<16;
        if (base<bytes-(1ULL<<20)) base=bytes-0x20000;
    }
    if (base>=bytes) return false;
    *out=(struct gu_turing_inputs){bytes,base};
    return true;
}
#endif
