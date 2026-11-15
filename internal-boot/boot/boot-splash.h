/* SPDX-License-Identifier: GPL-2.0-only */
#pragma once
#include <Uefi.h>
#include <Protocol/SimpleFileSystem.h>

EFI_STATUS GuBootSplashBegin(EFI_SYSTEM_TABLE *Table, EFI_FILE_PROTOCOL *Volume);
EFI_STATUS GuBootSplashPlay(BOOLEAN Countdown, BOOLEAN *Skip);
EFI_STATUS GuBootSplashEnd(VOID);
BOOLEAN GuBootSplashVisible(VOID);
BOOLEAN GuBootSplashDirect(VOID);
UINTN GuBootSplashWidth(VOID);
UINTN GuBootSplashFrames(VOID);
