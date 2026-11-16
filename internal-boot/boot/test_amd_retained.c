/* GPL-2.0-only. Actual ownership graph, synthetic code/PROM; RAM services only. */
#if !defined(GU_AMD_RETAINED_MULTI_DISPLAY) || defined(GU_UEFI_PORT)
#error This fixture is exclusively a host-only AMD retained display test
#endif
#include "../unlock/machine-profile.h"
/* Real SHA-256 checks over synthetic zero-filled fixtures. Production pins in
 * machine/firmware-profile.h are never changed by this translation unit. */
#undef GU_PROM_SHA256
#define GU_PROM_SHA256 "30e14955ebf1352266dc2ff8067e68104607e750abb9d3b36582b8af909fcb58"
#undef GU_EDID_TEXT_SHA256
#define GU_EDID_TEXT_SHA256 "91ad89dcb98cb520ca9eec1431624ff1d04509004d36d304879e0f7334bacab6"
#undef GU_NVGOP_TEXT_SHA256
#define GU_NVGOP_TEXT_SHA256 "d80220acc49bcaa509cd62e923c1359a74344beb9ab3af29352a8d0078174c3c"
#include "test_full.c"

static int MixedMode;
static VOID AmdRetainedTestTopology(VOID) {
  if(MixedMode==7) {
    for(UINTN i=Live.Count;i;i--) {
      EDGE *e=&Live.Edges[i-1];
      if(e->Handle==FX_EdidChild || (e->Handle==FX_RtxPci && e->Controller==FX_EdidChild))
        Live.Edges[i-1]=Live.Edges[--Live.Count];
    }
  }
  if(MixedMode==8)Live.Edges[Live.Count++]=(EDGE){FX_RtxPci,FX_NvAgent,FX_Input,PathGuid,EFI_OPEN_PROTOCOL_BY_CHILD_CONTROLLER,1};
  if(MixedMode==9)Live.Edges[Live.Count++]=(EDGE){FX_RtxPci,FX_NvAgent,FX_EdidChild,PathGuid,EFI_OPEN_PROTOCOL_BY_CHILD_CONTROLLER,1};
}
static EFI_STATUS AmdRetainedTestLog(VOID *context,const char *event,EFI_STATUS status) {
  EFI_STATUS s=FullLog(context,event,status);
  if(!strcmp(event,"amd-retained-console-pre-release-verification")) {
    if(MixedMode==10)memcpy(AdditionalChildPaths[0],TestRtxPath,sizeof(TestRtxPath));
    if(MixedMode==11 || MixedMode==12)for(UINTN i=0;i<Live.Count;i++)
      if(Live.Edges[i].Handle==FX_Amd && GuGuidEqual(&Live.Edges[i].Protocol,&EdidGuid)) {
        if(MixedMode==11)Live.Edges[i].Agent=FX_OutAgent;
        else Live.Edges[i].Count++;
      }
  }
  if(!strcmp(event,"amd-retained-display-child-consumers-preflight")) {
    if(MixedMode==1)Drop(FX_Amd,FX_EdidAgent,&EdidGuid);
    if(MixedMode==5)for(UINTN i=0;i<Live.Count;i++)
      if(Live.Edges[i].Handle==FX_RtxPci && Live.Edges[i].Controller==FX_EdidChild)Live.Edges[i].Agent=FX_OutAgent;
    if(MixedMode==6)Drop(FX_EdidChild,FX_EdidAgent,&EdidGuid);
  }
  if(!strcmp(event,"detach-edid-return") && Calls==3 && MixedMode==2)Drop(FX_Amd,FX_EdidAgent,&EdidGuid);
  if(!strcmp(event,"detach-nvidia-gop-intent")) {
    if(MixedMode==3)AdditionalChildPaths[0][GU_RTX_DISPLAY_BYTES-8]^=1;
    if(MixedMode==4)AmdMode.FrameBufferBase=0;
  }
  return s;
}
static UINTN AmdEdges(VOID) {
  UINTN count=0;for(UINTN i=0;i<Live.Count;i++)if(Live.Edges[i].Handle==FX_Amd)count++;
  return count;
}
#ifdef GU_RELEASE_AMD_MODEL
int LegacyAmdRetainedMain(int argc,char **argv) {
#else
int main(int argc,char **argv) {
#endif
  Check(argc==2,"need retained historical PCI config for capability-chain model");
  FILE *file=fopen(argv[1],"rb");
  Check(file && fread(InitialFullConfig,1,sizeof(InitialFullConfig),file)==sizeof(InitialFullConfig) && fgetc(file)==EOF,
        "read exact historical 256-byte config fixture");
  fclose(file);
  for(UINTN i=0;i<16;i++)InitialFullConfig[i]=FixtureRtxConfig[i];
  Check(AdditionalChildCount==1,"capture really contains the second RTX child");
  Check(RunFull(0)==EFI_SUCCESS,"AMD and two RTX displays complete RAM release");
  Check(Full.ChildCount==2 && Full.EdidDetached==2 && Calls==5,"two RTX EDID stops precede one NVIDIA stop");
  Check(ClaimCalls==1 && EnableCalls==1 && CloseCalls==1,"one bounded restore claim and cleanup");
  Check(AmdEdges()==4,"all AMD text/child/GOP/EDID edges retained");
  Check(GuVerifyReleased(LastTable,FALSE)==EFI_SUCCESS,"final verifier retains AMD display and input");
  const int failures[]={1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,29,30};
  for(UINTN i=0;i<sizeof(failures)/sizeof(failures[0]);i++) {
    Check(RunFull(failures[i])!=EFI_SUCCESS,"release/config/cache/hash/ownership/API failure refuses continuation");
  }
  for(MixedMode=1;MixedMode<=6;MixedMode++) {
    Check(RunFull(0)!=EFI_SUCCESS,"AMD or last-child drift refuses release");
    Check(Phase<4 && !ClaimCalls && !EnableCalls,"no NVIDIA stop or restore claim after unsafe drift");
  }
  MixedMode=0;
  Check(RunFull(0)==EFI_SUCCESS,"fresh RAM session succeeds after previous failures");
  TestAmdPath[28]^=1;
  Check(GuVerifyReleased(LastTable,FALSE)!=EFI_SUCCESS,"late AMD endpoint change blocks Windows");
  MixedMode=7;
  Check(RunFull(0)==EFI_SUCCESS && Full.ChildCount==1 && Calls==4 && Full.EdidDetached==1 && AmdEdges()==4,
        "one RTX child also retains AMD and completes one EDID/NVIDIA sequence");
  for(MixedMode=8;MixedMode<=12;MixedMode++) {
    if(MixedMode==9) {
      FullMode=FALSE;
      Check(Run(0)!=EFI_SUCCESS && Calls==0,"duplicate captured child edge fails console preparation before mutation");
      continue;
    }
    Check(RunFull(0)!=EFI_SUCCESS,"third/duplicate child/path and AMD EDID owner/count refuse");
    Check(Calls==2 && !ClaimCalls && !EnableCalls,"unsafe topology stops before any EDID or NVIDIA call");
  }
  printf("PASS AMD-retained dual-display: %d checks; captured graph, synthetic code/PROM and historical config tail, RAM only\n",Checks);
  return 0;
}
