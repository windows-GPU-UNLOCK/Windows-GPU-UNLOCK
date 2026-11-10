/* GPL-2.0-only. Read-only current-boot collector; no entry point or correction. */
#pragma once
#include "efi-binding.h"

typedef struct {
  EFI_HANDLE Handle;
  UINTN Segment,Bus,PathBytes;
  UINT32 PciId,Subsystem,Bar0;
  UINT8 Path[GU_DS_EFI_MAX_PATH];
} GU_DS_CAPTURE_TARGET;

/* One private zero-initialized context. Do not reset/recreate it to retry.
 * Input/context/Boot storage must be disjoint and live throughout the call.
 * Alias/reuse rejection leaves existing storage unchanged. Require this call's
 * EFI_SUCCESS; Ready alone may describe an earlier capture. Ready is observational
 * only: no claim, GPU qualification or write approval. */
typedef struct {
  BOOLEAN Used,Busy,Ready;
  EFI_STATUS Status;
  UINTN Count;
  GU_DS_EFI_BINDING Bindings[1+GU_DS_EFI_MAX_PARENTS];
  GU_DS_SNAPSHOT Snapshot;
} GU_DS_CAPTURE;

EFI_STATUS GuDsEfiCapture(GU_DS_CAPTURE *Context,EFI_BOOT_SERVICES *Boot,const GU_DS_CAPTURE_TARGET *Target);

#ifdef GU_DS_POST_STOP_CAPTURE
#if GU_DS_POST_STOP_CAPTURE != 1
#error GU_DS_POST_STOP_CAPTURE must be exactly 1 when enabled
#endif
/* Research opt-in only. Freezes a corrected pre-Stop snapshot before callbacks.
 * Caller must obtain Before using the same pinned target (snapshots contain no
 * historical device path). Before must be disjoint from Context/Boot/Target.
 * Both scans must satisfy the
 * restricted post-Stop transition and agree exactly. No Stop/claim/restore occurs.
 * A NULL Before is rejected without touching Context. All other context lifetime,
 * single-use and current-return-status requirements above still apply. */
EFI_STATUS GuDsEfiCaptureAfterStop(GU_DS_CAPTURE *Context,EFI_BOOT_SERVICES *Boot,
  const GU_DS_CAPTURE_TARGET *Target,const GU_DS_SNAPSHOT *Before);
/* Separate hypothetical route: retain an actual raw2/cache300 baseline, and
 * observe only raw0/cache0 with the exact restricted GPU/parent delta. Output
 * Snapshot remains the actual observation; it is not a corrected-before value.
 * No Stop or restoration is performed or qualified by this API. */
EFI_STATUS GuDsEfiCaptureReleasedMismatch(GU_DS_CAPTURE *Context,EFI_BOOT_SERVICES *Boot,
  const GU_DS_CAPTURE_TARGET *Target,const GU_DS_SNAPSHOT *Before);
/* Release-only baseline; ordinary correction capture remains raw2-only. Both
 * coherent raw3/cache300 and the prior raw2 envelope are observational inputs.
 * Exact two-scan, frozen binding, single-use and alias rules remain unchanged. */
EFI_STATUS GuDsEfiCaptureReleaseOrigin(GU_DS_CAPTURE *Context,EFI_BOOT_SERVICES *Boot,
  const GU_DS_CAPTURE_TARGET *Target);
/* Separate coherent IO+MEM origin; never interprets raw2/cache300 as raw3.
 * Before must come from the same pinned target and remain independently frozen.
 * Only an unchanged or coherently reduced IO/MEM subset is observed. */
EFI_STATUS GuDsEfiCaptureIoMemAfterStop(GU_DS_CAPTURE *Context,EFI_BOOT_SERVICES *Boot,
  const GU_DS_CAPTURE_TARGET *Target,const GU_DS_SNAPSHOT *Before);
#endif
