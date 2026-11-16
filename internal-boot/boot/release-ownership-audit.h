/* GPL-2.0-only. Host-only release audit; included after Full/PreparedPlan.
 * Queries are observations under serialized, trusted firmware, not a lock. */
#pragma once
#ifndef GU_RELEASE_PARENT_AUDIT
#error Ownership audit requires the host-only release parent audit
#endif
static BOOLEAN AuditOwnerCaps(VOID) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;
  return a->Table && a->Table->BootServices==a->Boot && a->Boot->OpenProtocolInformation==a->Owners &&
    a->Boot->FreePool==a->Free;
}
static BOOLEAN AuditRangeOverlap(const VOID *a,UINTN an,const VOID *b,UINTN bn) {
  UINTN x=(UINTN)a,y=(UINTN)b;return x<=y?y-x<an:x-y<bn;
}
static BOOLEAN AuditOwnerPool(const VOID *p,UINTN count) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;
  UINTN bytes=count && count<=64?count*sizeof(EFI_OPEN_PROTOCOL_INFORMATION_ENTRY):sizeof(EFI_OPEN_PROTOCOL_INFORMATION_ENTRY);
  if((UINTN)p%sizeof(UINTN) || (UINTN)p>~(UINTN)0-bytes ||
     AuditRangeOverlap(p,bytes,a,sizeof(*a)) || AuditRangeOverlap(p,bytes,&Full,sizeof(Full)) ||
     AuditRangeOverlap(p,bytes,&PreparedPlan,sizeof(PreparedPlan)) ||
     (PreparedGraph && AuditRangeOverlap(p,bytes,PreparedGraph,sizeof(*PreparedGraph))) ||
     AuditRangeOverlap(p,bytes,a->Boot,sizeof(*a->Boot)) || AuditRangeOverlap(p,bytes,a->Table,sizeof(*a->Table)) ||
     (a->HeldQuery && AuditRangeOverlap(p,bytes,a->HeldQuery,64*sizeof(*a->HeldQuery))) ||
     AuditRangeOverlap(p,bytes,a->ClaimOwner,1) || AuditRangeOverlap(p,bytes,a->ClaimTarget,1))return FALSE;
  for(UINTN i=0;i<a->Count;i++)
    if(AuditRangeOverlap(p,bytes,a->Devices[i].Pin.Io,sizeof(EFI_PCI_IO_PROTOCOL)) ||
       AuditRangeOverlap(p,bytes,a->Devices[i].Pin.Handle,1))return FALSE;
  return TRUE;
}
static EFI_STATUS AuditOwnerFree(EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *p) {
  if(!p)return EFI_SUCCESS;
  BOOLEAN held=ReleaseAudit.HeldQuery==p;
  EFI_STATUS s=ReleaseAudit.Free(p);
  if(held)ReleaseAudit.HeldQuery=NULL;
  if(!ReleaseAudit.PoolObserved || ReleaseAudit.PoolStatus==EFI_SUCCESS)ReleaseAudit.PoolStatus=s;
  ReleaseAudit.PoolObserved=TRUE;
  return s==EFI_SUCCESS && !AuditOwnerCaps()?EFI_NOT_READY:s;
}
static BOOLEAN AuditOwnerKey(const EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *a,const EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *b) {
  return a->AgentHandle==b->AgentHandle && a->ControllerHandle==b->ControllerHandle && a->Attributes==b->Attributes;
}
/* Present means exactly one attributable self-exclusive record, not simply
 * Open returning success. Stable additionally requires unchanged passives and
 * no other managing owner. Cleanup may remove our precise record in a changed
 * foreign graph, but never an ambiguous/preexisting same-agent reference. */
