/* GPL-2.0-only. Real UEFI protocol adapter exercised only through host mocks.
 * Deliberately not wired into probes, boot images, staging or LOCAL admission. */
#include "efi-adapter.h"
#include "efi-path.h"

static EFI_GUID PciGuid=EFI_PCI_IO_PROTOCOL_GUID,PathGuid=EFI_DEVICE_PATH_PROTOCOL_GUID;
/* One serialized run per image, shared by the public and internal callbacks. */
static GU_DS_EFI_CONTEXT ActiveAdapter;
static GU_DS_SNAPSHOT ReadSnapshots[2],DisableSnapshot;
static BOOLEAN WorkspaceBusy;
#ifdef GU_DS_POST_STOP_RESTORE
static GU_DS_SNAPSHOT RestoreInitial;
static GU_DR_TRANSACTION RestoreReport;
#endif
#ifdef GU_DS_HOST_WORKSPACE_TEST
#if !__STDC_HOSTED__
#error Workspace address probes are exclusively for hosted RAM tests
#endif
const VOID *GuDsTestAdapterWorkspace(UINTN index) {
#ifdef GU_DS_POST_STOP_RESTORE
  if(index==5)return &RestoreReport;
  if(index==6)return &RestoreInitial;
  if(index==7)return &ActiveAdapter.ReleasedBefore;
  if(index==8)return &ActiveAdapter.ReleasedAfter;
  if(index==9)return &ActiveAdapter.ReleasePlan;
#endif
  return index==0?(const VOID *)&ActiveAdapter:index==1?(const VOID *)&ReadSnapshots[0]:
    index==2?(const VOID *)&ReadSnapshots[1]:index==3?(const VOID *)&DisableSnapshot:ActiveAdapter.ActiveOutput;
}
#endif
static BOOLEAN Bytes(const VOID *a,const VOID *b,UINTN n) {
  const UINT8 *x=a,*y=b;for(UINTN i=0;i<n;i++)if(x[i]!=y[i])return FALSE;return TRUE;
}
static BOOLEAN Overlap(const VOID *a,UINTN an,const VOID *b,UINTN bn) {
  UINTN x=(UINTN)a,y=(UINTN)b;return x<=y?y-x<an:x-y<bn;
}
static const GU_DS_DEVICE *ExpectedDevice(const GU_DS_EFI_CONTEXT *c,UINTN i) {
  return i?&c->Expected.Parents[i-1]:&c->Expected.Gpu;
}
static BOOLEAN Caps(const GU_DS_EFI_CONTEXT *c,const GU_DS_EFI_DEVICE *d) {
  return c->Boot->HandleProtocol==c->HandleProtocol && c->Boot->LocateDevicePath==c->LocateDevicePath &&
    c->Boot->OpenProtocolInformation==c->OpenProtocolInformation && c->Boot->FreePool==c->FreePool &&
    d->Pin.Io->GetLocation==d->Location && d->Pin.Io->Pci.Read==d->Read && d->Pin.Io->Attributes==d->Attributes;
}
static BOOLEAN AllCaps(const GU_DS_EFI_CONTEXT *c) {
  for(UINTN i=0;i<1+c->Expected.ParentCount;i++)if(!Caps(c,&c->Devices[i]))return FALSE;
  return TRUE;
}
static BOOLEAN Controller(const GU_DS_EFI_BINDING *gpu,UINTN parents) {
  UINTN observed=0;
  return GuDsControllerParents(gpu->Path,gpu->PathBytes,&observed) && observed==parents;
}
EFI_STATUS GuDsEfiInitialize(GU_DS_EFI_CONTEXT *c,EFI_BOOT_SERVICES *boot,EFI_HANDLE owner,
  const GU_DS_EFI_BINDING *bindings,UINTN count,const GU_DS_SNAPSHOT *expected,
  BOOLEAN (*log)(VOID *,const char *),VOID *logContext) {
  if(!c)return EFI_INVALID_PARAMETER;
  if(WorkspaceBusy)return EFI_ALREADY_STARTED;
  if(c->InitUsed!=FALSE)return EFI_ALREADY_STARTED;
  /* Never reset a used context, including when Init is called from a callback. */
  c->InitUsed=TRUE;c->Ready=FALSE;
  if(!boot || !owner || !bindings || !expected || !log || !count || count>1+GU_DS_EFI_MAX_PARENTS ||
     Overlap(c,sizeof(*c),bindings,sizeof(*bindings)*count) || Overlap(c,sizeof(*c),expected,sizeof(*expected)) ||
     !boot->HandleProtocol || !boot->LocateDevicePath || !boot->OpenProtocolInformation || !boot->FreePool || !GuDecodeSnapshotValid(expected) ||
     expected->ParentCount+1!=count || !Controller(&bindings[0],expected->ParentCount))return EFI_INVALID_PARAMETER;
  c->Boot=boot;c->HandleProtocol=boot->HandleProtocol;c->LocateDevicePath=boot->LocateDevicePath;
  c->OpenProtocolInformation=boot->OpenProtocolInformation;c->FreePool=boot->FreePool;c->OwnerImage=owner;
  c->InputBindings=bindings;c->InputExpected=expected;
  c->ActiveOutput=NULL;
  c->OwnershipStatus=c->CleanupStatus=c->DisableIoStatus=EFI_NOT_STARTED;
  c->Expected=*expected;c->DurableLog=log;c->LogContext=logContext;
#ifdef GU_DS_POST_STOP_RESTORE
  c->RestoreMode=FALSE;
  c->ReleasedOrigin=FALSE;c->InputReleasedAfter=NULL;c->InputReleasePlan=NULL;
  c->ReleasedBefore=(GU_DS_SNAPSHOT){0};c->ReleasedAfter=(GU_DS_SNAPSHOT){0};
  c->ReleasePlan=(GU_DS_RELEASE_PLAN){0};
#endif
  for(UINTN i=0;i<count;i++) {
    GU_DS_EFI_DEVICE *d=&c->Devices[i];const GU_DS_DEVICE *e=ExpectedDevice(c,i);
    const GU_DS_EFI_BINDING *pin=&bindings[i];
    if(owner==pin->Handle || owner==(VOID *)pin->Io || (UINTN)pin->Handle!=e->Handle || (UINTN)pin->Io!=e->Interface || !pin->Io ||
       !pin->Io->GetLocation || !pin->Io->Pci.Read || !pin->Io->Attributes)return EFI_INVALID_PARAMETER;
    if(i) {
      UINTN prefix=12+6*i;
      if(pin->PathBytes!=prefix+4 || !Bytes(pin->Path,bindings[0].Path,prefix) ||
         !Bytes(pin->Path+prefix,bindings[0].Path+bindings[0].PathBytes-4,4) ||
         e->Function!=pin->Path[prefix-2] || e->Device!=pin->Path[prefix-1])return EFI_INVALID_PARAMETER;
    }
    d->Pin=*pin;d->Location=pin->Io->GetLocation;d->Read=pin->Io->Pci.Read;d->Attributes=pin->Io->Attributes;
  }
  c->Ready=TRUE;return EFI_SUCCESS;
}
static EFI_STATUS OwnerStatus(GU_DS_EFI_CONTEXT *c,EFI_STATUS s) {
  if(!c->OwnershipObserved || c->OwnershipStatus==EFI_SUCCESS)c->OwnershipStatus=s;
  c->OwnershipObserved=TRUE;
  return s;
}
static BOOLEAN PoolRange(GU_DS_EFI_CONTEXT *c,const VOID *p,UINTN count) {
  UINTN n=(count && count<=GU_DS_EFI_MAX_OPENERS)?count*sizeof(EFI_OPEN_PROTOCOL_INFORMATION_ENTRY):sizeof(EFI_OPEN_PROTOCOL_INFORMATION_ENTRY);
  if((UINTN)p%sizeof(UINTN) || (UINTN)p>~(UINTN)0-n ||
     GuDecodeWorkspaceOverlap(p,n) ||
     Overlap(p,n,c,sizeof(*c)) || Overlap(p,n,c->CallerContext,sizeof(*c)) ||
     Overlap(p,n,c->ActiveTransaction,
#ifdef GU_DS_POST_STOP_RESTORE
       c->RestoreMode?sizeof(GU_DR_TRANSACTION):
#endif
       sizeof(GU_DS_TRANSACTION)) ||
#ifdef GU_DS_POST_STOP_RESTORE
     Overlap(p,n,&RestoreInitial,sizeof(RestoreInitial)) || Overlap(p,n,&RestoreReport,sizeof(RestoreReport)) ||
     (c->ReleasedOrigin && (Overlap(p,n,c->InputReleasedAfter,sizeof(*c->InputReleasedAfter)) ||
       Overlap(p,n,c->InputReleasePlan,sizeof(*c->InputReleasePlan)))) ||
#endif
     Overlap(p,n,c->ActiveOutput,sizeof(GU_DS_SNAPSHOT)) ||
     Overlap(p,n,ReadSnapshots,sizeof(ReadSnapshots)) || Overlap(p,n,&DisableSnapshot,sizeof(DisableSnapshot)) ||
     Overlap(p,n,c->InputBindings,sizeof(*c->InputBindings)*(1+c->Expected.ParentCount)) ||
     Overlap(p,n,c->InputExpected,sizeof(*c->InputExpected)) || Overlap(p,n,c->Boot,sizeof(*c->Boot)) ||
     Overlap(p,n,c->OwnerImage,1))return FALSE;
  for(UINTN i=0;i<1+c->Expected.ParentCount;i++)if(Overlap(p,n,c->Devices[i].Pin.Io,sizeof(EFI_PCI_IO_PROTOCOL)) ||
      Overlap(p,n,c->Devices[i].Pin.Handle,1))return FALSE;
  return TRUE;
}
static EFI_STATUS DropOwner(GU_DS_EFI_CONTEXT *c,EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *entries) {
  if(!entries)return EFI_SUCCESS;
  /* Use the frozen deallocator, including for valid outputs accompanying an
   * error. A failure may already have freed the buffer: never retry it. */
  EFI_STATUS s=c->FreePool(entries);
  if(!c->CleanupObserved || c->CleanupStatus==EFI_SUCCESS)c->CleanupStatus=s;
  c->CleanupObserved=TRUE;
  if(s!=EFI_SUCCESS){c->OwnershipFault=TRUE;return EFI_DEVICE_ERROR;}
  return AllCaps(c)?EFI_SUCCESS:EFI_NOT_READY;
}
static EFI_STATUS OpenOwner(GU_DS_EFI_CONTEXT *c,EFI_OPEN_PROTOCOL_INFORMATION_ENTRY **held) {
  *held=NULL;
  if(c->OwnershipFault || !AllCaps(c))return OwnerStatus(c,EFI_NOT_READY);
  EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *entries=NULL;UINTN count=~(UINTN)0;
  EFI_STATUS s=c->OpenProtocolInformation(c->Devices[0].Pin.Handle,&PciGuid,&entries,&count);
  if(entries && !PoolRange(c,entries,count)) {
    /* Borrowed/invalid addresses are not owned pool allocations to free. */
    c->OwnershipFault=TRUE;return OwnerStatus(c,EFI_COMPROMISED_DATA);
  }
  BOOLEAN valid=s==EFI_SUCCESS && entries && count && count<=GU_DS_EFI_MAX_OPENERS && AllCaps(c);
  UINTN owned=0;
  if(valid)for(UINTN i=0;i<count;i++) {
    const EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *e=&entries[i];
    if(!e->OpenCount){valid=FALSE;break;}
    if(e->Attributes==EFI_OPEN_PROTOCOL_EXCLUSIVE) {
      if(e->AgentHandle!=c->OwnerImage || e->ControllerHandle || e->OpenCount!=1){valid=FALSE;break;}
      owned++;
    } else if(e->Attributes!=EFI_OPEN_PROTOCOL_BY_HANDLE_PROTOCOL && e->Attributes!=EFI_OPEN_PROTOCOL_GET_PROTOCOL &&
              e->Attributes!=EFI_OPEN_PROTOCOL_TEST_PROTOCOL){valid=FALSE;break;}
  }
  if(!valid || owned!=1) {
    EFI_STATUS closed=DropOwner(c,entries);
    return OwnerStatus(c,closed!=EFI_SUCCESS?closed:s!=EFI_SUCCESS?s:EFI_ACCESS_DENIED);
  }
  *held=entries;return OwnerStatus(c,EFI_SUCCESS);
}
static EFI_STATUS ObserveOwner(GU_DS_EFI_CONTEXT *c) {
  EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *entries=NULL;EFI_STATUS s=OpenOwner(c,&entries);
  if(s==EFI_SUCCESS)s=DropOwner(c,entries);
  return s;
}
static EFI_STATUS Resolve(GU_DS_EFI_CONTEXT *c,GU_DS_EFI_DEVICE *d) {
  if(!Caps(c,d))return EFI_NOT_READY;
  VOID *io=NULL,*path=NULL;
  EFI_STATUS s=c->HandleProtocol(d->Pin.Handle,&PciGuid,&io);
  if(s!=EFI_SUCCESS || io!=d->Pin.Io || !Caps(c,d))return EFI_NOT_READY;
  s=c->HandleProtocol(d->Pin.Handle,&PathGuid,&path);
  if(s!=EFI_SUCCESS || !path || !Bytes(path,d->Pin.Path,d->Pin.PathBytes) || !Caps(c,d))return EFI_NOT_READY;
  UINT8 copy[GU_DS_EFI_MAX_PATH];
  for(UINTN i=0;i<d->Pin.PathBytes;i++)copy[i]=d->Pin.Path[i];
  EFI_DEVICE_PATH_PROTOCOL *rest=(VOID *)copy;EFI_HANDLE h=NULL;
  s=c->LocateDevicePath(&PciGuid,&rest,&h);
  if(s!=EFI_SUCCESS || h!=d->Pin.Handle || (UINTN)rest!=(UINTN)copy+d->Pin.PathBytes-4 ||
     !Bytes(copy,d->Pin.Path,d->Pin.PathBytes) || !Caps(c,d))return EFI_NOT_READY;
  return EFI_SUCCESS;
}
static EFI_STATUS ReadOne(GU_DS_EFI_CONTEXT *c,UINTN index,UINT32 sentinel,GU_DS_DEVICE *out) {
  GU_DS_EFI_DEVICE *d=&c->Devices[index];const GU_DS_DEVICE *pin=ExpectedDevice(c,index);
  if(Resolve(c,d)!=EFI_SUCCESS)return EFI_NOT_READY;
  out->Handle=(UINTN)d->Pin.Handle;out->Interface=(UINTN)d->Pin.Io;
  out->Segment=out->Bus=out->Device=out->Function=~(UINTN)0;
  EFI_STATUS s=d->Location(d->Pin.Io,&out->Segment,&out->Bus,&out->Device,&out->Function);
  if(s!=EFI_SUCCESS || !Caps(c,d) || out->Segment!=pin->Segment || out->Bus!=pin->Bus ||
     out->Device!=pin->Device || out->Function!=pin->Function)return EFI_NOT_READY;
  for(UINTN i=0;i<64;i++)out->Config[i]=sentinel;
  s=d->Read(d->Pin.Io,EfiPciIoWidthUint32,0,64,out->Config);
  if(s!=EFI_SUCCESS || !Caps(c,d))return EFI_NOT_READY;
  for(UINTN i=0;i<64;i++)if(out->Config[i]!=pin->Config[i]) {
#ifdef GU_DS_POST_STOP_RESTORE
    if(c->RestoreMode && !index && i==1 && (out->Config[i]|2U)==pin->Config[i])continue;
#endif
    return EFI_NOT_READY;
  }
  out->Attributes=out->Supported=~0ULL;
  s=d->Attributes(d->Pin.Io,EfiPciIoAttributeOperationGet,0,&out->Attributes);
  if(s!=EFI_SUCCESS || out->Attributes==~0ULL || !Caps(c,d))return EFI_NOT_READY;
  s=d->Attributes(d->Pin.Io,EfiPciIoAttributeOperationSupported,0,&out->Supported);
  if(s!=EFI_SUCCESS || out->Supported==~0ULL || !Caps(c,d))return EFI_NOT_READY;
  return Resolve(c,d);
}
static EFI_STATUS ReadLocked(GU_DS_EFI_CONTEXT *c,GU_DS_SNAPSHOT *out) {
  if(ObserveOwner(c)!=EFI_SUCCESS)return EFI_NOT_READY;
  GU_DS_SNAPSHOT *first=&ReadSnapshots[0],*second=&ReadSnapshots[1];
  *first=(GU_DS_SNAPSHOT){0};*second=(GU_DS_SNAPSHOT){0};
  first->ParentCount=second->ParentCount=c->Expected.ParentCount;
  for(UINTN pass=0;pass<2;pass++) {
    GU_DS_SNAPSHOT *s=pass?second:first;
    for(UINTN i=0;i<1+c->Expected.ParentCount;i++) {
      GU_DS_DEVICE *d=i?&s->Parents[i-1]:&s->Gpu;
      if(ReadOne(c,i,pass?0x5a5a5a5aU:0xa5a5a5a5U,d)!=EFI_SUCCESS)return EFI_NOT_READY;
    }
    s->Complete=TRUE;
#ifdef GU_DS_POST_STOP_RESTORE
    if(c->RestoreMode && GuDsStopTransition(&c->Expected,s)==GU_DS_STOP_REFUSED)return EFI_NOT_READY;
#endif
  }
  if(!AllCaps(c) || !GuDecodeSnapshotMatches(second,first,FALSE))return EFI_NOT_READY;
  if(ObserveOwner(c)!=EFI_SUCCESS)return EFI_NOT_READY;
  *out=*second;return EFI_SUCCESS;
}
static EFI_STATUS AdapterRead(VOID *context,GU_DS_SNAPSHOT *out) {
  GU_DS_EFI_CONTEXT *c=context;
  if(!out || Overlap(c,sizeof(*c),out,sizeof(*out)))return EFI_INVALID_PARAMETER;
  *out=(GU_DS_SNAPSHOT){0};
  if(c->Ready!=TRUE || c->Busy!=FALSE)return EFI_NOT_READY;
  c->ActiveOutput=out; /* protect the core's output through Read, Log and Disable */
  c->Busy=TRUE;EFI_STATUS s=ReadLocked(c,out);c->Busy=FALSE;return s;
}
static EFI_STATUS AdapterDisable(VOID *context) {
  GU_DS_EFI_CONTEXT *c=context;
  if(c->Ready!=TRUE || c->Busy!=FALSE || c->WriteSpent!=FALSE)return EFI_ACCESS_DENIED;
  c->Busy=TRUE;c->WriteSpent=TRUE;
  GU_DS_SNAPSHOT *now=&DisableSnapshot;*now=(GU_DS_SNAPSHOT){0};EFI_STATUS s=ReadLocked(c,now);
  EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *held=NULL;
  if(s==EFI_SUCCESS && GuDecodeSnapshotMatches(now,&c->Expected,FALSE))s=OpenOwner(c,&held);
  else s=EFI_NOT_READY;
  if(s==EFI_SUCCESS && AllCaps(c)) {
    GU_DS_EFI_DEVICE *g=&c->Devices[0];
    c->DisableInvoked=TRUE;
    s=g->Attributes(g->Pin.Io,EfiPciIoAttributeOperationDisable,GU_DS_IO,NULL);
    c->DisableIoStatus=s;
  } else s=EFI_NOT_READY;
  /* No FreePool/log callback between the final ownership query and Disable.
   * The held pool buffer is only a snapshot, not a new ownership lock. */
  EFI_STATUS closed=DropOwner(c,held);
  if(s==EFI_SUCCESS && closed!=EFI_SUCCESS)s=closed;
  c->Busy=FALSE;return s;
}
static BOOLEAN AdapterLog(VOID *context,const char *event) {
  GU_DS_EFI_CONTEXT *c=context;
  if(c->Ready!=TRUE || c->Busy!=FALSE)return FALSE;
  c->Busy=TRUE;BOOLEAN ok=c->DurableLog(c->LogContext,event);
  if(ok==TRUE && ObserveOwner(c)!=EFI_SUCCESS)ok=FALSE;
  c->Busy=FALSE;return ok==TRUE;
}
GU_DS_RESULT GuDsEfiRun(GU_DS_EFI_CONTEXT *c,GU_DS_TRANSACTION *t) {
  if(c && t && WorkspaceBusy)return GU_DS_REUSED;
  if(!c || !t || Overlap(c,sizeof(*c),t,sizeof(*t)) || c->Ready!=TRUE)return GU_DS_INVALID;
#ifdef GU_DS_POST_STOP_RESTORE
  if(c->RestoreMode)return GU_DS_INVALID;
#endif
  if(c->RunUsed!=FALSE || c->Busy!=FALSE)return GU_DS_REUSED;
  WorkspaceBusy=TRUE;c->RunUsed=TRUE;
  /* Keep caller-owned binding/policy edits out of an in-flight transaction. */
  GU_DS_EFI_CONTEXT *active=&ActiveAdapter;*active=*c;c->Busy=TRUE;
  active->CallerContext=c;active->ActiveTransaction=t;active->ActiveOutput=NULL;
  const GU_DS_OPS ops={active,AdapterRead,AdapterDisable,AdapterLog};
  GU_DS_RESULT result=GuDecodeSync(t,&ops,&active->Expected);
  c->WriteSpent=active->WriteSpent;c->RunUsed=TRUE;c->Busy=FALSE;
  c->OwnershipFault=active->OwnershipFault;c->OwnershipStatus=active->OwnershipStatus;
  c->CleanupStatus=active->CleanupStatus;c->DisableIoStatus=active->DisableIoStatus;
  c->OwnershipObserved=active->OwnershipObserved;c->CleanupObserved=active->CleanupObserved;
  c->DisableInvoked=active->DisableInvoked;WorkspaceBusy=FALSE;
  return result;
}

