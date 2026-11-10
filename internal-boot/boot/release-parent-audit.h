/* GPL-2.0-only. Host-only bridge from actual release phases to typed observations.
 * No shipped admission change, new actuator API or hardware approval. The
 * separately gated mismatch hypothesis reuses only the existing MEMORY restore.
 * Included after PLAN: all state belongs to one serialized EFI-image model. */
#pragma once
#if GU_RELEASE_PARENT_AUDIT != 1 || !defined(GU_FULL_UNLOCK) || !defined(__STDC_HOSTED__) || !__STDC_HOSTED__
#error Release parent audit is exactly-1, full-release, hosted research only
#endif
#if !defined(GU_DS_POST_STOP_CAPTURE) || GU_DS_POST_STOP_CAPTURE != 1
#error Release parent audit requires the opt-in post-Stop collector
#endif
#include "../../research/pci-decode/efi-capture.h"
#include "../../research/pci-decode/efi-path.h"
#include "../../research/pci-decode/stop-transition.h"
#ifdef GU_RELEASE_MISMATCH_RESEARCH
#if GU_RELEASE_MISMATCH_RESEARCH != 1
#error Released mismatch research must be exactly 1
#endif
#endif

#define GU_RELEASE_AUDIT_CAPTURES 32U
typedef struct {
  BOOLEAN Active,PrepareEntered,Used,Ready,ReleaseUsed,Failed,Mismatch,PlanReady,Verifying;
  BOOLEAN IoMem,AfterReady;
  EFI_SYSTEM_TABLE *Table;
  EFI_BOOT_SERVICES *Boot;
  EFI_HANDLE_PROTOCOL Handle;
  EFI_LOCATE_DEVICE_PATH Locate;
  EFI_DISCONNECT_CONTROLLER Disconnect;
  EFI_OPEN_PROTOCOL Open;
  EFI_CLOSE_PROTOCOL Close;
  EFI_RAISE_TPL Raise;
  EFI_RESTORE_TPL Restore;
  EFI_OPEN_PROTOCOL_INFORMATION Owners;
  EFI_FREE_POOL Free;
  BOOLEAN OwnershipStarted,OwnerBaselineReady,OpenInvoked,OpenSucceeded,ClaimObserved,ClaimMayRemain,CloseInvoked;
  BOOLEAN OwnerObserved,PoolObserved,CleanupObserved;
  EFI_STATUS OpenStatus,CloseStatus,OwnerStatus,PoolStatus;
  EFI_STATUS CleanupStatus;
  EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *HeldQuery;
  EFI_HANDLE ClaimTarget,ClaimOwner;
  EFI_PCI_IO_PROTOCOL *ClaimIo;
  EFI_OPEN_PROTOCOL_INFORMATION_ENTRY Passive[64];
  UINTN PassiveCount,ViewOwnCount;
  GU_DS_CAPTURE_TARGET Target;
  GU_DS_EFI_DEVICE Devices[1+GU_DS_EFI_MAX_PARENTS];
  UINTN Count,Next;
  UINTN ActualAfterIndex;
  GU_DS_RELEASE_PLAN Plan;
  /* Each operation gets a distinct single-use collector, never a reset/retry. */
  GU_DS_CAPTURE Captures[GU_RELEASE_AUDIT_CAPTURES];
} GU_RELEASE_AUDIT_STATE;
static GU_RELEASE_AUDIT_STATE ReleaseAudit;

