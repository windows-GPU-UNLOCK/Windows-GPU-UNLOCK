/* GPL-2.0-only. Fixed-profile retained AMD frontend, host RAM only. */
#define GU_RELEASE_AMD_MODEL 1
static void AmdRetainedAuditTests(void);
#include "test_release_parent_audit.c"

static VOID AmdRetainedAuditTests(VOID) {
#ifdef GU_RELEASE_MISMATCH_RESEARCH
  const unsigned routes=2;
#else
  const unsigned routes=1;
#endif
  for(unsigned route=0;route<routes;route++) {
    OwnershipDefaults();ModelMismatch=(BOOLEAN)route;MixedMode=0;AmdScenario=0;
    Check(AuditedRun(0,FALSE)==EFI_SUCCESS && Full.ChildCount==1+AdditionalChildCount &&
      EdidStops==Full.ChildCount && NvStops==1 && AmdEdges()==4,"AMD and captured RTX children survive audited release");
    Check(AmdMode.FrameBufferBase==0xfce0000000ULL && LastTable->ConOut==&Text && LastTable->ConIn==&Keys &&
      !memcmp(TestAmdPath,PreparedPlan.AmdDisplayPath,sizeof(TestAmdPath)),"AMD framebuffer/path/text/input retained");
    UINTN segment,bus,device,function;Check(AuditLocation(&AmdPci,&segment,&bus,&device,&function)==EFI_SUCCESS &&
      !segment && bus==12 && !device && !function,"AMD BDF is not normalized to RTX or its parent");
    Check(GuVerifyReleased(LastTable,TRUE)==EFI_SUCCESS && GuVerifyReleased(LastTable,FALSE)==EFI_SUCCESS,"AMD typed cold/final checks");
    for(unsigned fault=1;fault<=5;fault++) {
      AmdAfterEdidFault=fault;
      Check(AuditedRun(0,FALSE)!=EFI_SUCCESS && EdidStops==1 && !NvStops && !ClaimCalls && !EnableCalls,
        "AMD shared EDID owner/count/framebuffer/path/geometry drift after first child blocks subsequent release");
    }
    AmdAfterEdidFault=0;
    if(AdditionalChildCount==1) {
      const int failures[]={1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,29,30};
      for(UINTN i=0;i<sizeof(failures)/sizeof(failures[0]);i++) {
        AmdScenario=failures[i];Check(AuditedRun(0,FALSE)!=EFI_SUCCESS,"legacy retained AMD failure refused");
      }
      AmdScenario=0;
      for(MixedMode=1;MixedMode<=6;MixedMode++) {
        Check(AuditedRun(0,FALSE)!=EFI_SUCCESS && Phase<4 && !ClaimCalls && !EnableCalls,"original AMD/last-child drift blocks NVIDIA Stop/write");
      }
      MixedMode=7;
      EFI_STATUS single=AuditedRun(0,FALSE);
      Check(single==EFI_SUCCESS && Full.ChildCount==1 && EdidStops==1 && NvStops==1 && AmdEdges()==4,"dual-child graph with one RTX child retains AMD");
      for(MixedMode=8;MixedMode<=12;MixedMode++) {
        Check(AuditedRun(0,FALSE)!=EFI_SUCCESS && Calls==(MixedMode==9?0:2) && !ClaimCalls && !EnableCalls,
          "original excess/duplicate child and AMD owner/count faults stop before driver release");
      }
      MixedMode=0;
    }
    for(unsigned fault=1;fault<=5;fault++) {
      Check(AuditedRun(0,FALSE)==EFI_SUCCESS,"fresh session for final AMD fault");
      if(fault==1)TestAmdPath[28]^=1;
      if(fault==2)AmdMode.FrameBufferBase=0;
      if(fault==3)AmdInfo.HorizontalResolution=0;
      if(fault==4)Drop(FX_Amd,FX_EdidAgent,&EdidGuid);
      if(fault==5)LastTable->ConIn=NULL;
      int calls=Calls,enables=EnableCalls;
      Check(GuVerifyReleased(LastTable,FALSE)!=EFI_SUCCESS && Calls==calls && EnableCalls==enables,
        "late AMD display/input drift blocks handoff without repeated effects");
    }
    Check(AuditedRun(0,FALSE)==EFI_SUCCESS,"fresh AMD session for last graph callback drift");
    AmdFinalBindingFault=TRUE;AmdFinalBindingInjected=FALSE;
    Check(GuVerifyReleased(LastTable,FALSE)!=EFI_SUCCESS && AmdFinalBindingInjected &&
      !strcmp(GuLastVerifyDiagnostic()->Stage,"verify-final-bindings"),"last graph callback binding drift blocks AMD handoff");
    AmdFinalBindingFault=FALSE;
  }
  MixedMode=0;AmdScenario=0;AmdAfterEdidFault=0;OwnershipDefaults();
}
