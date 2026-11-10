/* GPL-2.0-only. Pure path policy, no firmware or GPU access. */
#include "../../internal-boot/unlock/checks.h"
#include <stdio.h>
#include <string.h>
int main(void) {
  const UINT8 original[]={2,1,12,0,0xd0,0x41,3,0x0a,0,0,0,0,
    1,1,6,0,1,8,1,1,6,0,0,0,2,3,8,0,0,3,1,0x80,0x7f,0xff,4,0};
  UINT8 path[sizeof(original)];unsigned checks=0;
  for(unsigned i=0;i<sizeof(original);i++) {
    checks++;if(GuDisplayPath((VOID *)original,i)!=0)return 1;
    for(unsigned bit=0;bit<8;bit++) {
      memcpy(path,original,sizeof(path));path[i]^=(UINT8)(1U<<bit);
      int expected=0;
#if defined(GU_PROFILE_B650M_3090FE) && !defined(GU_HEADLESS_RESEARCH)
      if(i>=28 && i<32)expected=1;
#endif
      checks++;if(GuDisplayPath((VOID *)path,sizeof(path))!=expected)return 1;
    }
  }
  if(GuDisplayPath((VOID *)original,sizeof(original))!=1)return 1;
  printf("PASS %u pure path checks; profile/headless scope preserved\n",checks+1);return 0;
}
