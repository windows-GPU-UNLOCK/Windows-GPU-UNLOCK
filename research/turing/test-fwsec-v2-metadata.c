/* SPDX-License-Identifier: GPL-2.0-only */
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include "fwsec-v2-metadata.h"
static uint8_t data[4096];
static void w(unsigned off,uint32_t v){for(unsigned i=0;i<4;i++)data[off+i]=(uint8_t)(v>>(8*i));}
static void setup(void){
    memset(data,0,sizeof(data));w(0,(60U<<16)|0x201);w(4,2048);
    w(16,16);w(24,512);w(28,0x1000);w(32,0x1100);w(36,256);
    w(40,1024);w(48,1024);
}
static unsigned checks;
static void refused(size_t length){
    struct gu_v2_metadata m;memset(&m,0xff,sizeof(m));
    assert(!gu_v2_metadata(data,length,&m));
    struct gu_v2_metadata zero={0};assert(!memcmp(&m,&zero,sizeof(m)));checks++;
}
int main(void){
    struct gu_v2_metadata m;setup();
    assert(gu_v2_metadata(data,sizeof(data),&m));
    assert(m.image_offset==60 && m.image_size==2048 && m.code_size==512);
    assert(m.nonsecure_size==256 && m.secure_pa==256 && m.secure_size==256);
    assert(m.data_offset==1024 && m.data_size==1024 && m.interface_offset==16);
    for(size_t length=0;length<60;length++){setup();refused(length);}
    setup();refused(2107); /* descriptor+image needs 2108 bytes */
    setup();assert(gu_v2_metadata(data,2108,&m));
    const struct {unsigned off;uint32_t value;} bad[]={
      {0,(59U<<16)|0x201},{0,(60U<<16)|0x301},{0,(60U<<16)|0x203},
      {4,0},{4,UINT32_MAX},{12,1},{16,1021},{20,UINT32_MAX},
      {24,UINT32_MAX},{28,0x1200},{32,0xffffffff},{36,513},
      {36,0},{40,2048},{44,1},{48,UINT32_MAX},{52,1},{56,1}
    };
    for(unsigned i=0;i<sizeof(bad)/sizeof(bad[0]);i++){setup();w(bad[i].off,bad[i].value);refused(sizeof(data));}
    setup();assert(!gu_v2_metadata(NULL,sizeof(data),&m));
    assert(!gu_v2_metadata(data,sizeof(data),NULL));
    assert(checks==79);
    puts("PASS: v2 research metadata, exact image boundary, 79 truncation/geometry refusals and zero failure output");
    return 0;
}
