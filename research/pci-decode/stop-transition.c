/* GPL-2.0-only. No allocation, callbacks, protocol access or hardware writes. */
#include "stop-transition.h"

static BOOLEAN SameDevice(const GU_DS_DEVICE *a,const GU_DS_DEVICE *b,
                          UINT32 missing,UINT64 cleared) {
  if(a->Handle!=b->Handle || a->Interface!=b->Interface ||
     a->Segment!=b->Segment || a->Bus!=b->Bus || a->Device!=b->Device ||
     a->Function!=b->Function || a->Supported!=b->Supported ||
     b->Attributes!=(a->Attributes&~cleared))return FALSE;
  for(UINTN i=0;i<64;i++)
    if((b->Config[i]|(i==1?missing:0))!=a->Config[i])return FALSE;
  return TRUE;
}

GU_DS_STOP_RESULT GuDsStopTransition(const GU_DS_SNAPSHOT *before,
                                    const GU_DS_SNAPSHOT *after) {
  if(!GuDecodeSnapshotValid(before) || before->Gpu.Attributes!=GU_DS_MEMORY ||
     !after || after->Complete!=TRUE || after->ParentCount!=before->ParentCount)
    return GU_DS_STOP_REFUSED;
  UINT32 missing=before->Gpu.Config[1]&~after->Gpu.Config[1]&2U;
  if(missing && !(before->Gpu.Supported&GU_DS_MEMORY))return GU_DS_STOP_REFUSED;
  if(!SameDevice(&before->Gpu,&after->Gpu,missing,missing?GU_DS_MEMORY:0))
    return GU_DS_STOP_REFUSED;
  for(UINTN i=0;i<before->ParentCount;i++)
    if(!SameDevice(&before->Parents[i],&after->Parents[i],0,0))
      return GU_DS_STOP_REFUSED;
  return missing?GU_DS_STOP_MEMORY_OFF:GU_DS_STOP_UNCHANGED;
}

GU_DS_STOP_RESULT GuDsIoMemStopTransition(const GU_DS_SNAPSHOT *before,
                                         const GU_DS_SNAPSHOT *after) {
  if(!GuDsReleaseSnapshotValid(before) || (before->Gpu.Config[1]&0xffffU)!=3U ||
     !after || after->Complete!=TRUE || after->ParentCount!=before->ParentCount)
    return GU_DS_STOP_REFUSED;
  UINT32 missing=before->Gpu.Config[1]&~after->Gpu.Config[1]&3U;
  UINT64 cleared=(missing&1U?GU_DS_IO:0)|(missing&2U?GU_DS_MEMORY:0);
  if(!SameDevice(&before->Gpu,&after->Gpu,missing,cleared))return GU_DS_STOP_REFUSED;
  for(UINTN i=0;i<before->ParentCount;i++)
    if(!SameDevice(&before->Parents[i],&after->Parents[i],0,0))return GU_DS_STOP_REFUSED;
  return missing?GU_DS_STOP_DECODE_REDUCED:GU_DS_STOP_UNCHANGED;
}

static BOOLEAN PlanOverlap(const VOID *a,UINTN an,const VOID *b,UINTN bn) {
  UINTN x=(UINTN)a,y=(UINTN)b;return x<=y?y-x<an:x-y<bn;
}
BOOLEAN GuDsPlanReleasedMismatch(const GU_DS_SNAPSHOT *before,const GU_DS_SNAPSHOT *after,
                               GU_DS_RELEASE_PLAN *plan) {
  if(!plan || (before && PlanOverlap(plan,sizeof(*plan),before,sizeof(*before))) ||
     (after && PlanOverlap(plan,sizeof(*plan),after,sizeof(*after))) ||
     (before && after && PlanOverlap(before,sizeof(*before),after,sizeof(*after))))return FALSE;
  *plan=(GU_DS_RELEASE_PLAN){0};
  if(!GuDecodeSnapshotValid(before) || before->Gpu.Attributes!=(GU_DS_IO|GU_DS_MEMORY) ||
     !(before->Gpu.Supported&GU_DS_MEMORY) || !after || after->Complete!=TRUE ||
     after->ParentCount!=before->ParentCount || (after->Gpu.Config[1]&0xffffU)!=0 ||
     !SameDevice(&before->Gpu,&after->Gpu,2U,GU_DS_IO|GU_DS_MEMORY))return FALSE;
  for(UINTN i=0;i<before->ParentCount;i++)
    if(!SameDevice(&before->Parents[i],&after->Parents[i],0,0))return FALSE;
  plan->ParentCount=before->ParentCount;
  plan->ObservedBeforeAttributes=before->Gpu.Attributes;plan->ObservedAfterAttributes=after->Gpu.Attributes;
  plan->PlannedGpu=before->Gpu;plan->PlannedGpu.Attributes=GU_DS_MEMORY;
  plan->RestoreMask=GU_DS_MEMORY;plan->Ready=TRUE;return TRUE;
}
BOOLEAN GuDsReleasePlanMatches(const GU_DS_RELEASE_PLAN *plan,
                              const GU_DS_SNAPSHOT *before,const GU_DS_SNAPSHOT *after) {
  GU_DS_RELEASE_PLAN derived;
  if(!plan || !GuDsPlanReleasedMismatch(before,after,&derived))return FALSE;
  return plan->Ready==TRUE && plan->ParentCount==derived.ParentCount &&
    plan->ObservedBeforeAttributes==derived.ObservedBeforeAttributes &&
    plan->ObservedAfterAttributes==derived.ObservedAfterAttributes && plan->RestoreMask==derived.RestoreMask &&
    SameDevice(&plan->PlannedGpu,&derived.PlannedGpu,0,0);
}
