/* GPL-2.0-only. Research library only; no EFI entry point or shipped build. */
#pragma once
#include "decode-sync.h"
#include "efi-binding.h"
#define GU_DS_EFI_MAX_OPENERS 64U
#ifdef GU_DS_POST_STOP_RESTORE
#if GU_DS_POST_STOP_RESTORE != 1
#error GU_DS_POST_STOP_RESTORE must be exactly 1 when enabled
#endif
#include "stop-transition.h"
typedef enum {
  GU_DR_INVALID,GU_DR_REUSED,GU_DR_READ_FAILED,GU_DR_LOG_FAILED,
  GU_DR_DRIFT,GU_DR_OWNERSHIP_FAILED,GU_DR_ENABLE_FAILED,
  GU_DR_UNCHANGED,GU_DR_RESTORED
} GU_DR_RESULT;
typedef struct {
  BOOLEAN Started,EnableInvoked,PostObserved,ReleasedOrigin;
  EFI_STATUS EnableStatus,ObservationStatus;
  GU_DR_RESULT Result;
} GU_DR_TRANSACTION;
#endif

/* One zero-initialized context. Treat initialized fields as private/immutable.
 * Caller retains the exclusive claim, input storage and interface lifetimes,
 * serializes the operation, and separately authorizes any future physical use.
 * Per-image workspace rejects Init/Run from callbacks, including fresh contexts.
 * Observing an open record does not acquire or lock a protocol. */
typedef struct {
  BOOLEAN InitUsed,Ready,RunUsed,Busy,WriteSpent,OwnershipFault;
  BOOLEAN OwnershipObserved,CleanupObserved,DisableInvoked;
  EFI_BOOT_SERVICES *Boot;
  EFI_HANDLE_PROTOCOL HandleProtocol;
  EFI_LOCATE_DEVICE_PATH LocateDevicePath;
  EFI_OPEN_PROTOCOL_INFORMATION OpenProtocolInformation;
  EFI_FREE_POOL FreePool;
  EFI_HANDLE OwnerImage;
  const GU_DS_EFI_BINDING *InputBindings;
  const GU_DS_SNAPSHOT *InputExpected;
  const VOID *CallerContext,*ActiveTransaction,*ActiveOutput;
#ifdef GU_DS_POST_STOP_RESTORE
  BOOLEAN RestoreMode;
  BOOLEAN ReleasedOrigin;
  const GU_DS_SNAPSHOT *InputReleasedAfter;
  const GU_DS_RELEASE_PLAN *InputReleasePlan;
  /* Private immutable originals. Expected is a planned target only when
   * ReleasedOrigin is TRUE; it must not be reported as observed pre-Stop data. */
  GU_DS_SNAPSHOT ReleasedBefore,ReleasedAfter;
  GU_DS_RELEASE_PLAN ReleasePlan;
#endif
  EFI_STATUS OwnershipStatus,CleanupStatus,DisableIoStatus;
  GU_DS_EFI_DEVICE Devices[1+GU_DS_EFI_MAX_PARENTS];
  GU_DS_SNAPSHOT Expected;
  BOOLEAN (*DurableLog)(VOID *Context,const char *Event);
  VOID *LogContext;
} GU_DS_EFI_CONTEXT;

/* Bindings[0] is GPU; following bindings are its immediate root-to-leaf parents.
 * Init is pure validation/copying and calls no firmware or log callback. */
EFI_STATUS GuDsEfiInitialize(GU_DS_EFI_CONTEXT *Context,EFI_BOOT_SERVICES *Boot,EFI_HANDLE OwnerImage,
  const GU_DS_EFI_BINDING *Bindings,UINTN Count,const GU_DS_SNAPSHOT *Expected,
  BOOLEAN (*DurableLog)(VOID *,const char *),VOID *LogContext);
GU_DS_RESULT GuDsEfiRun(GU_DS_EFI_CONTEXT *Context,GU_DS_TRANSACTION *Transaction);

#ifdef GU_DS_POST_STOP_RESTORE
/* Research-only, caller-held exclusive claim and retained lifetimes required.
 * Expected is the corrected memory-on baseline from before release, associated
 * with these same pinned bindings by the caller. No Stop/Open/Close occurs.
 * A successful result is observational, not hardware/firmware qualification. */
EFI_STATUS GuDsEfiInitializeRestore(GU_DS_EFI_CONTEXT *Context,EFI_BOOT_SERVICES *Boot,EFI_HANDLE OwnerImage,
  const GU_DS_EFI_BINDING *Bindings,UINTN Count,const GU_DS_SNAPSHOT *Expected,
  BOOLEAN (*DurableLog)(VOID *,const char *),VOID *LogContext);
GU_DR_RESULT GuDsEfiRestoreRun(GU_DS_EFI_CONTEXT *Context,GU_DR_TRANSACTION *Transaction);
/* Separate hypothesis-only origin, not the corrected-observed-before API.
 * Before/After remain actual snapshots; Plan is rederived, and all three are
 * copied into private context storage. Bindings must refer to this same target.
 * The caller retains the full originals, paths and exclusive claim throughout.
 * No release/Stop is performed or proven; no physical use is authorized. */
EFI_STATUS GuDsEfiInitializeReleasedRestore(GU_DS_EFI_CONTEXT *Context,EFI_BOOT_SERVICES *Boot,EFI_HANDLE OwnerImage,
  const GU_DS_EFI_BINDING *Bindings,UINTN Count,const GU_DS_SNAPSHOT *Before,
  const GU_DS_SNAPSHOT *After,const GU_DS_RELEASE_PLAN *Plan,
  BOOLEAN (*DurableLog)(VOID *,const char *),VOID *LogContext);
#endif
