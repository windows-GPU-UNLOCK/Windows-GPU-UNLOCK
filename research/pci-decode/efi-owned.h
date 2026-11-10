/* GPL-2.0-only. Research-only serialized claim/correction/close lifecycle. */
#pragma once
#include "efi-capture.h"
#include "efi-adapter.h"

typedef enum {
  GU_DO_INVALID,GU_DO_REUSED,GU_DO_CAPTURE_FAILED,GU_DO_LOG_FAILED,
  GU_DO_OWNERSHIP_REFUSED,GU_DO_OPEN_FAILED,GU_DO_ADAPTER_FAILED,
  GU_DO_CLOSE_FAILED,GU_DO_VERIFY_FAILED,GU_DO_ALREADY_CONSISTENT,GU_DO_FIXED
} GU_DO_RESULT;
typedef struct {
  BOOLEAN Started,OpenInvoked,OpenSucceeded,ClaimObserved,CloseInvoked,ClaimMayRemain;
  BOOLEAN OwnershipObserved,CleanupObserved,AfterObserved,DisableInvoked;
  BOOLEAN AdapterOwnershipObserved,AdapterCleanupObserved;
  EFI_STATUS CaptureStatus,OwnershipStatus,CleanupStatus,OpenStatus,CloseStatus,AfterStatus;
  EFI_STATUS AdapterOwnershipStatus,AdapterCleanupStatus,DisableIoStatus;
  GU_DS_RESULT AdapterResult;
  GU_DO_RESULT Result;
} GU_DO_TRANSACTION;

/* TPL_APPLICATION only. Caller serializes all controller access and retains
 * handles/interfaces/storage for the complete call. Never reset/recreate a used
 * transaction to retry. EXCLUSIVE may implicitly stop drivers: no-manager queries
 * are observations, not locks. Trusted read-only callbacks/firmware are required.
 * No production entry point uses this library; no physical use is authorized. */
GU_DO_RESULT GuDsOwnedRun(GU_DO_TRANSACTION *Transaction,EFI_BOOT_SERVICES *Boot,
  EFI_HANDLE OwnerImage,const GU_DS_CAPTURE_TARGET *Target,
  BOOLEAN (*DurableLog)(VOID *,const char *),VOID *LogContext);
