/* GPL-2.0-only. Research-only decode-cache transaction; no shipped build uses it. */
#pragma once
#include "snapshot.h"
#define GU_DS_FOLLOWUPS 4U

typedef struct {
  VOID *Context;
  EFI_STATUS (*Read)(VOID *Context, GU_DS_SNAPSHOT *Snapshot);
  /* The only write capability. Its adapter must target the verified GPU and call
   * PciIo Attributes(Disable, IO), never enable IO, memory or bus mastering. */
  EFI_STATUS (*DisableIo)(VOID *Context);
  /* TRUE means the event was durably recorded; a failed log forbids further work. */
  BOOLEAN (*Log)(VOID *Context, const char *Event);
} GU_DS_OPS;

typedef enum {
  GU_DS_INVALID, GU_DS_REUSED, GU_DS_READ_FAILED, GU_DS_LOG_FAILED,
  GU_DS_DRIFT, GU_DS_DISABLE_FAILED, GU_DS_ALREADY_CONSISTENT, GU_DS_FIXED
} GU_DS_RESULT;

/* Caller owns one zero-initialized object per authorized transaction. Never reset
 * it to retry. Per-image workspace blocks callback reentry through fresh objects;
 * it is not a CPU lock and cannot police new objects after a completed call. */
typedef struct {
  BOOLEAN Started, Attempted, PostObserved;
  EFI_STATUS DisableStatus, ObservationStatus;
  GU_DS_RESULT Result;
} GU_DS_TRANSACTION;

GU_DS_RESULT GuDecodeSync(GU_DS_TRANSACTION *Transaction, const GU_DS_OPS *Ops,
                         const GU_DS_SNAPSHOT *Expected);
/* Internal alias guard for adapters freeing firmware query buffers. No callback
 * or address disclosure; covers this image's private core workspace. */
BOOLEAN GuDecodeWorkspaceOverlap(const VOID *Buffer,UINTN Bytes);
