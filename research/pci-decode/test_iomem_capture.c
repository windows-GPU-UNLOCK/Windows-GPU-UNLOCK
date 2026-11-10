/* GPL-2.0-only. Coherent IO+MEM release observations, RAM-only services. */
#define GU_DS_IOMEM_TEST
#include "test_post_stop_capture.c"

static void IoMemSetup(MODEL *m,unsigned parents,UINTN segment,unsigned remaining) {
  PostSetup(m,parents,segment,TRUE);
  Before.Gpu.Config[1]|=1U;Before.Gpu.Attributes=GU_DS_IO|GU_DS_MEMORY;
  ExpectedBefore=Before;
  m->Devices[0].State.Config[1]=(Before.Gpu.Config[1]&~3U)|remaining;
  m->Devices[0].State.Attributes=(remaining&1?GU_DS_IO:0)|(remaining&2?GU_DS_MEMORY:0);
}
static EFI_STATUS IoMemCollect(MODEL *m) {
  return GuDsEfiCaptureIoMemAfterStop(&Capture,&m->Boot,&Target,&Before);
}
static void IoMemRefuse(MODEL *m) {
  Check(IoMemCollect(m)!=EFI_SUCCESS,"unsafe coherent IO+MEM capture refused");
  GU_DS_SNAPSHOT empty={0};GU_DS_EFI_BINDING binding={0};
  Check(Capture.Used && !Capture.Ready && !Capture.Busy && !Capture.Count &&
    !memcmp(&empty,&Capture.Snapshot,sizeof(empty)),"IO+MEM refusal publishes no partial observation");
  for(unsigned i=0;i<16;i++)Check(!memcmp(&binding,&Capture.Bindings[i],sizeof(binding)),"no partial IO+MEM binding");
  unsigned calls=m->Calls;Check(IoMemCollect(m)==EFI_ALREADY_STARTED && calls==m->Calls,"IO+MEM refusal cannot be retried");ReadOnly(m);
}
int main(void) {
  Check(legacy_post_capture_main()==0,"existing ordinary/corrected/mismatch policies unchanged");
  MODEL m;
  Check(!GuDsReleaseSnapshotValid(NULL) && GuDsIoMemStopTransition(NULL,NULL)==GU_DS_STOP_REFUSED,"missing IO+MEM observations refuse");
  for(unsigned p=1;p<=15;p++)for(unsigned segment=0;segment<3;segment++) {
    UINTN s=segment==2?0xffff:segment;
    for(unsigned remaining=0;remaining<4;remaining++) {
      IoMemSetup(&m,p,s,remaining);PostReentry=TRUE;
      Check(!GuDecodeSnapshotValid(&Before) && GuDsReleaseSnapshotValid(&Before),"command3 is release-only, never correction eligible");
      Check(GuDsStopTransition(&Before,&Before)==GU_DS_STOP_REFUSED,"corrected transition rejects coherent3");
      GU_DS_RELEASE_PLAN plan;
      Check(!GuDsPlanReleasedMismatch(&Before,&Before,&plan),"mismatch plan rejects coherent3");
      Check(IoMemCollect(&m)==EFI_SUCCESS && Capture.Ready && Capture.Count==m.Count,"IO+MEM capture across depths/segments/subsets");
      Check(GuDsIoMemStopTransition(&ExpectedBefore,&Capture.Snapshot)==(remaining==3?GU_DS_STOP_UNCHANGED:GU_DS_STOP_DECODE_REDUCED),"exact coherent subset observed");
      Check(GuDecodeSnapshotMatches(&Before,&ExpectedBefore,FALSE),"original300 remains an observation");ReadOnly(&m);
    }
    IoMemSetup(&m,p,s,0);GU_DS_SNAPSHOT after=ExpectedBefore;after.Gpu.Config[1]&=~3U;after.Gpu.Attributes=0;
    GU_DS_SNAPSHOT original=after;
    for(unsigned node=0;node<=p;node++)for(unsigned word=0;word<64;word++)for(unsigned bit=0;bit<32;bit++) {
      after=original;(node?&after.Parents[node-1]:&after.Gpu)->Config[word]^=1U<<bit;
      Check(GuDsIoMemStopTransition(&Before,&after)==GU_DS_STOP_REFUSED,"every unrelated config bit/cache mismatch refuses");
    }
    for(unsigned node=0;node<=p;node++)for(unsigned field=0;field<8;field++)for(unsigned bit=0;bit<64;bit++) {
      after=original;GU_DS_DEVICE *d=node?&after.Parents[node-1]:&after.Gpu;UINT64 delta=1ULL<<bit;
      switch(field) {
        case 0:d->Handle^=delta;break;case 1:d->Interface^=delta;break;case 2:d->Segment^=delta;break;
        case 3:d->Bus^=delta;break;case 4:d->Device^=delta;break;case 5:d->Function^=delta;break;
        case 6:d->Attributes^=delta;break;case 7:d->Supported^=delta;break;
      }
      Check(GuDsIoMemStopTransition(&Before,&after)==GU_DS_STOP_REFUSED,"every unrelated identity/cache/support/parent bit refuses");
    }
  }
  for(unsigned bad=0;bad<9;bad++) {
    IoMemSetup(&m,2,0,0);
    switch(bad) {
      case 0:Before.Gpu.Config[1]&=~1U;break;case 1:Before.Gpu.Attributes=GU_DS_MEMORY;break;
      case 2:Before.Gpu.Supported&=~GU_DS_IO;break;case 3:Before.Gpu.Supported&=~GU_DS_MEMORY;break;
      case 4:Before.Gpu.Config[1]|=4;break;case 5:Before.Complete=2;break;
      case 6:Before.ParentCount=0;break;case 7:Before.Gpu.Config[63]^=1;break;
      case 8:Before.Parents[0].Config[63]^=1;break;
    }
    IoMemRefuse(&m);
  }
  IoMemSetup(&m,2,0,0);Check(IoMemCollect(&m)==EFI_SUCCESS,"IO+MEM callback fault baseline");unsigned calls=m.Calls;
  for(unsigned at=1;at<=calls;at++) {
    for(unsigned warning=0;warning<2;warning++) {
      IoMemSetup(&m,2,0,0);m.FaultAt=at;m.FaultStatus=warning?EFI_WARN_UNKNOWN_GLYPH:EFI_DEVICE_ERROR;IoMemRefuse(&m);
    }
    IoMemSetup(&m,2,0,0);m.DropAt=at;IoMemRefuse(&m);
    for(unsigned mutation=6;mutation<=10;mutation++) {
      IoMemSetup(&m,2,0,0);m.Mutation=mutation;m.MutateAt=at;IoMemRefuse(&m);
    }
  }
  for(unsigned mutation=1;mutation<=5;mutation++) {
    IoMemSetup(&m,2,0,0);m.Mutation=mutation;m.MutateAt=1;IoMemRefuse(&m);
  }
  IoMemSetup(&m,2,0,0);m.Partial=1;IoMemRefuse(&m);
  IoMemSetup(&m,2,0,0);ReplaceAt=calls/2+1;IoMemRefuse(&m);
  IoMemSetup(&m,2,0,0);SwitchAt=calls/2+1;IoMemRefuse(&m);
  IoMemSetup(&m,2,0,0);FreezeBefore=FreezeTarget=TRUE;
  Check(IoMemCollect(&m)==EFI_SUCCESS && BeforeFrozen && Frozen,"IO+MEM origin and target frozen before callbacks");
  Check(GuDsIoMemStopTransition(&ExpectedBefore,&Capture.Snapshot)==GU_DS_STOP_DECODE_REDUCED,"frozen origin still revalidates");ReadOnly(&m);
  IoMemSetup(&m,2,0,3);Check(Collect(&m)!=EFI_SUCCESS,"ordinary capture still rejects coherent command3");
  IoMemSetup(&m,2,0,3);Check(GuDsEfiCaptureReleaseOrigin(&Capture,&m.Boot,&Target)==EFI_SUCCESS,"release-only baseline accepts coherent3");ReadOnly(&m);
  IoMemSetup(&m,2,0,3);m.Devices[0].State.Attributes=GU_DS_MEMORY;
  Check(GuDsEfiCaptureReleaseOrigin(&Capture,&m.Boot,&Target)!=EFI_SUCCESS && !Capture.Ready,"release baseline refuses raw3/cache200");
  IoMemSetup(&m,2,0,0);GU_DS_CAPTURE saved=Capture;
  Check(GuDsEfiCaptureIoMemAfterStop(&Capture,&m.Boot,&Target,NULL)==EFI_INVALID_PARAMETER && !memcmp(&saved,&Capture,sizeof(saved)) && !m.Calls,"IO+MEM NULL origin preserves storage");
  Check(GuDsEfiCaptureIoMemAfterStop(&Capture,&m.Boot,&Target,&Capture.Snapshot)==EFI_INVALID_PARAMETER && !memcmp(&saved,&Capture,sizeof(saved)) && !m.Calls,"IO+MEM aliased origin preserves storage");
  printf("PASS %u IO+MEM and legacy capture assertions; RAM only\n",Checks);return 0;
}
