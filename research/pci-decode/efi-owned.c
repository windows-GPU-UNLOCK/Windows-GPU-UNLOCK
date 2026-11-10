/* GPL-2.0-only. No direct Stop/Disconnect/enable/reset/chainload capability.
 * OpenProtocol(EXCLUSIVE) has implicit disconnect semantics under UEFI; this
 * caller is only for a serialized, trusted, already-unmanaged controller. */
#include "efi-owned.h"

typedef struct {
  GU_DO_TRANSACTION Report;
  GU_DO_TRANSACTION *Caller;
  const GU_DS_CAPTURE_TARGET *Input;
  GU_DS_CAPTURE_TARGET Target;
  EFI_BOOT_SERVICES *Boot;
  EFI_HANDLE Owner;
  EFI_HANDLE_PROTOCOL Handle;
  EFI_LOCATE_DEVICE_PATH Locate;
  EFI_OPEN_PROTOCOL_INFORMATION Owners;
  EFI_OPEN_PROTOCOL Open;
  EFI_CLOSE_PROTOCOL Close;
  EFI_FREE_POOL Free;
  BOOLEAN (*Log)(VOID *,const char *);
  VOID *LogContext;
  GU_DS_CAPTURE Before,Fresh,After;
  GU_DS_EFI_CONTEXT Adapter;
  GU_DS_TRANSACTION Core;
  EFI_OPEN_PROTOCOL_INFORMATION_ENTRY Passive[GU_DS_EFI_MAX_OPENERS];
  UINTN PassiveCount;
} WORK;
static WORK Active;
static BOOLEAN Busy;
static EFI_GUID PciGuid=EFI_PCI_IO_PROTOCOL_GUID;
static BOOLEAN Overlap(const VOID *a,UINTN an,const VOID *b,UINTN bn) {
  UINTN x=(UINTN)a,y=(UINTN)b;return x<=y?y-x<an:x-y<bn;
}
static BOOLEAN Caps(WORK *w) {
  if(w->Boot->HandleProtocol!=w->Handle || w->Boot->LocateDevicePath!=w->Locate ||
     w->Boot->OpenProtocolInformation!=w->Owners || w->Boot->OpenProtocol!=w->Open ||
     w->Boot->CloseProtocol!=w->Close || w->Boot->FreePool!=w->Free)return FALSE;
  if(w->Adapter.Ready)for(UINTN i=0;i<1+w->Adapter.Expected.ParentCount;i++) {
    const GU_DS_EFI_DEVICE *d=&w->Adapter.Devices[i];
    if(d->Pin.Io->Pci.Read!=d->Read || d->Pin.Io->GetLocation!=d->Location || d->Pin.Io->Attributes!=d->Attributes)return FALSE;
  }
  return TRUE;
}
static EFI_STATUS OwnerStatus(WORK *w,EFI_STATUS s) {
  if(!w->Report.OwnershipObserved || w->Report.OwnershipStatus==EFI_SUCCESS)w->Report.OwnershipStatus=s;
  w->Report.OwnershipObserved=TRUE;return s;
}
static BOOLEAN PoolRange(WORK *w,const VOID *p,UINTN count) {
  UINTN n=count && count<=GU_DS_EFI_MAX_OPENERS?count*sizeof(EFI_OPEN_PROTOCOL_INFORMATION_ENTRY):sizeof(EFI_OPEN_PROTOCOL_INFORMATION_ENTRY);
  if((UINTN)p%sizeof(UINTN) || (UINTN)p>~(UINTN)0-n || Overlap(p,n,w,sizeof(*w)) ||
     Overlap(p,n,w->Caller,sizeof(*w->Caller)) || Overlap(p,n,w->Input,sizeof(*w->Input)) ||
     Overlap(p,n,w->Boot,sizeof(*w->Boot)) || Overlap(p,n,w->Owner,1))return FALSE;
  for(UINTN i=0;i<w->Before.Count;i++)if(Overlap(p,n,w->Before.Bindings[i].Io,sizeof(EFI_PCI_IO_PROTOCOL)) ||
      Overlap(p,n,w->Before.Bindings[i].Handle,1))return FALSE;
  return TRUE;
}
static EFI_STATUS Drop(WORK *w,EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *p) {
  if(!p)return EFI_SUCCESS;
  EFI_STATUS s=w->Free(p);
  if(!w->Report.CleanupObserved || w->Report.CleanupStatus==EFI_SUCCESS)w->Report.CleanupStatus=s;
  w->Report.CleanupObserved=TRUE;
  return s==EFI_SUCCESS && Caps(w)?EFI_SUCCESS:s==EFI_SUCCESS?EFI_NOT_READY:s;
}
static BOOLEAN Key(const EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *a,const EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *b) {
  return a->AgentHandle==b->AgentHandle && a->ControllerHandle==b->ControllerHandle && a->Attributes==b->Attributes;
}
/* phase0 records passives; phase1 requires identical passives without a claim;
 * phase2 requires identical passives plus exactly our fresh exclusive claim. */
