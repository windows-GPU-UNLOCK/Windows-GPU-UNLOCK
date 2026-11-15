/* SPDX-License-Identifier: GPL-2.0-only */
#include <assert.h>
#include <stdio.h>
#include "layout-inputs.h"
#include "../../internal-boot/unlock/vendor/layout_610.h"
int main(void) {
    struct gu_turing_inputs in={0};
    /* Synthetic 44 * 2^28 = 11 GiB, not a captured 2080 Ti register. */
    assert(gu_turing_layout_inputs(0x2c8,0,&in));
    assert(in.usable_fb==11811160064ULL && in.vga_base==11810111488ULL);
    struct gpu_unlock_layout_in geometry={
        .usable_fb=in.usable_fb,.vga_base=in.vga_base,.mmu_lock_valid=false,
        .frts_size=0x100000,.boot_size=4096,.image_size=0x800000,
        .nonwpr_size=0x200000,.heap_request=0x1000000};
    struct gpu_unlock_layout_out layout;
    assert(gpu_unlock_layout(&geometry,&layout)==0);
    assert(layout.wpr_end<=in.vga_base && layout.wpr_end<=in.usable_fb);
    assert(layout.nonwpr_start<layout.wpr_start && layout.wpr_start<layout.gsp_offset);
    assert(gu_turing_layout_inputs(0x400002c8,0,&in));
    assert(in.usable_fb==11072962560ULL); /* 11 GiB * 15/16 */
    assert(gu_turing_layout_inputs(0x2c8,8,&in));
    assert(in.vga_base==11811028992ULL); /* lower VGA claim uses top128KiB */
    assert(!gu_turing_layout_inputs(0x2c8,0xffffff08U,&in));
    assert(!in.usable_fb && !in.vga_base);
    unsigned tested=0;
    for(unsigned mag=1;mag<64;mag++)for(unsigned scale=0;scale<16;scale++)
      for(unsigned ecc=0;ecc<2;ecc++) {
        uint32_t r=(mag<<4)|scale|(ecc<<30);
        uint64_t bytes=(uint64_t)mag<<(scale+20);
        if(ecc) bytes=bytes/16*15;
        bool accepted=gu_turing_layout_inputs(r,0,&in);
        assert(accepted==(bytes>=(256ULL<<20)));
        if(accepted)assert(in.usable_fb==bytes && in.vga_base==bytes-(1ULL<<20));
        else assert(!in.usable_fb && !in.vga_base);
        tested++;
      }
    const uint32_t bad[]={0,0xf,UINT32_MAX,0xbadf5620U,0x800002c8U,0x100002c8U};
    for(unsigned i=0;i<sizeof(bad)/sizeof(bad[0]);i++) {
        assert(!gu_turing_layout_inputs(bad[i],0,&in));
        assert(!in.usable_fb && !in.vga_base);
    }
    assert(!gu_turing_layout_inputs(0x2c8,UINT32_MAX,&in));
    assert(!gu_turing_layout_inputs(0x2c8,0xbadf5620U,&in));
    assert(!gu_turing_layout_inputs(0x2c8,0,NULL));
    puts("PASS: 2016 synthetic range combinations, VGA/sentinel refusals, unchanged actual layout calculator");
    assert(tested==2016);
    return 0;
}
