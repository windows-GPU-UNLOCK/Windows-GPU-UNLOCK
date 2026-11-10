/* SPDX-License-Identifier: GPL-2.0-only
 * Research metadata only, no production callers, firmware copies or execution.
 */
#ifndef GU_RESEARCH_FWSEC_V2_METADATA_H
#define GU_RESEARCH_FWSEC_V2_METADATA_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
struct gu_v2_metadata {
    uint32_t image_offset,image_size,code_size,nonsecure_size;
    uint32_t secure_pa,secure_size,data_offset,data_size,interface_offset;
};
static uint32_t gu_v2_u32(const uint8_t *p) {
    return (uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
}
static bool gu_v2_span(uint32_t size,uint32_t at,uint32_t count) {
    return at<=size && count<=size-at;
}
static bool gu_v2_round(uint32_t value,uint32_t *out) {
    if(!value || value>UINT32_MAX-255) return false;
    *out=(value+255)&~255U;
    return true;
}
static bool gu_v2_metadata(const uint8_t *data,size_t length,struct gu_v2_metadata *out) {
    if(!out) return false;
    *out=(struct gu_v2_metadata){0};
    if(!data || length<60 || length>1024*1024) return false;
    uint32_t hdr=gu_v2_u32(data),desc=hdr>>16;
    if((hdr&0xffff)!=0x201 || desc<60 || desc>length) return false;
    /* Research subset: generic-loader entry and DMEM base must be zero;
     * unreviewed tail fields stop rather than acquiring inferred meaning. */
    if(gu_v2_u32(data+12) || gu_v2_u32(data+44) ||
       gu_v2_u32(data+52) || gu_v2_u32(data+56)) return false;
    struct gu_v2_metadata m={.image_offset=desc};
    uint32_t code_aligned,data_aligned;
    if(!gu_v2_round(gu_v2_u32(data+4),&m.image_size) ||
       m.image_size>length-desc) return false;
    m.interface_offset=gu_v2_u32(data+16);
    uint32_t code_pa=gu_v2_u32(data+20),code_va=gu_v2_u32(data+28);
    m.code_size=gu_v2_u32(data+24);
    uint32_t secure_va=gu_v2_u32(data+32),secure=gu_v2_u32(data+36);
    m.data_offset=gu_v2_u32(data+40);m.data_size=gu_v2_u32(data+48);
    if(secure>m.code_size || secure_va<code_va ||
       secure_va-code_va>UINT32_MAX-code_pa ||
       !gu_v2_round(secure,&m.secure_size) ||
       !gu_v2_round(m.code_size,&code_aligned) ||
       !gu_v2_round(m.data_size,&data_aligned)) return false;
    m.secure_pa=secure_va-code_va+code_pa;
    m.nonsecure_size=m.code_size-secure;
    if(!gu_v2_span(m.image_size,0,m.code_size) ||
       !gu_v2_span(m.image_size,m.secure_pa,m.secure_size) ||
       !gu_v2_span(m.image_size,m.data_offset,m.data_size) ||
       !gu_v2_span(code_aligned,code_pa,m.code_size) ||
       !gu_v2_span(code_aligned,m.secure_pa,m.secure_size) ||
       !gu_v2_span(data_aligned,0,m.data_size) ||
       !gu_v2_span(m.data_size,m.interface_offset,4)) return false;
    *out=m;
    return true;
}
#endif