static EFI_STATUS View(WORK *w,UINTN phase,BOOLEAN keep,EFI_OPEN_PROTOCOL_INFORMATION_ENTRY **held) {
  *held=NULL;if(!Caps(w))return OwnerStatus(w,EFI_NOT_READY);
  EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *p=NULL;UINTN count=~(UINTN)0;
  EFI_STATUS s=w->Owners(w->Target.Handle,&PciGuid,&p,&count);
  if(p && !PoolRange(w,p,count))return OwnerStatus(w,EFI_COMPROMISED_DATA);
  BOOLEAN valid=s==EFI_SUCCESS && Caps(w) && count<=GU_DS_EFI_MAX_OPENERS && (count?p!=NULL:p==NULL);
  UINTN own=0,passives=0;
  if(valid)for(UINTN i=0;i<count;i++) {
    const EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *e=&p[i];
    if(!e->AgentHandle || !e->OpenCount){valid=FALSE;break;}
    for(UINTN j=0;j<i;j++)if(Key(e,&p[j]))valid=FALSE;
    if(!valid)break;
    if(e->AgentHandle==w->Owner) {
      if(phase!=2 || e->ControllerHandle || e->Attributes!=EFI_OPEN_PROTOCOL_EXCLUSIVE || e->OpenCount!=1){valid=FALSE;break;}
      own++;continue;
    }
    if(e->Attributes!=1 && e->Attributes!=2 && e->Attributes!=4){valid=FALSE;break;}
    if(!phase)w->Passive[passives]=*e;
    else {
      UINTN matches=0;
      for(UINTN j=0;j<w->PassiveCount;j++)if(Key(e,&w->Passive[j]) && e->OpenCount==w->Passive[j].OpenCount)matches++;
      if(matches!=1){valid=FALSE;break;}
    }
    passives++;
  }
  if(!phase) {
    if(passives>=GU_DS_EFI_MAX_OPENERS)valid=FALSE; /* leave room for self claim */
    if(valid)w->PassiveCount=passives;
  } else if(passives!=w->PassiveCount)valid=FALSE;
  if(own!=(phase==2?1U:0U))valid=FALSE;
  EFI_STATUS result=s!=EFI_SUCCESS?s:valid?EFI_SUCCESS:EFI_ACCESS_DENIED;
  if(result==EFI_SUCCESS && keep)*held=p;
  else {EFI_STATUS freeStatus=Drop(w,p);if(result==EFI_SUCCESS)result=freeStatus;}
  return OwnerStatus(w,result);
}
static EFI_STATUS Capture(WORK *w,GU_DS_CAPTURE *capture,BOOLEAN fixed) {
  if(!Caps(w))return EFI_NOT_READY;
  EFI_STATUS s=GuDsEfiCapture(capture,w->Boot,&w->Target);
  if(s==EFI_SUCCESS && (!Caps(w) || !GuDecodeSnapshotMatches(&capture->Snapshot,&w->Before.Snapshot,fixed)))s=EFI_NOT_READY;
  return s;
}
static BOOLEAN Log(WORK *w,const char *event) {return Caps(w) && w->Log(w->LogContext,event)==TRUE && Caps(w);}
static GU_DO_RESULT Run(WORK *w) {
  GU_DO_TRANSACTION *r=&w->Report;
  r->CaptureStatus=GuDsEfiCapture(&w->Before,w->Boot,&w->Target);
  if(r->CaptureStatus!=EFI_SUCCESS || !Caps(w))return GU_DO_CAPTURE_FAILED;
  EFI_STATUS s=GuDsEfiInitialize(&w->Adapter,w->Boot,w->Owner,w->Before.Bindings,w->Before.Count,
    &w->Before.Snapshot,w->Log,w->LogContext);
  if(s!=EFI_SUCCESS)return GU_DO_INVALID;
  if(w->Before.Snapshot.Gpu.Attributes==GU_DS_MEMORY) {
    if(!Log(w,"owned-decode-already-consistent"))return GU_DO_LOG_FAILED;
    r->CaptureStatus=Capture(w,&w->Fresh,FALSE);
    return r->CaptureStatus==EFI_SUCCESS?GU_DO_ALREADY_CONSISTENT:GU_DO_CAPTURE_FAILED;
  }
  EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *held=NULL;
  if(View(w,0,FALSE,&held)!=EFI_SUCCESS)return GU_DO_OWNERSHIP_REFUSED;
  if(!Log(w,"owned-decode-exclusive-intent"))return GU_DO_LOG_FAILED;
  r->CaptureStatus=Capture(w,&w->Fresh,FALSE);
  if(r->CaptureStatus!=EFI_SUCCESS)return GU_DO_CAPTURE_FAILED;
  if(View(w,1,TRUE,&held)!=EFI_SUCCESS)return GU_DO_OWNERSHIP_REFUSED;
  /* No log/free/read callback between the final passive view and Open. */
  EFI_PCI_IO_PROTOCOL *io=NULL;
  if(!Caps(w)){Drop(w,held);return GU_DO_OWNERSHIP_REFUSED;}
  r->OpenInvoked=TRUE;r->ClaimMayRemain=TRUE;
  r->OpenStatus=w->Open(w->Target.Handle,&PciGuid,(VOID **)&io,w->Owner,NULL,EFI_OPEN_PROTOCOL_EXCLUSIVE);
  r->OpenSucceeded=r->OpenStatus==EFI_SUCCESS;
  EFI_STATUS freeStatus=Drop(w,held);held=NULL;
  s=View(w,2,FALSE,&held);
  r->ClaimObserved=s==EFI_SUCCESS;
  /* An undefined warning/error may have acquired a claim. Clean up only when
   * success or a precise post-view attributes it to this serialized caller. */
  GU_DO_RESULT result=GU_DO_OPEN_FAILED;
  if(r->OpenSucceeded && freeStatus==EFI_SUCCESS && s==EFI_SUCCESS && io==w->Before.Bindings[0].Io && Caps(w)) {
    r->AdapterResult=GuDsEfiRun(&w->Adapter,&w->Core);
    r->DisableInvoked=w->Adapter.DisableInvoked;
    r->AdapterOwnershipObserved=w->Adapter.OwnershipObserved;r->AdapterCleanupObserved=w->Adapter.CleanupObserved;
    r->AdapterOwnershipStatus=w->Adapter.OwnershipStatus;r->AdapterCleanupStatus=w->Adapter.CleanupStatus;
    r->DisableIoStatus=w->Adapter.DisableIoStatus;
    result=r->AdapterResult==GU_DS_FIXED?GU_DO_FIXED:r->AdapterResult==GU_DS_ALREADY_CONSISTENT?GU_DO_ALREADY_CONSISTENT:GU_DO_ADAPTER_FAILED;
    if(!Caps(w) && result==GU_DO_FIXED)result=GU_DO_ADAPTER_FAILED;
  }
  if(r->OpenSucceeded || r->ClaimObserved) {
    r->CloseInvoked=TRUE;
    r->CloseStatus=w->Close(w->Target.Handle,&PciGuid,w->Owner,NULL);
    if(r->CloseStatus!=EFI_SUCCESS && (result==GU_DO_FIXED || result==GU_DO_ALREADY_CONSISTENT))result=GU_DO_CLOSE_FAILED;
  }
  s=View(w,1,FALSE,&held);
  EFI_STATUS beforeAfterStatus=s;
  r->ClaimMayRemain=s!=EFI_SUCCESS;
  r->AfterStatus=Capture(w,&w->After,result==GU_DO_FIXED || result==GU_DO_CLOSE_FAILED);
  r->AfterObserved=w->After.Ready && w->After.Status==EFI_SUCCESS;
  /* Capture itself calls firmware. It cannot be the last action after the
   * no-claim proof: those reads might have recreated a controller consumer. */
  s=View(w,1,FALSE,&held);r->ClaimMayRemain=s!=EFI_SUCCESS;
  if((result==GU_DO_FIXED || result==GU_DO_ALREADY_CONSISTENT) &&
     (beforeAfterStatus!=EFI_SUCCESS || s!=EFI_SUCCESS || r->AfterStatus!=EFI_SUCCESS || !Caps(w)))result=GU_DO_VERIFY_FAILED;
  return result;
}
GU_DO_RESULT GuDsOwnedRun(GU_DO_TRANSACTION *t,EFI_BOOT_SERVICES *boot,EFI_HANDLE owner,
  const GU_DS_CAPTURE_TARGET *target,BOOLEAN (*log)(VOID *,const char *),VOID *logContext) {
  if(!t)return GU_DO_INVALID;
  if(Busy || t->Started!=FALSE)return GU_DO_REUSED;
  if((target && Overlap(t,sizeof(*t),target,sizeof(*target))) || (boot && Overlap(t,sizeof(*t),boot,sizeof(*boot))) ||
     Overlap(t,sizeof(*t),&Active,sizeof(Active)))return GU_DO_INVALID;
  *t=(GU_DO_TRANSACTION){0};t->Started=TRUE;
  t->CaptureStatus=t->OwnershipStatus=t->CleanupStatus=t->OpenStatus=t->CloseStatus=t->AfterStatus=
    t->AdapterOwnershipStatus=t->AdapterCleanupStatus=t->DisableIoStatus=EFI_NOT_STARTED;
  if(!boot || !owner || !target || !log || !boot->OpenProtocol || !boot->CloseProtocol ||
     !boot->HandleProtocol || !boot->LocateDevicePath || !boot->OpenProtocolInformation || !boot->FreePool ||
     Overlap(t,sizeof(*t),target,sizeof(*target)) || Overlap(t,sizeof(*t),boot,sizeof(*boot)) ||
     Overlap(t,sizeof(*t),&Active,sizeof(Active)))return GU_DO_INVALID;
  Busy=TRUE;Active=(WORK){0};WORK *w=&Active;w->Caller=t;w->Input=target;w->Target=*target;
  w->Boot=boot;w->Owner=owner;w->Handle=boot->HandleProtocol;w->Locate=boot->LocateDevicePath;
  w->Owners=boot->OpenProtocolInformation;w->Open=boot->OpenProtocol;w->Close=boot->CloseProtocol;w->Free=boot->FreePool;
  w->Log=log;w->LogContext=logContext;w->Report.Started=TRUE;
  w->Report.CaptureStatus=w->Report.OwnershipStatus=w->Report.CleanupStatus=w->Report.OpenStatus=
    w->Report.CloseStatus=w->Report.AfterStatus=w->Report.AdapterOwnershipStatus=
    w->Report.AdapterCleanupStatus=w->Report.DisableIoStatus=EFI_NOT_STARTED;
  w->Report.AdapterResult=GU_DS_INVALID;
  w->Report.Result=Run(w);*t=w->Report;Busy=FALSE;return t->Result;
}
