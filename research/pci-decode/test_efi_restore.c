/* GPL-2.0-only. All EFIAPI functions below operate exclusively on host RAM. */
static void RestoreTick(void);
#define GU_DS_RESTORE_TEST
#define main adapter_fixture_main
#include "test_efi_adapter.c"
#undef main
#include "efi-capture.h"

static GU_DR_TRANSACTION RestoreTransaction;
static BOOLEAN RestoreReentry,InsideRestoreHook;
static unsigned EnableBehavior,RestoreSwitchAt;
static unsigned SwitchOnLog;
static BOOLEAN FreezeRestoreReport;
static VOID *RestoreBorrowed;
static GU_DS_SNAPSHOT ActualBefore,ActualAfter;
static GU_DS_RELEASE_PLAN ActualPlan;
static BOOLEAN FreezeReleasedInputs;
static unsigned ReleasedEnableBoundary;
static void RestoreTick(void) {
  if(RestoreReentry && !InsideRestoreHook) {
    InsideRestoreHook=TRUE;
    unsigned calls=M->Calls;GU_DR_TRANSACTION fresh={0};GU_DS_TRANSACTION old={0};
    GU_DS_EFI_CONTEXT context={0};
    Check(GuDsEfiRestoreRun(&M->Adapter,&RestoreTransaction)==GU_DR_REUSED,"restore current-context reentry refused");
    Check(GuDsEfiRestoreRun(&M->Adapter,&fresh)==GU_DR_REUSED && !fresh.Started,"restore fresh transaction reentry refused");
    Check(GuDsEfiRun(&M->Adapter,&old)==GU_DS_REUSED && !old.Started,"ordinary run cannot enter active restore");
    Check(GuDsEfiInitializeRestore(&context,&M->Boot,(EFI_HANDLE)&M->OwnerTag,M->Bindings,M->Count,&M->Expected,Log,M)==EFI_ALREADY_STARTED && !context.InitUsed,
      "fresh restore initializer cannot enter workspace");
    Check(GuDsEfiInitializeReleasedRestore(&context,&M->Boot,(EFI_HANDLE)&M->OwnerTag,M->Bindings,M->Count,
      &ActualBefore,&ActualAfter,&ActualPlan,Log,M)==EFI_ALREADY_STARTED && !context.InitUsed,
      "fresh released-origin initializer cannot enter workspace");
    context=M->Adapter;context.RunUsed=FALSE;context.Busy=FALSE;
    Check(GuDsEfiRestoreRun(&context,&fresh)==GU_DR_REUSED && !context.RunUsed && !fresh.Started,
      "fresh restore context cannot overwrite active workspace");
    Check(M->Calls==calls,"restore reentry makes no firmware callback");InsideRestoreHook=FALSE;
  }
  if(RestoreSwitchAt && M->Calls==RestoreSwitchAt) {
    M->Devices[0].State.Config[1]^=2;M->Devices[0].State.Attributes^=GU_DS_MEMORY;RestoreSwitchAt=0;
  }
}
static EFI_STATUS EFIAPI RestoreAttributes(EFI_PCI_IO_PROTOCOL *io,
  EFI_PCI_IO_PROTOCOL_ATTRIBUTE_OPERATION operation,UINT64 mask,UINT64 *out) {
  if(operation!=EfiPciIoAttributeOperationEnable)return Attributes(io,operation,mask,out);
  DEVICE *d=Device(io);
  Check(d==&M->Devices[0] && mask==GU_DS_MEMORY && !out,"only Enable(MEMORY) on pinned GPU");
  Check(RestoreTransaction.Started || FreezeRestoreReport,"transaction marked before Enable callback");
#ifdef GU_DS_HOST_WORKSPACE_TEST
  const GU_DR_TRANSACTION *active=GuDsTestAdapterWorkspace(5);
  Check(active->Started && active->EnableInvoked,"private invocation marker precedes Enable callback");
#endif
  Check(M->PoolLive==1 && M->LastOwnerQuery==M->Calls && M->LastFree<M->LastOwnerQuery,
    "final ownership buffer held with zero callbacks before Enable");
  Check(++M->Writes==1,"Enable is never retried");M->DisableAt=M->Calls+1;
  if(EnableBehavior!=1){d->State.Config[1]|=2;d->State.Attributes|=GU_DS_MEMORY;}
  if(EnableBehavior==2){d->State.Config[1]|=4;d->State.Attributes|=GU_DS_MASTER;}
  if(EnableBehavior==3)d->State.Attributes|=1ULL<<40;
  if(EnableBehavior==4)M->Devices[M->Count-1].State.Config[63]^=1;
  EFI_STATUS s=Tick();return s==EFI_SUCCESS?M->WriteStatus:s;
}
static EFI_STATUS EFIAPI RestoreOwners(EFI_HANDLE h,EFI_GUID *g,
  EFI_OPEN_PROTOCOL_INFORMATION_ENTRY **out,UINTN *count) {
  if(!RestoreBorrowed)return Owners(h,g,out,count);
  M->OwnerQueries++;M->LastOwnerQuery=M->Calls+1;EFI_STATUS s=Tick();
  *out=RestoreBorrowed;*count=1;return s;
}
static BOOLEAN RestoreLog(VOID *context,const char *event) {
  BOOLEAN result=Log(context,event);
  if(SwitchOnLog==M->Logs) {
    M->Devices[0].State.Config[1]^=2;M->Devices[0].State.Attributes^=GU_DS_MEMORY;
  }
  if(FreezeRestoreReport){RestoreTransaction=(GU_DR_TRANSACTION){0};M->Adapter.RestoreMode=FALSE;}
  if(FreezeReleasedInputs) {
    ActualBefore.Parents[0].Config[20]^=1;ActualAfter.Parents[0].Config[20]^=1;
    ActualPlan.RestoreMask|=GU_DS_MASTER;
    M->Adapter.ReleasedBefore.Parents[0].Config[20]^=1;
    M->Adapter.ReleasedAfter.Parents[0].Config[20]^=1;
    M->Adapter.ReleasePlan.RestoreMask|=GU_DS_MASTER;M->Adapter.ReleasedOrigin=FALSE;
  }
  return result;
}
static void RestoreSetup(MODEL *m,unsigned parents,UINTN segment,BOOLEAN off) {
  Setup(m,parents,segment);memset(&RestoreTransaction,0,sizeof(RestoreTransaction));
  RestoreReentry=InsideRestoreHook=FALSE;EnableBehavior=RestoreSwitchAt=0;
  SwitchOnLog=0;FreezeRestoreReport=FALSE;RestoreBorrowed=NULL;m->Boot.OpenProtocolInformation=RestoreOwners;
  FreezeReleasedInputs=FALSE;
  m->Expected.Gpu.Attributes=GU_DS_MEMORY;
  for(unsigned i=0;i<m->Count;i++)m->Devices[i].Io.Attributes=RestoreAttributes;
  m->Devices[0].State.Attributes=off?0:GU_DS_MEMORY;
  if(off)m->Devices[0].State.Config[1]&=~2U;
}
static EFI_STATUS RestoreInit(MODEL *m) {
  return GuDsEfiInitializeRestore(&m->Adapter,&m->Boot,(EFI_HANDLE)&m->OwnerTag,
    m->Bindings,m->Count,&m->Expected,RestoreLog,m);
}
static GU_DR_RESULT RestoreRun(MODEL *m) {return GuDsEfiRestoreRun(&m->Adapter,&RestoreTransaction);}
static void ReleasedSetup(MODEL *m,unsigned parents,UINTN segment) {
  RestoreSetup(m,parents,segment,TRUE);ActualBefore=m->Expected;ActualBefore.Gpu.Attributes|=GU_DS_IO;
  ActualAfter=m->Expected;ActualAfter.Gpu.Config[1]&=~2U;ActualAfter.Gpu.Attributes=0;
  Check(GuDsPlanReleasedMismatch(&ActualBefore,&ActualAfter,&ActualPlan),"released-origin fixture derives a separate plan");
}
static EFI_STATUS ReleasedInit(MODEL *m) {
  return GuDsEfiInitializeReleasedRestore(&m->Adapter,&m->Boot,(EFI_HANDLE)&m->OwnerTag,m->Bindings,m->Count,
    &ActualBefore,&ActualAfter,&ActualPlan,RestoreLog,m);
}
static void ReleasedRefuse(MODEL *m) {
  GU_DR_RESULT r=RestoreRun(m);unsigned calls=m->Calls;
  Check(r!=GU_DR_RESTORED && r!=GU_DR_UNCHANGED,"unsafe released-origin restoration refuses");
  if(RestoreTransaction.Started)Check(RestoreTransaction.ReleasedOrigin==TRUE,"failed released-origin report retains policy path");
  if((m->FaultAt && m->FaultAt<ReleasedEnableBoundary) || (m->DropAt && m->DropAt<ReleasedEnableBoundary))
    Check(!m->Writes,"pre-Enable released-origin callback failure cannot write");
  Check(m->Writes<=1 && !m->PoolLive,"released-origin failure has no retry or retained query buffer");
  Check(RestoreRun(m)==(RestoreTransaction.Started?GU_DR_REUSED:r) && m->Calls==calls,
    "released-origin refusal has no new callback on repeat");
  ReleasedSetup(m,2,0);Check(ReleasedInit(m)==EFI_SUCCESS,"fresh released-origin Init after failure");
  Check(RestoreRun(m)==GU_DR_RESTORED && RestoreTransaction.ReleasedOrigin,"fresh released-origin session after failure");
}
static void RestoreRefuse(MODEL *m) {
  GU_DR_RESULT r=RestoreRun(m);
  if(r==GU_DR_RESTORED || r==GU_DR_UNCHANGED)fprintf(stderr,
    "unexpected success: owner=%u fault=%u drop=%u mutation=%u at=%u\n",
    m->OwnerMode,m->FaultAt,m->DropAt,m->Mutation,m->MutateAt);
  Check(r!=GU_DR_RESTORED && r!=GU_DR_UNCHANGED,"unsafe restore refused");
  Check(m->Writes<=1 && !m->PoolLive,"restore failure leaves no owned query buffer or retry");
  unsigned calls=m->Calls;
  Check(RestoreRun(m)==GU_DR_REUSED && m->Calls==calls,"spent restore is never retried");
  RestoreSetup(m,2,0,TRUE);Check(RestoreInit(m)==EFI_SUCCESS,"fresh post-failure Init");
  Check(RestoreRun(m)==GU_DR_RESTORED,"fresh post-failure session releases workspace");
}
int main(void) {
  Check(adapter_fixture_main()==0,"ordinary adapter suite unchanged with restore opt-in");
  MODEL m;
  RestoreSetup(&m,3,0,TRUE);
  static GU_DS_CAPTURE post,restored;GU_DS_CAPTURE_TARGET target={0};
  target.Handle=m.Bindings[0].Handle;target.Segment=m.Expected.Gpu.Segment;target.Bus=m.Expected.Gpu.Bus;
  target.PciId=m.Expected.Gpu.Config[0];target.Subsystem=m.Expected.Gpu.Config[11];target.Bar0=m.Expected.Gpu.Config[4];
  target.PathBytes=m.Bindings[0].PathBytes;memcpy(target.Path,m.Bindings[0].Path,target.PathBytes);
  Check(GuDsEfiCaptureAfterStop(&post,&m.Boot,&target,&m.Expected)==EFI_SUCCESS,
    "actual read-only collector obtains memory-off observation");
  Check(GuDsEfiInitializeRestore(&m.Adapter,&m.Boot,(EFI_HANDLE)&m.OwnerTag,post.Bindings,post.Count,
    &m.Expected,RestoreLog,&m)==EFI_SUCCESS && RestoreRun(&m)==GU_DR_RESTORED,
    "captured bindings compose with held-claim MEMORY restore");
  Check(GuDsEfiCaptureAfterStop(&restored,&m.Boot,&target,&m.Expected)==EFI_SUCCESS &&
    GuDecodeSnapshotMatches(&restored.Snapshot,&m.Expected,FALSE) && m.Writes==1 && !m.PoolLive,
    "actual collector verifies restored baseline after the sole write");
  for(unsigned parents=1;parents<=15;parents++)for(unsigned s=0;s<3;s++)for(unsigned off=0;off<2;off++) {
    RestoreSetup(&m,parents,s==2?0xffff:s,(BOOLEAN)off);RestoreReentry=TRUE;
    Check(RestoreInit(&m)==EFI_SUCCESS,"bounded restore Init");
    GU_DS_TRANSACTION old={0};
    Check(GuDsEfiRun(&m.Adapter,&old)==GU_DS_INVALID && !old.Started && !m.Calls,"ordinary run refuses restore context");
    Check(RestoreRun(&m)==(off?GU_DR_RESTORED:GU_DR_UNCHANGED),"bounded MEMORY restoration or verified no-op");
    Check(m.Writes==off && RestoreTransaction.EnableInvoked==(BOOLEAN)off,"exact Enable invocation count");
    Check(!m.PoolLive && m.Adapter.RunUsed && RestoreTransaction.Started,"restore output and cleanup");
    Check(RestoreTransaction.EnableStatus==(off?EFI_SUCCESS:EFI_NOT_STARTED),"separate raw Enable status");
  }
  RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"fault baseline Init");
  Check(RestoreRun(&m)==GU_DR_RESTORED,"fault baseline run");unsigned calls=m.Calls,enable=m.DisableAt;
  UINT8 outputless[4096];memcpy(outputless,m.NoOutput,sizeof(outputless));
  for(unsigned at=1;at<=calls;at++) {
    for(unsigned warning=0;warning<3;warning++) {
      RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"fault Init");
      m.FaultAt=at;m.FaultStatus=warning==0?EFI_DEVICE_ERROR:warning==1?EFI_WARN_UNKNOWN_GLYPH:EFI_NOT_STARTED;
      RestoreRefuse(&m);
    }
    RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"missing output Init");m.DropAt=at;
    if(at!=enable && !outputless[at])RestoreRefuse(&m); /* Free/Enable have no output to omit. */
    for(unsigned mutation=6;mutation<=12;mutation++) {
      RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"method drift Init");m.Mutation=mutation;m.MutateAt=at;RestoreRefuse(&m);
    }
  }
  for(unsigned behavior=1;behavior<=4;behavior++) {
    RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"Enable effect fixture");EnableBehavior=behavior;RestoreRefuse(&m);
  }
  RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"post-Enable cleanup failure fixture");
  m.FaultAt=enable+1;m.FaultStatus=EFI_NOT_STARTED;
  Check(RestoreRun(&m)==GU_DR_OWNERSHIP_FAILED && RestoreTransaction.EnableInvoked &&
    RestoreTransaction.EnableStatus==EFI_SUCCESS && m.Adapter.CleanupObserved &&
    m.Adapter.CleanupStatus==EFI_NOT_STARTED && !RestoreTransaction.PostObserved && m.Calls==enable+1,
    "cleanup uncertainty preserves raw status and stops before more observations");
  for(unsigned status=0;status<3;status++) {
    RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"partial error fixture");
    m.WriteStatus=status==0?EFI_DEVICE_ERROR:status==1?EFI_WARN_UNKNOWN_GLYPH:EFI_NOT_STARTED;
    Check(RestoreRun(&m)==GU_DR_ENABLE_FAILED && RestoreTransaction.EnableInvoked &&
      RestoreTransaction.EnableStatus==m.WriteStatus && RestoreTransaction.PostObserved,
      "partial effect with matching readback never promotes Enable warning/error");
  }
  for(unsigned mode=1;mode<=34;mode++) {
    if(mode==11 || mode==20 || mode==22)continue;
    RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"ownership fixture");m.OwnerMode=mode;RestoreRefuse(&m);
  }
  for(unsigned log=1;log<=2;log++) {
    RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"log fail Init");m.LogFault=log;RestoreRefuse(&m);
    RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"log drift Init");m.LogDrift=log;RestoreRefuse(&m);
    RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"log claim loss Init");m.OwnerLogDrift=log;RestoreRefuse(&m);
  }
  for(unsigned off=0;off<2;off++)for(unsigned log=1;log<=2;log++) {
    RestoreSetup(&m,2,0,(BOOLEAN)off);Check(RestoreInit(&m)==EFI_SUCCESS,"MEM switch fixture");SwitchOnLog=log;RestoreRefuse(&m);
  }
  RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"report freeze fixture");FreezeRestoreReport=TRUE;
  Check(RestoreRun(&m)==GU_DR_RESTORED && RestoreTransaction.Started && RestoreTransaction.EnableInvoked,
    "callback edits cannot erase private report or restore mode");