static BOOLEAN ReleaseAuditBound(VOID) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;
  if(!a->Table || a->Table->BootServices!=a->Boot || a->Boot->HandleProtocol!=a->Handle ||
     a->Boot->LocateDevicePath!=a->Locate || a->Boot->DisconnectController!=a->Disconnect ||
     a->Boot->OpenProtocol!=a->Open || a->Boot->CloseProtocol!=a->Close ||
     a->Boot->RaiseTPL!=a->Raise || a->Boot->RestoreTPL!=a->Restore ||
     a->Boot->OpenProtocolInformation!=a->Owners || a->Boot->FreePool!=a->Free)return FALSE;
  for(UINTN i=0;i<a->Count;i++) {
    const GU_DS_EFI_DEVICE *d=&a->Devices[i];
    if(d->Pin.Io->GetLocation!=d->Location || d->Pin.Io->Pci.Read!=d->Read ||
       d->Pin.Io->Attributes!=d->Attributes)return FALSE;
  }
  return TRUE;
}
static EFI_STATUS ReleaseAuditStatus(EFI_STATUS status) {
  if(status!=EFI_SUCCESS)ReleaseAudit.Failed=TRUE;
  return status;
}
static EFI_STATUS ReleaseAuditBeforeConsole(EFI_SYSTEM_TABLE *t,const PLAN *p) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;
  if(a->Used)return EFI_ALREADY_STARTED;
  a->Used=TRUE;
  if(!t || !t->BootServices || !p)return ReleaseAuditStatus(EFI_INVALID_PARAMETER);
  a->Table=t;a->Boot=t->BootServices;a->Handle=a->Boot->HandleProtocol;a->Locate=a->Boot->LocateDevicePath;
  a->Disconnect=a->Boot->DisconnectController;a->Open=a->Boot->OpenProtocol;a->Close=a->Boot->CloseProtocol;
  a->Raise=a->Boot->RaiseTPL;a->Restore=a->Boot->RestoreTPL;
  a->Owners=a->Boot->OpenProtocolInformation;a->Free=a->Boot->FreePool;
  if(!a->Handle || !a->Locate || !a->Disconnect || !a->Open || !a->Close || !a->Raise || !a->Restore || !a->Owners || !a->Free)
    return ReleaseAuditStatus(EFI_UNSUPPORTED);
  UINTN controller=0,total=0,parents=0;
  if(!GuDecodeGpuDisplayPath(p->RtxDisplayPath,sizeof(p->RtxDisplayPath),&controller,&total) ||
     total!=sizeof(p->RtxDisplayPath) || controller+4>sizeof(a->Target.Path))return ReleaseAuditStatus(EFI_UNSUPPORTED);
  a->Target.Handle=p->RtxPci;a->Target.Segment=GU_TARGET_SEGMENT;a->Target.Bus=GU_TARGET_BUS;
  a->Target.PciId=GU_BOARD_ID;a->Target.Subsystem=GU_BOARD_SUBSYSTEM;a->Target.Bar0=(UINT32)GU_BAR0_BASE;
  a->Target.PathBytes=controller+4;
  for(UINTN i=0;i<controller;i++)a->Target.Path[i]=p->RtxDisplayPath[i];
  const UINT8 end[]={0x7f,0xff,4,0};
  for(UINTN i=0;i<4;i++)a->Target.Path[controller+i]=end[i];
  if(!GuDsControllerParents(a->Target.Path,a->Target.PathBytes,&parents))return ReleaseAuditStatus(EFI_UNSUPPORTED);
  GU_DS_CAPTURE *before=&a->Captures[a->Next++];
  EFI_STATUS s=GuDsEfiCaptureReleaseOrigin(before,a->Boot,&a->Target);
  if(s!=EFI_SUCCESS || !ReleaseAuditBound() || before->Bindings[0].Io!=p->RtxIo)
    return ReleaseAuditStatus(EFI_NOT_READY);
  a->IoMem=(before->Snapshot.Gpu.Config[1]&0xffffU)==3U;
  if(!a->IoMem && before->Snapshot.Gpu.Attributes!=GU_DS_MEMORY) {
#ifdef GU_RELEASE_MISMATCH_RESEARCH
    if(before->Snapshot.Gpu.Attributes!=(GU_DS_IO|GU_DS_MEMORY) ||
       !(before->Snapshot.Gpu.Supported&GU_DS_MEMORY))return ReleaseAuditStatus(EFI_NOT_READY);
    a->Mismatch=TRUE;
#else
    return ReleaseAuditStatus(EFI_NOT_READY);
#endif
  }
  a->Count=before->Count;
  for(UINTN i=0;i<a->Count;i++) {
    GU_DS_EFI_DEVICE *d=&a->Devices[i];d->Pin=before->Bindings[i];
    d->Location=d->Pin.Io->GetLocation;d->Read=d->Pin.Io->Pci.Read;d->Attributes=d->Pin.Io->Attributes;
  }
  a->Ready=TRUE;
  return EFI_SUCCESS;
}
/* FALSE: exact frozen pre-release observation. TRUE: the selected corrected or
 * mismatch Stop delta. Caller still performs its graph/code/cold/claim guards. */