#ifdef GU_DS_POST_STOP_RESTORE
static BOOLEAN RestoreInitStorage(GU_DS_EFI_CONTEXT *c,EFI_BOOT_SERVICES *boot,EFI_HANDLE owner,
  const GU_DS_EFI_BINDING *bindings,UINTN count,const GU_DS_SNAPSHOT *expected,
  const GU_DS_SNAPSHOT *after,const GU_DS_RELEASE_PLAN *plan) {
  if(!c || (boot && Overlap(c,sizeof(*c),boot,sizeof(*boot))) ||
     (owner && Overlap(c,sizeof(*c),owner,1)) ||
     (expected && Overlap(c,sizeof(*c),expected,sizeof(*expected))) ||
     (after && Overlap(c,sizeof(*c),after,sizeof(*after))) ||
     (plan && Overlap(c,sizeof(*c),plan,sizeof(*plan))) ||
     (bindings && count && count<=1+GU_DS_EFI_MAX_PARENTS &&
       Overlap(c,sizeof(*c),bindings,count*sizeof(*bindings))))return FALSE;
  if(bindings && count && count<=1+GU_DS_EFI_MAX_PARENTS)for(UINTN i=0;i<count;i++)if(
    (bindings[i].Io && Overlap(c,sizeof(*c),bindings[i].Io,sizeof(EFI_PCI_IO_PROTOCOL))) ||
    (bindings[i].Handle && Overlap(c,sizeof(*c),bindings[i].Handle,1)))return FALSE;
  return TRUE;
}
EFI_STATUS GuDsEfiInitializeRestore(GU_DS_EFI_CONTEXT *c,EFI_BOOT_SERVICES *boot,EFI_HANDLE owner,
  const GU_DS_EFI_BINDING *bindings,UINTN count,const GU_DS_SNAPSHOT *expected,
  BOOLEAN (*log)(VOID *,const char *),VOID *logContext) {
  if(!RestoreInitStorage(c,boot,owner,bindings,count,expected,NULL,NULL))return EFI_INVALID_PARAMETER;
  EFI_STATUS s=GuDsEfiInitialize(c,boot,owner,bindings,count,expected,log,logContext);
  if(s!=EFI_SUCCESS)return s;
  if(c->Expected.Gpu.Attributes!=GU_DS_MEMORY || !(c->Expected.Gpu.Supported&GU_DS_MEMORY)) {
    c->Ready=FALSE;return EFI_INVALID_PARAMETER;
  }
  c->RestoreMode=TRUE;return EFI_SUCCESS;
}
EFI_STATUS GuDsEfiInitializeReleasedRestore(GU_DS_EFI_CONTEXT *c,EFI_BOOT_SERVICES *boot,EFI_HANDLE owner,
  const GU_DS_EFI_BINDING *bindings,UINTN count,const GU_DS_SNAPSHOT *before,
  const GU_DS_SNAPSHOT *after,const GU_DS_RELEASE_PLAN *plan,
  BOOLEAN (*log)(VOID *,const char *),VOID *logContext) {
  if(WorkspaceBusy)return EFI_ALREADY_STARTED;
  if(!RestoreInitStorage(c,boot,owner,bindings,count,before,after,plan))return EFI_INVALID_PARAMETER;
  if(c->InitUsed!=FALSE)return EFI_ALREADY_STARTED;
  if(!GuDsReleasePlanMatches(plan,before,after)) {
    c->InitUsed=TRUE;c->Ready=FALSE;return EFI_INVALID_PARAMETER;
  }
  EFI_STATUS s=GuDsEfiInitialize(c,boot,owner,bindings,count,before,log,logContext);
  if(s!=EFI_SUCCESS)return s;
  c->ReleasedBefore=*before;c->ReleasedAfter=*after;c->ReleasePlan=*plan;
  c->InputReleasedAfter=after;c->InputReleasePlan=plan;
  c->Expected=c->ReleasedBefore;c->Expected.Gpu=c->ReleasePlan.PlannedGpu;
  c->RestoreMode=TRUE;c->ReleasedOrigin=TRUE;return EFI_SUCCESS;
}
static GU_DR_RESULT RestoreFinish(GU_DS_EFI_CONTEXT *c,GU_DR_TRANSACTION *t,GU_DR_RESULT result) {
  GU_DS_EFI_CONTEXT *a=&ActiveAdapter;
  c->WriteSpent=a->WriteSpent;c->RunUsed=TRUE;c->Busy=FALSE;
  c->OwnershipFault=a->OwnershipFault;c->OwnershipStatus=a->OwnershipStatus;
  c->CleanupStatus=a->CleanupStatus;c->OwnershipObserved=a->OwnershipObserved;
  c->CleanupObserved=a->CleanupObserved;
  RestoreReport.Result=result;*t=RestoreReport;WorkspaceBusy=FALSE;return result;
}
static EFI_STATUS RestoreRead(GU_DS_EFI_CONTEXT *c,GU_DS_SNAPSHOT *out) {
  EFI_STATUS s=ReadLocked(c,out);RestoreReport.ObservationStatus=s;
  if(s==EFI_SUCCESS && RestoreReport.EnableInvoked)RestoreReport.PostObserved=TRUE;
  return s;
}
GU_DR_RESULT GuDsEfiRestoreRun(GU_DS_EFI_CONTEXT *c,GU_DR_TRANSACTION *t) {
  if(c && t && WorkspaceBusy)return GU_DR_REUSED;
  if(!c || !t || Overlap(c,sizeof(*c),t,sizeof(*t)) || c->Ready!=TRUE || c->RestoreMode!=TRUE)
    return GU_DR_INVALID;
  if(c->RunUsed!=FALSE || c->Busy!=FALSE)return GU_DR_REUSED;
  if(!GuDecodeSnapshotValid(&c->Expected) || c->Expected.Gpu.Attributes!=GU_DS_MEMORY ||
     !(c->Expected.Gpu.Supported&GU_DS_MEMORY) || c->Expected.ParentCount>GU_DS_EFI_MAX_PARENTS ||
     Overlap(t,sizeof(*t),c->Boot,sizeof(*c->Boot)) ||
     Overlap(t,sizeof(*t),c->OwnerImage,1) ||
     Overlap(t,sizeof(*t),c->InputExpected,sizeof(*c->InputExpected)) ||
     Overlap(t,sizeof(*t),c->InputBindings,(1+c->Expected.ParentCount)*sizeof(*c->InputBindings)))return GU_DR_INVALID;
  if(c->ReleasedOrigin!=FALSE && c->ReleasedOrigin!=TRUE)return GU_DR_INVALID;
  if(!c->ReleasedOrigin && (c->InputReleasedAfter || c->InputReleasePlan || c->ReleasePlan.Ready!=FALSE ||
     c->ReleasedBefore.Complete!=FALSE || c->ReleasedAfter.Complete!=FALSE))return GU_DR_INVALID;
  if(c->ReleasedOrigin && (!c->InputReleasedAfter || !c->InputReleasePlan ||
     !GuDsReleasePlanMatches(&c->ReleasePlan,&c->ReleasedBefore,&c->ReleasedAfter) ||
     !GuDecodeSnapshotMatches(&c->Expected,&c->ReleasedBefore,TRUE) ||
     Overlap(t,sizeof(*t),c->InputReleasedAfter,sizeof(*c->InputReleasedAfter)) ||
     Overlap(t,sizeof(*t),c->InputReleasePlan,sizeof(*c->InputReleasePlan))))return GU_DR_INVALID;
  for(UINTN i=0;i<1+c->Expected.ParentCount;i++)if(
    Overlap(t,sizeof(*t),c->Devices[i].Pin.Io,sizeof(EFI_PCI_IO_PROTOCOL)) ||
    Overlap(t,sizeof(*t),c->Devices[i].Pin.Handle,1))return GU_DR_INVALID;
  if(t->Started!=FALSE)return GU_DR_REUSED;
  WorkspaceBusy=TRUE;c->RunUsed=TRUE;c->Busy=TRUE;
  GU_DS_EFI_CONTEXT *a=&ActiveAdapter;*a=*c;a->Busy=FALSE;
  a->CallerContext=c;a->ActiveTransaction=t;a->ActiveOutput=&RestoreInitial;
  RestoreReport=(GU_DR_TRANSACTION){0};RestoreReport.Started=TRUE;
  RestoreReport.ReleasedOrigin=a->ReleasedOrigin;
  RestoreReport.EnableStatus=RestoreReport.ObservationStatus=EFI_NOT_STARTED;
  t->Started=TRUE;
  if(RestoreRead(a,&RestoreInitial)!=EFI_SUCCESS)return RestoreFinish(c,t,GU_DR_READ_FAILED);
  if(a->ReleasedOrigin && !GuDecodeSnapshotMatches(&RestoreInitial,&a->ReleasedAfter,FALSE))
    return RestoreFinish(c,t,GU_DR_DRIFT);
  GU_DS_STOP_RESULT phase=GuDsStopTransition(&a->Expected,&RestoreInitial);
  if(phase==GU_DS_STOP_REFUSED)return RestoreFinish(c,t,GU_DR_DRIFT);
  if(AdapterLog(a,phase==GU_DS_STOP_MEMORY_OFF?"decode-memory-restore-intent":"decode-memory-already-enabled")!=TRUE)
    return RestoreFinish(c,t,GU_DR_LOG_FAILED);
  if(RestoreRead(a,&DisableSnapshot)!=EFI_SUCCESS)return RestoreFinish(c,t,GU_DR_READ_FAILED);
  if(!GuDecodeSnapshotMatches(&DisableSnapshot,&RestoreInitial,FALSE))return RestoreFinish(c,t,GU_DR_DRIFT);
  if(phase==GU_DS_STOP_MEMORY_OFF) {
    EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *held=NULL;
    EFI_STATUS s=OpenOwner(a,&held);
    if(s!=EFI_SUCCESS || !AllCaps(a)) {
      DropOwner(a,held);return RestoreFinish(c,t,GU_DR_OWNERSHIP_FAILED);
    }
    a->WriteSpent=TRUE;RestoreReport.EnableInvoked=TRUE;
    GU_DS_EFI_DEVICE *g=&a->Devices[0];
    s=g->Attributes(g->Pin.Io,EfiPciIoAttributeOperationEnable,GU_DS_MEMORY,NULL);
    RestoreReport.EnableStatus=s;
    EFI_STATUS cleanup=DropOwner(a,held);
    if(s!=EFI_SUCCESS) {
      if(cleanup==EFI_SUCCESS)RestoreRead(a,&DisableSnapshot);
      return RestoreFinish(c,t,GU_DR_ENABLE_FAILED);
    }
    if(cleanup!=EFI_SUCCESS)return RestoreFinish(c,t,GU_DR_OWNERSHIP_FAILED);
  }
  if(RestoreRead(a,&DisableSnapshot)!=EFI_SUCCESS)return RestoreFinish(c,t,GU_DR_READ_FAILED);
  if(!GuDecodeSnapshotMatches(&DisableSnapshot,&a->Expected,FALSE))return RestoreFinish(c,t,GU_DR_DRIFT);
  if(AdapterLog(a,"decode-memory-restore-observed")!=TRUE)return RestoreFinish(c,t,GU_DR_LOG_FAILED);
  if(RestoreRead(a,&DisableSnapshot)!=EFI_SUCCESS)return RestoreFinish(c,t,GU_DR_READ_FAILED);
  if(!GuDecodeSnapshotMatches(&DisableSnapshot,&a->Expected,FALSE))return RestoreFinish(c,t,GU_DR_DRIFT);
  return RestoreFinish(c,t,phase==GU_DS_STOP_MEMORY_OFF?GU_DR_RESTORED:GU_DR_UNCHANGED);
}
#endif