#ifdef GU_DS_HOST_WORKSPACE_TEST
  for(unsigned index=0;index<8;index++)for(unsigned placement=0;placement<3;placement++) {
    RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"private pool alias fixture");
    const UINT8 *address=index==7?(const VOID *)&RestoreTransaction:GuDsTestAdapterWorkspace(index);
    /* ActiveOutput is set only by Run: obtain its pointer during Owners below. */
    if(index==4)continue;
    RestoreBorrowed=(VOID *)(placement==2?(UINTN)address-sizeof(UINTN):(UINTN)address+(placement?sizeof(UINTN):0));
    Check(RestoreRun(&m)!=GU_DR_RESTORED && !m.Writes && !m.Frees,"borrowed workspace/report pool alias is neither freed nor written");
  }
#endif
  RestoreSetup(&m,2,0,TRUE);Check(RestoreInit(&m)==EFI_SUCCESS,"frozen policy Init");m.Freeze=1;
  Check(RestoreRun(&m)==GU_DR_RESTORED,"caller policy edits cannot alter frozen restore");
  RestoreSetup(&m,2,0,TRUE);m.Expected.Gpu.Attributes|=GU_DS_IO;
  Check(RestoreInit(&m)==EFI_INVALID_PARAMETER && !m.Adapter.Ready && !m.Calls,"uncorrected baseline not eligible");
  RestoreSetup(&m,2,0,TRUE);m.Expected.Gpu.Supported&=~GU_DS_MEMORY;
  Check(RestoreInit(&m)==EFI_INVALID_PARAMETER && !m.Adapter.Ready && !m.Calls,"missing memory support not eligible");
  RestoreSetup(&m,2,0,TRUE);Check(Init(&m)==EFI_SUCCESS,"ordinary context Init");
  Check(RestoreRun(&m)==GU_DR_INVALID && !m.Calls,"restore cannot inherit ordinary context");
  RestoreSetup(&m,2,0,TRUE);EFI_PCI_IO_PROTOCOL savedIo=m.Devices[0].Io;
  Check(GuDsEfiInitializeRestore((VOID *)&m.Devices[0].Io,&m.Boot,(EFI_HANDLE)&m.OwnerTag,
    m.Bindings,m.Count,&m.Expected,RestoreLog,&m)==EFI_INVALID_PARAMETER &&
    !memcmp(&savedIo,&m.Devices[0].Io,sizeof(savedIo)) && !m.Calls,
    "Init context cannot alias a bound protocol");
  Check(RestoreInit(&m)==EFI_SUCCESS,"borrowed output fixture");
  Check(GuDsEfiRestoreRun(&m.Adapter,(VOID *)&m.Devices[0].Io)==GU_DR_INVALID &&
    !memcmp(&savedIo,&m.Devices[0].Io,sizeof(savedIo)) && !m.Calls,"report cannot alias a protocol");
  UINTN savedOwner=m.OwnerTag;
  Check(GuDsEfiRestoreRun(&m.Adapter,(VOID *)&m.OwnerTag)==GU_DR_INVALID && m.OwnerTag==savedOwner && !m.Calls,
    "report cannot alias owner handle storage");
  ReleasedSetup(&m,3,0);
  static GU_DS_CAPTURE releasedCapture,finalReleasedCapture;
  target.Handle=m.Bindings[0].Handle;target.Bus=m.Expected.Gpu.Bus;target.PathBytes=m.Bindings[0].PathBytes;
  memcpy(target.Path,m.Bindings[0].Path,target.PathBytes);
  Check(GuDsEfiCaptureReleasedMismatch(&releasedCapture,&m.Boot,&target,&ActualBefore)==EFI_SUCCESS,
    "actual collector obtains the hypothetical released-mismatch observation");
  unsigned capturedCalls=m.Calls;
  Check(GuDsEfiInitializeReleasedRestore(&m.Adapter,&m.Boot,(EFI_HANDLE)&m.OwnerTag,
    releasedCapture.Bindings,releasedCapture.Count,&ActualBefore,&releasedCapture.Snapshot,&ActualPlan,
    RestoreLog,&m)==EFI_SUCCESS && m.Calls==capturedCalls,"separate released-origin initializer accepts actual observations without callbacks");
  Check(m.Adapter.ReleasedBefore.Gpu.Attributes==0x300 && !m.Adapter.ReleasedAfter.Gpu.Attributes &&
    m.Adapter.Expected.Gpu.Attributes==0x200 && m.Adapter.ReleasedOrigin,
    "actual snapshots and planned target stay explicitly distinct");
  Check(RestoreRun(&m)==GU_DR_RESTORED && RestoreTransaction.ReleasedOrigin && m.Writes==1,
    "captured release and typed plan compose with held-claim restore");
  Check(GuDsEfiCapture(&finalReleasedCapture,&m.Boot,&target)==EFI_SUCCESS &&
    GuDecodeSnapshotMatches(&finalReleasedCapture.Snapshot,&m.Adapter.Expected,FALSE),
    "ordinary collector verifies the actual restored state without a manufactured before capture");
  for(unsigned parents=1;parents<=15;parents++)for(unsigned s=0;s<3;s++) {
    ReleasedSetup(&m,parents,s==2?0xffff:s);RestoreReentry=TRUE;
    Check(ReleasedInit(&m)==EFI_SUCCESS && !m.Calls,"released-origin Init is pure across bounded routes");
    Check(RestoreRun(&m)==GU_DR_RESTORED && RestoreTransaction.ReleasedOrigin && m.Writes==1 &&
      m.Adapter.ReleasedBefore.Gpu.Attributes==0x300 && !m.Adapter.ReleasedAfter.Gpu.Attributes,
      "bounded released-origin restore retains actual history");
  }
  ReleasedSetup(&m,2,0);Check(ReleasedInit(&m)==EFI_SUCCESS,"released-origin fault baseline Init");
  Check(RestoreRun(&m)==GU_DR_RESTORED,"released-origin fault baseline run");calls=m.Calls;enable=m.DisableAt;
  ReleasedEnableBoundary=enable;
  memcpy(outputless,m.NoOutput,sizeof(outputless));
  for(unsigned at=1;at<=calls;at++) {
    for(unsigned warning=0;warning<3;warning++) {
      ReleasedSetup(&m,2,0);Check(ReleasedInit(&m)==EFI_SUCCESS,"released-origin fault Init");
      m.FaultAt=at;m.FaultStatus=warning==0?EFI_DEVICE_ERROR:warning==1?EFI_WARN_UNKNOWN_GLYPH:EFI_NOT_STARTED;
      ReleasedRefuse(&m);
    }
    if(at!=enable && !outputless[at]) {
      ReleasedSetup(&m,2,0);Check(ReleasedInit(&m)==EFI_SUCCESS,"released-origin missing output Init");m.DropAt=at;ReleasedRefuse(&m);
    }
  }
  for(unsigned bad=0;bad<7;bad++) {
    ReleasedSetup(&m,2,0);
    switch(bad) {
      case 0:ActualBefore.Gpu.Attributes=GU_DS_MEMORY;break;
      case 1:ActualAfter.Gpu.Attributes=GU_DS_IO;break;
      case 2:ActualPlan.PlannedGpu.Config[63]^=1;break;
      case 3:ActualPlan.RestoreMask|=GU_DS_MASTER;break;
      case 4:ActualAfter.Parents[1].Config[63]^=1;break;
      case 5:ActualPlan.Ready=2;break;
      case 6:m.Bindings[1].Path[8]^=1;break;
    }
    Check(ReleasedInit(&m)!=EFI_SUCCESS && !m.Adapter.Ready && !m.Calls,"invalid released-origin Init stays unusable and pure");
    Check(RestoreRun(&m)==GU_DR_INVALID && !m.Calls,"failed released-origin Init cannot be run");
    GU_DS_TRANSACTION ordinary={0};
    Check(GuDsEfiRun(&m.Adapter,&ordinary)==GU_DS_INVALID && !m.Calls,"partial released Init cannot enter ordinary Run");
  }
  for(unsigned status=0;status<3;status++) {
    ReleasedSetup(&m,2,0);Check(ReleasedInit(&m)==EFI_SUCCESS,"released partial-effect fixture");
    m.WriteStatus=status==0?EFI_DEVICE_ERROR:status==1?EFI_WARN_UNKNOWN_GLYPH:EFI_NOT_STARTED;
    Check(RestoreRun(&m)==GU_DR_ENABLE_FAILED && RestoreTransaction.ReleasedOrigin &&
      RestoreTransaction.EnableInvoked && RestoreTransaction.EnableStatus==m.WriteStatus && RestoreTransaction.PostObserved,
      "released origin preserves failed Enable even with matching post-observation");
  }
  ReleasedSetup(&m,2,0);Check(ReleasedInit(&m)==EFI_SUCCESS,"released cleanup uncertainty fixture");
  m.FaultAt=enable+1;m.FaultStatus=EFI_NOT_STARTED;
  Check(RestoreRun(&m)==GU_DR_OWNERSHIP_FAILED && RestoreTransaction.ReleasedOrigin &&
    RestoreTransaction.EnableStatus==EFI_SUCCESS && m.Adapter.CleanupStatus==EFI_NOT_STARTED && m.Calls==enable+1,
    "released cleanup failure stops without further callbacks");
  for(unsigned changed=0;changed<6;changed++) {
    ReleasedSetup(&m,2,0);Check(ReleasedInit(&m)==EFI_SUCCESS,"released-origin history pin Init");
    switch(changed) {
      case 0:m.Adapter.ReleasedBefore.Parents[0].Config[20]^=1;m.Adapter.ReleasedAfter.Parents[0].Config[20]^=1;break;
      case 1:m.Devices[0].State.Config[1]|=2;m.Devices[0].State.Attributes=GU_DS_MEMORY;break;
      case 2:m.Devices[2].State.Config[20]^=1;break;
      case 3:m.Adapter.ReleasedOrigin=2;break;
      case 4:m.Adapter.ReleasePlan.PlannedGpu.Config[63]^=1;break;
      case 5:m.Adapter.ReleasedOrigin=FALSE;break;
    }
    ReleasedRefuse(&m);
  }
  ReleasedSetup(&m,2,0);Check(ReleasedInit(&m)==EFI_SUCCESS,"released-origin frozen original fixture");
  ActualBefore.Parents[0].Config[20]^=1;ActualAfter.Parents[0].Config[20]^=1;ActualPlan.RestoreMask|=GU_DS_MASTER;
  FreezeReleasedInputs=FreezeRestoreReport=TRUE;m.Freeze=1;
  Check(RestoreRun(&m)==GU_DR_RESTORED && RestoreTransaction.ReleasedOrigin && RestoreTransaction.EnableInvoked,
    "frozen originals and origin/report survive caller input and callback context edits");