static EFI_STATUS ReleaseAuditObserve(BOOLEAN afterStop) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;
  if(!a->Ready || a->Failed || !ReleaseAuditBound() || a->Next>=GU_RELEASE_AUDIT_CAPTURES)
    return ReleaseAuditStatus(EFI_NOT_READY);
  GU_DS_CAPTURE *current=&a->Captures[a->Next++];
  const GU_DS_SNAPSHOT *before=&a->Captures[0].Snapshot;
  EFI_STATUS s=afterStop?(a->IoMem?GuDsEfiCaptureIoMemAfterStop(current,a->Boot,&a->Target,before):
    a->Mismatch?GuDsEfiCaptureReleasedMismatch(current,a->Boot,&a->Target,before):
    GuDsEfiCaptureAfterStop(current,a->Boot,&a->Target,before)):GuDsEfiCaptureReleaseOrigin(current,a->Boot,&a->Target);
  if(s!=EFI_SUCCESS || !ReleaseAuditBound() ||
     (!afterStop && !GuDecodeSnapshotMatches(&current->Snapshot,before,FALSE)))
    return ReleaseAuditStatus(EFI_NOT_READY);
  if(afterStop && a->Mismatch) {
    if(!a->PlanReady) {
      if(!GuDsPlanReleasedMismatch(before,&current->Snapshot,&a->Plan))return ReleaseAuditStatus(EFI_NOT_READY);
      a->ActualAfterIndex=a->Next-1;a->PlanReady=TRUE;
    }
    if(!GuDsReleasePlanMatches(&a->Plan,before,&current->Snapshot) ||
       !GuDecodeSnapshotMatches(&current->Snapshot,&a->Captures[a->ActualAfterIndex].Snapshot,FALSE))
      return ReleaseAuditStatus(EFI_NOT_READY);
  }
  if(afterStop && a->IoMem) {
    if(!a->AfterReady){a->ActualAfterIndex=a->Next-1;a->AfterReady=TRUE;}
    if(!GuDecodeSnapshotMatches(&current->Snapshot,&a->Captures[a->ActualAfterIndex].Snapshot,FALSE))
      return ReleaseAuditStatus(EFI_NOT_READY);
  }
  return EFI_SUCCESS;
}
static EFI_STATUS ReleaseAuditRestoreTarget(UINT64 observed,UINT64 *target) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;
  const GU_DS_SNAPSHOT *before=&a->Captures[0].Snapshot;
  if(!target || !a->Ready || a->Failed || observed!=before->Gpu.Attributes)return EFI_NOT_READY;
  if(a->IoMem && (!a->AfterReady || a->ActualAfterIndex>=a->Next ||
     GuDsIoMemStopTransition(before,&a->Captures[a->ActualAfterIndex].Snapshot)==GU_DS_STOP_REFUSED))return EFI_NOT_READY;
  if(!a->Mismatch){*target=observed;return EFI_SUCCESS;}
  if(!a->PlanReady || a->ActualAfterIndex>=a->Next ||
     !GuDsReleasePlanMatches(&a->Plan,before,&a->Captures[a->ActualAfterIndex].Snapshot))return EFI_NOT_READY;
  *target=a->Plan.PlannedGpu.Attributes;
  return *target==GU_DS_MEMORY?EFI_SUCCESS:EFI_NOT_READY;
}
static EFI_STATUS ReleaseAuditRestored(VOID) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;UINT64 target=0;
  if(ReleaseAuditRestoreTarget(a->Captures[0].Snapshot.Gpu.Attributes,&target)!=EFI_SUCCESS ||
     !ReleaseAuditBound() || a->Next>=GU_RELEASE_AUDIT_CAPTURES)return ReleaseAuditStatus(EFI_NOT_READY);
  GU_DS_CAPTURE *current=&a->Captures[a->Next++];
  EFI_STATUS s=GuDsEfiCaptureReleaseOrigin(current,a->Boot,&a->Target);
  if(s!=EFI_SUCCESS || !ReleaseAuditBound() || current->Snapshot.Gpu.Attributes!=target ||
     !GuDecodeSnapshotMatches(&current->Snapshot,&a->Captures[0].Snapshot,a->Mismatch))
    return ReleaseAuditStatus(EFI_NOT_READY);
  return EFI_SUCCESS;
}
