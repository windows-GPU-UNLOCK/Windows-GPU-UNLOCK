/* GPL-2.0-only. Claim lifecycle, real EFIAPI types, all effects in RAM. */
static void OwnedTick(void);
#define GU_DS_OWNED_TEST
#include "test_efi_capture.c"
#include "efi-owned.h"

static GU_DO_TRANSACTION Owned;
static BOOLEAN Claimed,ReenterOwned,FreezeOwned,CheckingReentry;
static unsigned OpenCalls,CloseCalls,OwnedMode,AfterClose,ReadAtClose;
static void OwnedTick(void) {
  if(OwnedMode==26 && AfterClose && M->Reads>ReadAtClose)Claimed=TRUE;
  if(ReenterOwned && !CheckingReentry) {
    CheckingReentry=TRUE;
    unsigned calls=M->Calls;
    GU_DO_TRANSACTION fresh={0};
    Check(GuDsOwnedRun(&Owned,&M->Boot,(EFI_HANDLE)&M->OwnerTag,&Target,Log,M)==GU_DO_REUSED,"current owned transaction cannot reenter");
    Check(GuDsOwnedRun(&fresh,&M->Boot,(EFI_HANDLE)&M->OwnerTag,&Target,Log,M)==GU_DO_REUSED && !fresh.Started,"fresh transaction cannot reenter shared claim workspace");
    Check(M->Calls==calls,"reentry calls no service");
    CheckingReentry=FALSE;
  }
  if(FreezeOwned && !Frozen){Frozen=TRUE;Target.PciId^=1;Target.Path[8]^=1;Target.Bus^=1;Owned.Started=FALSE;}
}
static EFI_STATUS EFIAPI OwnedOwners(EFI_HANDLE h,EFI_GUID *g,EFI_OPEN_PROTOCOL_INFORMATION_ENTRY **out,UINTN *count) {
  Check(h==Target.Handle && !memcmp(g,&PciGuid,sizeof(*g)),"only pinned GPU opener list");
  M->OwnerQueries++;M->LastOwnerQuery=M->Calls+1;
  EFI_STATUS status=Tick();if(M->DropAt==M->Calls)return status;
  if(OwnedMode==13 && !OpenCalls){*count=1;*out=(VOID *)&Owned;return status;}
  if(OwnedMode==14 && !OpenCalls){*count=1;*out=(VOID *)((UINTN)&Owned+1);return status;}
  if(OwnedMode==15 && !OpenCalls){*count=65;*out=NULL;return status;}
  if(OwnedMode==16 && !Claimed){*count=0;*out=NULL;return status;}
  if((OwnedMode==32 && !OpenCalls) || (OwnedMode==40 && OpenCalls && !AfterClose)){*count=1;*out=NULL;return status;}
  Check(!M->PoolLive && !M->Pool,"one opener allocation at a time");
  UINTN n=OwnedMode==27?(Claimed?64:63):OwnedMode==28?64:OwnedMode==16?1:Claimed?2:1;
  M->Pool=calloc(n,sizeof(*M->Pool));Check(M->Pool!=NULL,"mock owner allocation");M->PoolLive++;
  *count=n;*out=M->Pool;
  if(OwnedMode!=16)M->Pool[0]=(EFI_OPEN_PROTOCOL_INFORMATION_ENTRY){(EFI_HANDLE)&M->Devices[1].Tag,NULL,EFI_OPEN_PROTOCOL_GET_PROTOCOL,1};
  if(Claimed)M->Pool[OwnedMode==16?0:1]=(EFI_OPEN_PROTOCOL_INFORMATION_ENTRY){(EFI_HANDLE)&M->OwnerTag,NULL,EFI_OPEN_PROTOCOL_EXCLUSIVE,1};
  if(OwnedMode==27 || OwnedMode==28) {
    for(UINTN i=0;i<n-(Claimed?1:0);i++)M->Pool[i]=(EFI_OPEN_PROTOCOL_INFORMATION_ENTRY){(EFI_HANDLE)(UINTN)(0x10000+i*16),NULL,2,1};
    if(Claimed)M->Pool[n-1]=(EFI_OPEN_PROTOCOL_INFORMATION_ENTRY){(EFI_HANDLE)&M->OwnerTag,NULL,EFI_OPEN_PROTOCOL_EXCLUSIVE,1};
  }
  if(!OpenCalls && OwnedMode>=1 && OwnedMode<=7) {
    M->Pool[0].Attributes=OwnedMode==1?EFI_OPEN_PROTOCOL_BY_DRIVER:OwnedMode==2?EFI_OPEN_PROTOCOL_BY_CHILD_CONTROLLER:
      OwnedMode==3?EFI_OPEN_PROTOCOL_EXCLUSIVE:OwnedMode==4?(EFI_OPEN_PROTOCOL_BY_DRIVER|EFI_OPEN_PROTOCOL_EXCLUSIVE):OwnedMode==5?3:OwnedMode==6?0x40:EFI_OPEN_PROTOCOL_GET_PROTOCOL;
    if(OwnedMode==7)M->Pool[0].AgentHandle=(EFI_HANDLE)&M->OwnerTag;
  }
  if(!OpenCalls && OwnedMode==8)M->Pool[0].OpenCount=0;
  if(!OpenCalls && OwnedMode==29)*count=0;
  if(!OpenCalls && OwnedMode==30)*count=65;
  if(AfterClose && OwnedMode==25)M->Pool[0].OpenCount++;
  return OwnedMode==33 && !OpenCalls?EFI_NOT_STARTED:status;
}
static EFI_STATUS EFIAPI OwnedOpen(EFI_HANDLE h,EFI_GUID *g,VOID **out,EFI_HANDLE agent,EFI_HANDLE controller,UINT32 attrs) {
  Check(h==(EFI_HANDLE)&M->Devices[0].Tag && !memcmp(g,&PciGuid,sizeof(*g)) && agent==(EFI_HANDLE)&M->OwnerTag && !controller && attrs==EFI_OPEN_PROTOCOL_EXCLUSIVE,"one exact application exclusive claim");
  Check(!Claimed && ++OpenCalls==1,"claim is not a retry or existing self reference");
  Check(M->PoolLive==(OwnedMode==16?0U:1U) && M->LastOwnerQuery==M->Calls,"no callback between passive view and Open");
  EFI_STATUS s=Tick();
  if(s!=EFI_SUCCESS)return s;
  Claimed=TRUE;*out=&M->Devices[0].Io;
  if(OwnedMode==9)*out=NULL;
  if(OwnedMode==10)*out=&M->Devices[1].Io;
  if(OwnedMode==11)return EFI_WARN_UNKNOWN_GLYPH;
  if(OwnedMode==12)return EFI_DEVICE_ERROR;
  if(OwnedMode==35)return EFI_NOT_STARTED;
  if(OwnedMode==40)return EFI_DEVICE_ERROR;
  if(OwnedMode==17)M->Devices[M->Count-1].State.Config[63]^=1;
  if(OwnedMode==18)M->Devices[M->Count-1].Io.Attributes=NULL;
  if(OwnedMode==19)M->Boot.CloseProtocol=NULL;
  return s;
}
static EFI_STATUS EFIAPI OwnedClose(EFI_HANDLE h,EFI_GUID *g,EFI_HANDLE agent,EFI_HANDLE controller) {
  Check(h==(EFI_HANDLE)&M->Devices[0].Tag && !memcmp(g,&PciGuid,sizeof(*g)) && agent==(EFI_HANDLE)&M->OwnerTag && !controller,"close only our exact GPU tuple");
  Check(++CloseCalls==1,"close never retries");
  EFI_STATUS s=Tick();AfterClose=1;ReadAtClose=M->Reads;
  if(OwnedMode!=23 && OwnedMode!=38)Claimed=FALSE;
  if(OwnedMode==20)return EFI_WARN_UNKNOWN_GLYPH;
  if(OwnedMode==21)return EFI_DEVICE_ERROR;
  if(OwnedMode==22)return EFI_NOT_STARTED;
  if(OwnedMode==38)return EFI_DEVICE_ERROR;
  if(OwnedMode==24)M->Devices[M->Count-1].State.Config[63]^=1;
  return s;
}
static EFI_STATUS EFIAPI OwnedAttributes(EFI_PCI_IO_PROTOCOL *p,EFI_PCI_IO_PROTOCOL_ATTRIBUTE_OPERATION op,UINT64 mask,UINT64 *out) {
  if(op!=EfiPciIoAttributeOperationDisable)return CaptureAttributes(p,op,mask,out);
  Check(p==&M->Devices[0].Io && Claimed && mask==GU_DS_IO && !out,"only claimed GPU Disable(IO), no enable/BME/MMIO");
  Check(!M->Writes && M->PoolLive==1 && M->LastOwnerQuery==M->Calls,"single write holds final ownership query buffer");
  M->Writes++;M->DisableAt=M->Calls+1;M->Devices[0].State.Attributes&=~GU_DS_IO;
  EFI_STATUS s=Tick();return s==EFI_SUCCESS?M->WriteStatus:s;
}
static EFI_STATUS EFIAPI OwnedFree(VOID *p) {
  EFI_STATUS status=Free(p);return OwnedMode==34?EFI_NOT_STARTED:status;
}
static void OwnedSetup(MODEL *m,unsigned parents,UINTN segment,unsigned mode) {
  CaptureSetup(m,parents,segment);memset(&Owned,0,sizeof(Owned));
  Claimed=ReenterOwned=FreezeOwned=CheckingReentry=FALSE;OpenCalls=CloseCalls=AfterClose=ReadAtClose=0;OwnedMode=mode;
  m->Boot.OpenProtocolInformation=OwnedOwners;m->Boot.OpenProtocol=OwnedOpen;m->Boot.CloseProtocol=OwnedClose;
  m->Boot.FreePool=OwnedFree;
  if(mode==37)m->WriteStatus=EFI_NOT_STARTED;
  for(unsigned i=0;i<m->Count;i++)m->Devices[i].Io.Attributes=OwnedAttributes;
}
static GU_DO_RESULT OwnedRun(void) {return GuDsOwnedRun(&Owned,&M->Boot,(EFI_HANDLE)&M->OwnerTag,&Target,Log,M);}
static void Bounds(void) {
  Check(OpenCalls<=1 && CloseCalls<=1 && M->Writes<=1 && !M->PoolLive,"at most one claim/close/write and no query pool leak");
  unsigned calls=M->Calls;GU_DO_RESULT again=OwnedRun();
  Check(again==GU_DO_REUSED && M->Calls==calls,"completed transaction cannot repeat");
}
int main(void) {
  MODEL m;
  for(unsigned parents=1;parents<=15;parents++)for(unsigned segment=0;segment<3;segment++) {
    OwnedSetup(&m,parents,segment==2?0xffff:segment,0);ReenterOwned=TRUE;
    Check(OwnedRun()==GU_DO_FIXED,"capture/claim/actual adapter/close/postcheck compose");
    Check(Owned.OpenInvoked && Owned.OpenSucceeded && Owned.ClaimObserved && Owned.CloseInvoked &&
      !Owned.ClaimMayRemain && Owned.DisableInvoked && Owned.AfterObserved && !Claimed,"complete claim lifecycle recorded separately");Bounds();
    Check(Owned.AdapterOwnershipObserved && Owned.AdapterCleanupObserved && Owned.AdapterOwnershipStatus==EFI_SUCCESS &&
      Owned.AdapterCleanupStatus==EFI_SUCCESS && Owned.DisableIoStatus==EFI_SUCCESS,"raw adapter statuses retained separately");
  }
  OwnedSetup(&m,1,0,0);Check(OwnedRun()==GU_DO_FIXED,"baseline");unsigned calls=m.Calls;
  for(unsigned at=1;at<=calls;at++)for(unsigned warning=0;warning<2;warning++) {
    OwnedSetup(&m,1,0,0);m.FaultAt=at;m.FaultStatus=warning?EFI_WARN_UNKNOWN_GLYPH:EFI_DEVICE_ERROR;
    GU_DO_RESULT result=OwnedRun();
    Check(result!=GU_DO_FIXED && result!=GU_DO_ALREADY_CONSISTENT,"every service warning/error prevents successful lifecycle");Bounds();
  }
  for(unsigned mode=1;mode<=26;mode++) {
    OwnedSetup(&m,1,0,mode);GU_DO_RESULT result=OwnedRun();
    if(mode==16)Check(result==GU_DO_FIXED,"canonical empty passive view is supported");
    else Check(result!=GU_DO_FIXED && result!=GU_DO_ALREADY_CONSISTENT,"managing/borrowed/partial/close/state failure refuses");
    if(mode<=8 || mode==13 || mode==14 || mode==15)Check(!OpenCalls && !m.Writes,"unsafe preclaim view never calls EXCLUSIVE");
    if(mode==11 || mode==12)Check(CloseCalls==1 && !Claimed && !m.Writes,"error with precise self claim cleaned without promotion");
    if(mode>=20 && mode<=22)Check(Owned.CloseStatus==(mode==20?EFI_WARN_UNKNOWN_GLYPH:mode==21?EFI_DEVICE_ERROR:EFI_NOT_STARTED),"real Close status is never overwritten as a sentinel");
    if(mode==26)Check(Owned.Result==GU_DO_VERIFY_FAILED && Owned.ClaimMayRemain && Claimed,"post-close capture cannot hide a recreated self claim");
    Bounds();
  }
  const unsigned extra[]={27,28,29,30,32,33,34,35,37,38,40};
  for(unsigned i=0;i<sizeof(extra)/sizeof(extra[0]);i++) {
    unsigned mode=extra[i];OwnedSetup(&m,1,0,mode);GU_DO_RESULT result=OwnedRun();
    if(mode==27)Check(result==GU_DO_FIXED,"63 passive records leave room for the owned adapter's self record");
    else Check(result!=GU_DO_FIXED && result!=GU_DO_ALREADY_CONSISTENT,"boundary/missing/status ambiguity refuses success");
    if(mode==28 || mode==29 || mode==30 || mode==32 || mode==33 || mode==34)Check(!OpenCalls && !m.Writes,"bad query/cleanup status never requests exclusive access");
    if(mode==33)Check(Owned.OwnershipObserved && Owned.OwnershipStatus==EFI_NOT_STARTED,"real query NOT_STARTED is retained with observed flag");
    if(mode==34)Check(Owned.CleanupObserved && Owned.CleanupStatus==EFI_NOT_STARTED,"real cleanup NOT_STARTED is retained with observed flag");
    if(mode==35)Check(Owned.OpenInvoked && !Owned.OpenSucceeded && Owned.OpenStatus==EFI_NOT_STARTED && CloseCalls==1,"real Open NOT_STARTED with observable claim is cleaned without promotion");
    if(mode==37)Check(Owned.DisableInvoked && Owned.DisableIoStatus==EFI_NOT_STARTED && Owned.AdapterResult==GU_DS_DISABLE_FAILED,"adapter raw write failure survives lifecycle cleanup");
    if(mode==38)Check(Owned.ClaimMayRemain && Claimed && Owned.CloseStatus==EFI_DEVICE_ERROR,"failed Close with remaining claim is uncertain and never retried");
    if(mode==40)Check(Owned.OpenInvoked && !Owned.CloseInvoked && Owned.ClaimMayRemain && Claimed,"unobservable error-side claim is not misattributed or declared cleaned");
    Bounds();
  }
  OwnedSetup(&m,1,0,0);m.Devices[0].State.Attributes=GU_DS_MEMORY;
  Check(OwnedRun()==GU_DO_ALREADY_CONSISTENT && !OpenCalls && !CloseCalls && !m.Writes,"consistent snapshot has no claim or correction");Bounds();
  for(unsigned command=0;command<8;command++)if(command!=2) {
    OwnedSetup(&m,1,0,0);m.Devices[0].State.Config[1]=command;
    Check(OwnedRun()==GU_DO_CAPTURE_FAILED && !OpenCalls && !m.Writes,"MEM-off/BME/unqualified command never acquires claim");Bounds();
  }
  OwnedSetup(&m,1,0,0);FreezeOwned=TRUE;
  Check(OwnedRun()==GU_DO_FIXED && Owned.Started,"caller policy/transaction edits cannot change private in-flight copy");Bounds();
  printf("PASS %u owned lifecycle assertions; all protocol effects simulated in RAM\n",Checks);return 0;
}