#ifdef GU_DS_HOST_WORKSPACE_TEST
  for(unsigned index=0;index<6;index++)for(unsigned placement=0;placement<3;placement++) {
    ReleasedSetup(&m,2,0);Check(ReleasedInit(&m)==EFI_SUCCESS,"released-origin pool alias fixture");
    const UINT8 *address=index<3?GuDsTestAdapterWorkspace(7+index):
      index==3?(const VOID *)&ActualBefore:index==4?(const VOID *)&ActualAfter:(const VOID *)&ActualPlan;
    RestoreBorrowed=(VOID *)(placement==2?(UINTN)address-sizeof(UINTN):(UINTN)address+(placement?sizeof(UINTN):0));
    Check(RestoreRun(&m)!=GU_DR_RESTORED && !m.Writes && !m.Frees,"actual history and plan buffers are not freed or written");
  }
#endif
  ReleasedSetup(&m,2,0);GU_DS_SNAPSHOT savedAfter=ActualAfter;GU_DS_RELEASE_PLAN savedPlan=ActualPlan;
  Check(GuDsEfiInitializeReleasedRestore((VOID *)&ActualAfter,&m.Boot,(EFI_HANDLE)&m.OwnerTag,
    m.Bindings,m.Count,&ActualBefore,&ActualAfter,&ActualPlan,RestoreLog,&m)==EFI_INVALID_PARAMETER &&
    !memcmp(&ActualAfter,&savedAfter,sizeof(savedAfter)) && !m.Calls,"context cannot overwrite actual After input");
  Check(GuDsEfiInitializeReleasedRestore(&m.Adapter,&m.Boot,(EFI_HANDLE)&m.OwnerTag,
    m.Bindings,m.Count,&ActualBefore,&ActualAfter,(VOID *)&m.Adapter,RestoreLog,&m)==EFI_INVALID_PARAMETER &&
    !m.Adapter.InitUsed && !m.Calls,"plan/context overlap preserves untouched context");
  Check(ReleasedInit(&m)==EFI_SUCCESS,"released report overlap fixture");
  Check(GuDsEfiRestoreRun(&m.Adapter,(VOID *)&ActualAfter)==GU_DR_INVALID &&
    !memcmp(&ActualAfter,&savedAfter,sizeof(savedAfter)) && !m.Calls,"report cannot overwrite actual After input");
  Check(GuDsEfiRestoreRun(&m.Adapter,(VOID *)&ActualPlan)==GU_DR_INVALID &&
    !memcmp(&ActualPlan,&savedPlan,sizeof(savedPlan)) && !m.Calls,"report cannot overwrite original Plan");
  printf("PASS %u restore/ordinary assertions; RAM only\n",Checks);return 0;
}