static EFI_STATUS AuditOwnerView(BOOLEAN establish,BOOLEAN keep,BOOLEAN *present,BOOLEAN *stable,
                                 EFI_OPEN_PROTOCOL_INFORMATION_ENTRY **held) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;*present=*stable=FALSE;*held=NULL;a->ViewOwnCount=~(UINTN)0;
  if(!AuditOwnerCaps())return EFI_NOT_READY;
  EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *p=NULL;UINTN count=~(UINTN)0;
  EFI_STATUS raw=a->Owners(a->ClaimTarget,&PciGuid,&p,&count);
  if(!a->OwnerObserved || a->OwnerStatus==EFI_SUCCESS)a->OwnerStatus=raw;
  a->OwnerObserved=TRUE;
  if(p && !AuditOwnerPool(p,count))return EFI_COMPROMISED_DATA;
  BOOLEAN valid=raw==EFI_SUCCESS && AuditOwnerCaps() && count<=64 && (!count || p);
  BOOLEAN unchanged=TRUE,precise=TRUE;UINTN own=0,passives=0;
  if(valid)for(UINTN i=0;i<count;i++) {
    const EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *e=&p[i];
    if(!e->AgentHandle || !e->OpenCount){valid=FALSE;break;}
    for(UINTN j=0;j<i;j++)if(AuditOwnerKey(e,&p[j]))valid=FALSE;
    if(!valid)break;
    if(e->AgentHandle==a->ClaimOwner) {
      own++;
      if(e->ControllerHandle || e->Attributes!=EFI_OPEN_PROTOCOL_EXCLUSIVE || e->OpenCount!=1)precise=FALSE;
    } else if(Passive(e->Attributes)) {
      if(establish) {
        if(passives>=63){valid=FALSE;break;}a->Passive[passives]=*e;
      } else {
        UINTN matches=0;
        for(UINTN j=0;j<a->PassiveCount;j++)if(AuditOwnerKey(e,&a->Passive[j]) && e->OpenCount==a->Passive[j].OpenCount)matches++;
        if(matches!=1)unchanged=FALSE;
      }
      passives++;
    } else unchanged=FALSE;
  }
  if(valid) {
    a->ViewOwnCount=own;*present=own==1 && precise;
    if(establish)a->PassiveCount=passives;
    else if(passives!=a->PassiveCount)unchanged=FALSE;
    *stable=unchanged && (own==0 || *present);
  }
  EFI_STATUS s=raw!=EFI_SUCCESS?raw:valid?EFI_SUCCESS:EFI_COMPROMISED_DATA;
  if(s==EFI_SUCCESS && keep){*held=p;a->HeldQuery=p;}
  else {EFI_STATUS freed=AuditOwnerFree(p);if(s==EFI_SUCCESS)s=freed;}
  return s;
}
static EFI_STATUS AuditOwnershipBegin(VOID) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;
  if(a->OwnershipStarted)return EFI_ALREADY_STARTED;
  a->OwnershipStarted=TRUE;a->ClaimTarget=PreparedPlan.RtxPci;a->ClaimIo=PreparedPlan.RtxIo;a->ClaimOwner=Full.Image;
  a->OpenStatus=a->CloseStatus=a->OwnerStatus=a->PoolStatus=EFI_NOT_STARTED;
  BOOLEAN present=FALSE,stable=FALSE;EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *held=NULL;
  EFI_STATUS s=AuditOwnerView(TRUE,FALSE,&present,&stable,&held);
  a->ClaimMayRemain=s!=EFI_SUCCESS || a->ViewOwnCount!=0;
  a->OwnerBaselineReady=s==EFI_SUCCESS && stable && !present && !a->ViewOwnCount;
  return s!=EFI_SUCCESS?s:a->OwnerBaselineReady?EFI_SUCCESS:EFI_ACCESS_DENIED;
}
static EFI_STATUS AuditOwnershipAcquire(EFI_PCI_IO_PROTOCOL **io) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;
  if(!a->OwnershipStarted || !a->OwnerBaselineReady || a->OpenInvoked || !ReleaseAuditBound())return EFI_ACCESS_DENIED;
  BOOLEAN present=FALSE,stable=FALSE;EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *held=NULL;
  EFI_STATUS s=AuditOwnerView(FALSE,TRUE,&present,&stable,&held);
  if(s!=EFI_SUCCESS || !stable || present || a->ViewOwnCount || !ReleaseAuditBound()) {
    AuditOwnerFree(held);a->ClaimMayRemain=TRUE;return s!=EFI_SUCCESS?s:EFI_ACCESS_DENIED;
  }
  /* No log/free/read callback between this precise no-self view and Open. */
  a->OpenInvoked=TRUE;a->ClaimMayRemain=TRUE;
  a->OpenStatus=a->Open(a->ClaimTarget,&PciGuid,(VOID **)io,a->ClaimOwner,NULL,EFI_OPEN_PROTOCOL_EXCLUSIVE);
  a->OpenSucceeded=a->OpenStatus==EFI_SUCCESS;
  EFI_STATUS freed=AuditOwnerFree(held);held=NULL;
  EFI_STATUS viewed=AuditOwnerView(FALSE,FALSE,&present,&stable,&held);
  a->ClaimObserved=viewed==EFI_SUCCESS && present;Full.Owned=a->ClaimObserved;
  a->ClaimMayRemain=viewed!=EFI_SUCCESS || a->ViewOwnCount!=0;
  if(a->OpenStatus!=EFI_SUCCESS)return a->OpenStatus;
  if(freed!=EFI_SUCCESS)return freed;
  if(viewed!=EFI_SUCCESS)return viewed;
  return stable && present && *io==a->ClaimIo && ReleaseAuditBound()?EFI_SUCCESS:EFI_NOT_READY;
}
static EFI_STATUS AuditOwnershipEnable(UINT64 needed) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;
  if(!a->OpenInvoked || !a->OpenSucceeded || a->OpenStatus!=EFI_SUCCESS || !a->ClaimObserved)return EFI_ACCESS_DENIED;
  BOOLEAN present=FALSE,stable=FALSE;EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *held=NULL;
  EFI_STATUS s=AuditOwnerView(FALSE,TRUE,&present,&stable,&held);
  if(s==EFI_SUCCESS && (!present || !stable || !ReleaseAuditBound()))s=EFI_ACCESS_DENIED;
  /* Retain the final owner-query buffer until the only write returns. */
  if(s==EFI_SUCCESS && needed)s=a->Devices[0].Attributes(a->ClaimIo,EfiPciIoAttributeOperationEnable,needed,NULL);
  EFI_STATUS freed=AuditOwnerFree(held);
  return s==EFI_SUCCESS?freed:s;
}
static EFI_STATUS AuditOwnershipFinishInner(VOID) {
  GU_RELEASE_AUDIT_STATE *a=&ReleaseAudit;
  if(!a->OpenInvoked)return EFI_SUCCESS;
  BOOLEAN present=FALSE,stable=FALSE;EFI_OPEN_PROTOCOL_INFORMATION_ENTRY *held=NULL;
  EFI_STATUS s=AuditOwnerView(FALSE,TRUE,&present,&stable,&held);
  if(s!=EFI_SUCCESS || (!present && a->ViewOwnCount)) {
    AuditOwnerFree(held);a->ClaimMayRemain=TRUE;return s!=EFI_SUCCESS?s:EFI_ACCESS_DENIED;
  }
  if(present) {
    if(a->CloseInvoked){AuditOwnerFree(held);return EFI_ALREADY_STARTED;}
    a->CloseInvoked=TRUE;
    a->CloseStatus=a->Close(a->ClaimTarget,&PciGuid,a->ClaimOwner,NULL);
  }
  EFI_STATUS freed=AuditOwnerFree(held);held=NULL;
  EFI_STATUS viewed=AuditOwnerView(FALSE,FALSE,&present,&stable,&held);
  a->ClaimMayRemain=viewed!=EFI_SUCCESS || a->ViewOwnCount!=0;
  if(!a->ClaimMayRemain)Full.Owned=FALSE;
  if(a->CloseInvoked && a->CloseStatus!=EFI_SUCCESS)return a->CloseStatus;
  if(freed!=EFI_SUCCESS)return freed;
  if(viewed!=EFI_SUCCESS)return viewed;
  return !present && !a->ViewOwnCount && stable && !a->ClaimMayRemain && ReleaseAuditBound()?EFI_SUCCESS:EFI_NOT_READY;
}
static EFI_STATUS AuditOwnershipFinish(VOID) {
  if(!ReleaseAudit.OpenInvoked)return EFI_SUCCESS;
  if(ReleaseAudit.CleanupObserved)return EFI_ALREADY_STARTED;
  ReleaseAudit.CleanupObserved=TRUE;
  ReleaseAudit.CleanupStatus=AuditOwnershipFinishInner();
  return ReleaseAudit.CleanupStatus;
}
