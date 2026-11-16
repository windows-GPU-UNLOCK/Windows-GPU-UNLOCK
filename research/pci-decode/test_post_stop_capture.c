/* GPL-2.0-only. Real collector calls, RAM firmware model, no physical effects. */
#define GU_DS_POST_STOP_TEST
#include "test_efi_capture.c"
#include "stop-transition.h"

static GU_DS_SNAPSHOT Before,ExpectedBefore;
static BOOLEAN PostReentry,FreezeBefore,BeforeFrozen;
static unsigned SwitchAt;
static BOOLEAN ReleasedMode;
static void PostHook(void) {
  if(PostReentry) {
    unsigned calls=M->Calls;GU_DS_CAPTURE fresh={0};
    Check(GuDsEfiCaptureAfterStop(&Capture,&M->Boot,&Target,&Before)==EFI_ALREADY_STARTED,
      "post entry refuses active context");
    Check(GuDsEfiCaptureAfterStop(&fresh,&M->Boot,&Target,&Before)==EFI_ALREADY_STARTED && !fresh.Used,
      "post entry refuses fresh context before private baseline changes");
    Check(GuDsEfiCapture(&fresh,&M->Boot,&Target)==EFI_ALREADY_STARTED && !fresh.Used,
      "ordinary entry shares post entry workspace guard");
    Check(GuDsEfiCaptureReleasedMismatch(&fresh,&M->Boot,&Target,&Before)==EFI_ALREADY_STARTED && !fresh.Used,
      "released-mismatch entry shares the same workspace guard");
    Check(GuDsEfiCaptureReleaseOrigin(&fresh,&M->Boot,&Target)==EFI_ALREADY_STARTED && !fresh.Used,
      "release-origin entry shares the workspace guard");
    Check(GuDsEfiCaptureIoMemAfterStop(&fresh,&M->Boot,&Target,&Before)==EFI_ALREADY_STARTED && !fresh.Used,
      "coherent IO+MEM entry shares the workspace guard");
    Check(M->Calls==calls,"cross entry reentry makes no service call");
  }
  if(FreezeBefore && !BeforeFrozen){BeforeFrozen=TRUE;Before.Gpu.Config[63]^=1;}
  if(SwitchAt && M->Calls+1==SwitchAt) {
    M->Devices[0].State.Config[1]^=2;
    M->Devices[0].State.Attributes^=GU_DS_MEMORY;SwitchAt=0;
  }
}
static void PostSetup(MODEL *m,unsigned parents,UINTN segment,BOOLEAN off) {
  CaptureSetup(m,parents,segment);Before=m->Expected;Before.Gpu.Attributes=GU_DS_MEMORY;
  ExpectedBefore=Before;m->Devices[0].State.Attributes=off?0:GU_DS_MEMORY;
  if(off)m->Devices[0].State.Config[1]&=~2U;
  PostReentry=FreezeBefore=BeforeFrozen=FALSE;SwitchAt=0;CaptureExtraHook=PostHook;
  ReleasedMode=FALSE;
}
static void ReleasedSetup(MODEL *m,unsigned parents,UINTN segment) {
  PostSetup(m,parents,segment,TRUE);Before.Gpu.Attributes|=GU_DS_IO;ExpectedBefore=Before;ReleasedMode=TRUE;
}
static EFI_STATUS PostCollect(MODEL *m) {
  return ReleasedMode?GuDsEfiCaptureReleasedMismatch(&Capture,&m->Boot,&Target,&Before):
    GuDsEfiCaptureAfterStop(&Capture,&m->Boot,&Target,&Before);
}
static void PostRefuse(MODEL *m) {
  Check(PostCollect(m)!=EFI_SUCCESS,"unsafe post capture refuses");
  GU_DS_SNAPSHOT empty={0};GU_DS_EFI_BINDING binding={0};
  Check(Capture.Used && !Capture.Ready && !Capture.Busy && !Capture.Count,
    "post failure is spent with no published result");
  Check(!memcmp(&empty,&Capture.Snapshot,sizeof(empty)),"post failure clears partial snapshot");
  for(unsigned i=0;i<16;i++)Check(!memcmp(&binding,&Capture.Bindings[i],sizeof(binding)),"post failure clears partial bindings");
  unsigned calls=m->Calls;
  Check(PostCollect(m)==EFI_ALREADY_STARTED && m->Calls==calls,"post failure cannot be retried");
  ReadOnly(m);
  PostSetup(m,2,0,TRUE);
  Check(PostCollect(m)==EFI_SUCCESS,"separate normal session after failure releases guard");ReadOnly(m);
}
#ifdef GU_DS_IOMEM_TEST
int legacy_post_capture_main(void) {
#else
int main(void) {
#endif
  Check(capture_fixture_main()==0,"ordinary capture suite unchanged in opt-in build");
  MODEL m;
  for(unsigned p=1;p<=15;p++)for(unsigned s=0;s<3;s++)for(unsigned off=0;off<2;off++) {
    PostSetup(&m,p,s==2?0xffff:s,(BOOLEAN)off);PostReentry=TRUE;
    Check(PostCollect(&m)==EFI_SUCCESS && Capture.Ready && Capture.Count==m.Count,"post capture across parent depths and segments");
    Check(GuDsStopTransition(&ExpectedBefore,&Capture.Snapshot)==(off?GU_DS_STOP_MEMORY_OFF:GU_DS_STOP_UNCHANGED),
      "observed post capture composes with pure transition");
    ReadOnly(&m);
    PostSetup(&m,p,s==2?0xffff:s,(BOOLEAN)off);PostReentry=TRUE;
    Check(Collect(&m)==(off?EFI_NOT_READY:EFI_SUCCESS),"ordinary policy never admits memory-off state");ReadOnly(&m);
  }
  PostSetup(&m,2,0,TRUE);Check(PostCollect(&m)==EFI_SUCCESS,"post fault sweep baseline");unsigned calls=m.Calls;
  for(unsigned at=1;at<=calls;at++) {
    for(unsigned warning=0;warning<2;warning++) {
      PostSetup(&m,2,0,TRUE);m.FaultAt=at;m.FaultStatus=warning?EFI_WARN_UNKNOWN_GLYPH:EFI_DEVICE_ERROR;PostRefuse(&m);
    }
    PostSetup(&m,2,0,TRUE);m.DropAt=at;PostRefuse(&m);
    for(unsigned mutation=6;mutation<=10;mutation++) {
      PostSetup(&m,2,0,TRUE);m.Mutation=mutation;m.MutateAt=at;PostRefuse(&m);
    }
  }
  for(unsigned mutation=1;mutation<=5;mutation++) {
    PostSetup(&m,2,0,TRUE);m.Mutation=mutation;m.MutateAt=1;PostRefuse(&m);
  }
  PostSetup(&m,2,0,TRUE);SwitchAt=calls/2+1;PostRefuse(&m);
  PostSetup(&m,2,0,FALSE);SwitchAt=calls/2+1;PostRefuse(&m);
  PostSetup(&m,2,0,TRUE);m.Partial=1;PostRefuse(&m);
  PostSetup(&m,2,0,TRUE);ReplaceAt=calls/2+1;PostRefuse(&m);
  for(unsigned bad=0;bad<8;bad++) {
    PostSetup(&m,2,0,TRUE);
    switch(bad) {
      case 0:Before.Gpu.Attributes|=GU_DS_IO;break;
      case 1:Before.Complete=2;break;
      case 2:Before.Gpu.Supported&=~GU_DS_MEMORY;m.Devices[0].State.Supported&=~GU_DS_MEMORY;break;
      case 3:Before.Gpu.Handle^=1;break;
      case 4:Before.Gpu.Interface^=1;break;
      case 5:Before.Parents[0].Attributes^=1ULL<<40;break;
      case 6:Target.Path[8]^=1;break;
      case 7:Before.ParentCount++;break;
    }
    PostRefuse(&m);
  }
  PostSetup(&m,2,0,TRUE);FreezeBefore=FreezeTarget=TRUE;
  Check(PostCollect(&m)==EFI_SUCCESS && BeforeFrozen && Frozen,"private baseline and target freeze precede services");
  Check(GuDsStopTransition(&ExpectedBefore,&Capture.Snapshot)==GU_DS_STOP_MEMORY_OFF,"caller edits cannot redirect transition baseline");ReadOnly(&m);
  PostSetup(&m,2,0,TRUE);GU_DS_CAPTURE saved=Capture;
  Check(GuDsEfiCaptureAfterStop(&Capture,&m.Boot,&Target,NULL)==EFI_INVALID_PARAMETER &&
    !memcmp(&saved,&Capture,sizeof(saved)) && !m.Calls,"null baseline leaves storage alone");
  Check(GuDsEfiCaptureAfterStop(&Capture,&m.Boot,&Target,&Capture.Snapshot)==EFI_INVALID_PARAMETER &&
    !memcmp(&saved,&Capture,sizeof(saved)) && !m.Calls,"baseline/context overlap refuses before mutation");
  Check(GuDsEfiCaptureAfterStop(&Capture,&m.Boot,&Target,(VOID *)&Target)==EFI_INVALID_PARAMETER &&
    !memcmp(&saved,&Capture,sizeof(saved)) && !m.Calls,"baseline/target overlap refuses before mutation");
  Check(GuDsEfiCaptureAfterStop(&Capture,&m.Boot,&Target,(VOID *)&m.Boot)==EFI_INVALID_PARAMETER &&
    !memcmp(&saved,&Capture,sizeof(saved)) && !m.Calls,"baseline/Boot overlap refuses before mutation");
  for(unsigned p=1;p<=15;p++)for(unsigned s=0;s<3;s++) {
    ReleasedSetup(&m,p,s==2?0xffff:s);PostReentry=TRUE;
    Check(PostCollect(&m)==EFI_SUCCESS && Capture.Ready,"hypothetical uncorrected baseline release capture");
    GU_DS_RELEASE_PLAN plan;
    Check(GuDsPlanReleasedMismatch(&Before,&Capture.Snapshot,&plan) &&
      Before.Gpu.Attributes==0x300 && !Capture.Snapshot.Gpu.Attributes && plan.PlannedGpu.Attributes==GU_DS_MEMORY,
      "actual cache observations and derived target stay separate");ReadOnly(&m);
  }
  ReleasedSetup(&m,2,0);Check(PostCollect(&m)==EFI_SUCCESS,"released-mismatch fault baseline");calls=m.Calls;
  for(unsigned at=1;at<=calls;at++) {
    for(unsigned warning=0;warning<2;warning++) {
      ReleasedSetup(&m,2,0);m.FaultAt=at;m.FaultStatus=warning?EFI_WARN_UNKNOWN_GLYPH:EFI_DEVICE_ERROR;PostRefuse(&m);
    }
    ReleasedSetup(&m,2,0);m.DropAt=at;PostRefuse(&m);
  }
  for(unsigned bad=0;bad<8;bad++) {
    ReleasedSetup(&m,2,0);
    switch(bad) {
      case 0:Before.Gpu.Attributes=GU_DS_MEMORY;break;
      case 1:m.Devices[0].State.Attributes=GU_DS_IO;break;
      case 2:m.Devices[0].State.Attributes=GU_DS_MEMORY;break;
      case 3:m.Devices[0].State.Config[1]|=2;m.Devices[0].State.Attributes=GU_DS_MEMORY;break;
      case 4:Before.Gpu.Config[63]^=1;break;
      case 5:Before.Parents[1].Config[63]^=1;break;
      case 6:m.Devices[0].State.Config[1]|=4;break;
      case 7:Before.Gpu.Supported&=~GU_DS_MEMORY;break;
    }
    PostRefuse(&m);
  }
  ReleasedSetup(&m,2,0);FreezeBefore=FreezeTarget=TRUE;
  Check(PostCollect(&m)==EFI_SUCCESS && BeforeFrozen && Frozen,"released-mismatch baseline frozen before callbacks");
  GU_DS_RELEASE_PLAN frozenPlan;
  Check(GuDsPlanReleasedMismatch(&ExpectedBefore,&Capture.Snapshot,&frozenPlan),"retained actual baseline revalidates observed release");
  printf("PASS %u post-Stop capture/composition assertions; RAM only\n",Checks);return 0;
}
