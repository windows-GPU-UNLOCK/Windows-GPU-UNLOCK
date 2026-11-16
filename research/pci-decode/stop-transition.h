/* GPL-2.0-only. Pure research observation policy; no restoration authority. */
#pragma once
#include "snapshot.h"

typedef enum {
  GU_DS_STOP_REFUSED,GU_DS_STOP_UNCHANGED,GU_DS_STOP_MEMORY_OFF,GU_DS_STOP_DECODE_REDUCED
} GU_DS_STOP_RESULT;

/* Compare a corrected, complete pre-Stop baseline with a complete post-Stop
 * observation. MEMORY_OFF describes a delta; it does not authorize Enable,
 * establish ownership, authenticate snapshots or prove that Stop occurred.
 * Supplied snapshots must remain immutable throughout this pure call. */
GU_DS_STOP_RESULT GuDsStopTransition(const GU_DS_SNAPSHOT *Before,
                                    const GU_DS_SNAPSHOT *After);
/* Coherent raw3/cache300 origin only. Observe unchanged or a coherent subset of
 * IO/MEM cleared; all other GPU fields and every parent must remain exact.
 * The restore target is the original observation, never a correction to raw2.
 * Observation alone does not authorize any write or establish Stop occurred. */
GU_DS_STOP_RESULT GuDsIoMemStopTransition(const GU_DS_SNAPSHOT *Before,
                                         const GU_DS_SNAPSHOT *After);

/* A derived target, deliberately not a complete/observed snapshot. The actual
 * Before300 and After0 snapshots remain separate mandatory inputs at every use.
 * This plan is not permission to Stop, claim a device, write or unlock. */
typedef struct {
  BOOLEAN Ready;
  UINTN ParentCount;
  UINT64 ObservedBeforeAttributes,ObservedAfterAttributes,RestoreMask;
  GU_DS_DEVICE PlannedGpu;
} GU_DS_RELEASE_PLAN;

/* Research hypothesis: actual raw2/cache300 -> actual raw0/cache0. This is not
 * the corrected-before contract of GuDsStopTransition. No hardware report here
 * establishes that uncorrected NVIDIA Stop produces this transition.
 * Disjoint failures clear Plan; argument-overlap refusal preserves storage. */
BOOLEAN GuDsPlanReleasedMismatch(const GU_DS_SNAPSHOT *Before,const GU_DS_SNAPSHOT *After,
                               GU_DS_RELEASE_PLAN *Plan);
/* Revalidates the supplied observation pair and derived GPU target. This is not
 * a fingerprint of earlier snapshots: parent data is not stored in Plan. Any
 * future actuator caller must freeze the original full snapshots separately. */
BOOLEAN GuDsReleasePlanMatches(const GU_DS_RELEASE_PLAN *Plan,
                              const GU_DS_SNAPSHOT *Before,const GU_DS_SNAPSHOT *After);
