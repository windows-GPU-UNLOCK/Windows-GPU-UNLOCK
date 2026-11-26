/* GPU-UNLOCK USB boot menu. GPL-2.0-only. Vibecoded with love by Claude.
 *
 * Shown first on every boot from the stick (\EFI\BOOT\BOOTX64.EFI):
 *   1. Windows + GPU-Unlock      -> \EFI\GPU-UNLOCK\UNLOCK.EFI (headless USB wrapper, unchanged)
 *   2. GPU dump, then Windows    -> \EFI\GPU-UNLOCK\PROBE.EFI  (generic read-only probe, unchanged)
 *   3. Windows without unlock    -> \EFI\Microsoft\Boot\bootmgfw.efi on the pinned Windows ESP
 * MENU_DEFAULT_ITEM starts after MENU_TIMEOUT_SECONDS; any key stops the timer.
 *
 * Two builds (build-menu.ps1):
 *   MENU_HAS_UNLOCK 0  dump phase: no profile yet. Item 1 is shown as not ready and refused;
 *                      the screen counts the dumps already on the stick.
 *   MENU_HAS_UNLOCK 1  normal: item 1 starts the unlock.
 *
 * The menu never touches the GPU: it prints text, reads keys, lists one directory on the
 * stick and chain-loads. Items 1 and 2 are read into memory, checked against the size and
 * SHA-256 compiled in by build-menu.ps1, and started from those exact bytes with a device
 * path on this same USB volume, so the wrapper's and probe's own USB/OwnDevice, child-hash
 * and Windows-ESP checks apply unchanged. It installs no driver binding, so the release-path
 * driver-image checks do not see it. If item 1 or 2 returns, nothing was released (the
 * wrapper stops instead of returning after release), so the menu falls back to item 3. */
#include <Uefi.h>
#include <Protocol/LoadedImage.h>
#include <Protocol/SimpleFileSystem.h>
#include <Protocol/DevicePath.h>
#include <Guid/FileInfo.h>
#include "media.h"
#include "sha256.h"
#include "menu-config.h"

#if MENU_DEFAULT_ITEM < 1 || MENU_DEFAULT_ITEM > 3
#error MENU_DEFAULT_ITEM must be 1, 2 or 3
#endif
#if MENU_TIMEOUT_SECONDS < 1 || MENU_TIMEOUT_SECONDS > 99
#error MENU_TIMEOUT_SECONDS must be 1..99
#endif
#if !MENU_HAS_UNLOCK && MENU_DEFAULT_ITEM == 1
#error a dump-phase menu cannot default to the unlock
#endif

#define TICK_US 100000U
#define LINE_WIDTH 79

static EFI_SYSTEM_TABLE *St;
static EFI_BOOT_SERVICES *Bs;
static EFI_HANDLE Self, OwnDevice;
static UINTN SavedAttribute;
static EFI_GUID LoadedGuid = EFI_LOADED_IMAGE_PROTOCOL_GUID;
static EFI_GUID FsGuid = EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID;
static EFI_GUID PathGuid = EFI_DEVICE_PATH_PROTOCOL_GUID;
static EFI_GUID InfoGuid = EFI_FILE_INFO_ID;

static VOID Say(const CHAR16 *Text) {
  if (St->ConOut) St->ConOut->OutputString(St->ConOut, (CHAR16 *)Text);
}

static VOID SayStatus(const CHAR16 *Prefix, EFI_STATUS Status) {
  CHAR16 text[24];
  UINTN n = 0;
  Say(Prefix);
  text[n++] = '0'; text[n++] = 'x';
  for (int i = 15; i >= 0; i--) text[n++] = (CHAR16)"0123456789abcdef"[((UINT64)Status >> (i * 4)) & 15];
  text[n++] = '\r'; text[n++] = '\n'; text[n] = 0;
  Say(text);
}

static UINTN Append(CHAR16 *Buffer, UINTN At, const CHAR16 *Text) {
  while (*Text && At < LINE_WIDTH) Buffer[At++] = *Text++;
  Buffer[At] = 0;
  return At;
}

static UINTN AppendNumber(CHAR16 *Buffer, UINTN At, UINTN Value) {
  CHAR16 digits[24];
  UINTN n = 0;
  do { digits[n++] = (CHAR16)('0' + Value % 10); Value /= 10; } while (Value && n < 20);
  while (n && At < LINE_WIDTH) Buffer[At++] = digits[--n];
  Buffer[At] = 0;
  return At;
}

/* One full-width line at a fixed row, so redraws need no ClearScreen. */
static VOID Line(UINTN Row, const CHAR16 *Text, BOOLEAN Highlight) {
  CHAR16 buffer[LINE_WIDTH + 1];
  UINTN n = 0;
  while (Text[n] && n < LINE_WIDTH) { buffer[n] = Text[n]; n++; }
  while (n < LINE_WIDTH) buffer[n++] = ' ';
  buffer[n] = 0;
  if (St->ConOut->SetCursorPosition) St->ConOut->SetCursorPosition(St->ConOut, 0, Row);
  if (Highlight && St->ConOut->SetAttribute) St->ConOut->SetAttribute(St->ConOut, EFI_BLACK | EFI_BACKGROUND_LIGHTGRAY);
  Say(buffer);
  if (Highlight && St->ConOut->SetAttribute) St->ConOut->SetAttribute(St->ConOut, SavedAttribute);
}

#if !MENU_HAS_UNLOCK
/* Number of DIAGnn.TXT files in \RTX3090-UNLOCK (completeness is checked later on Windows). */
static UINTN CountDumps(VOID) {
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *fs = NULL;
  EFI_FILE_PROTOCOL *root = NULL, *dir = NULL;
  UINTN count = 0;
  if (Bs->HandleProtocol(OwnDevice, &FsGuid, (VOID **)&fs) != EFI_SUCCESS || !fs) return 0;
  if (fs->OpenVolume(fs, &root) != EFI_SUCCESS || !root) return 0;
  if (root->Open(root, &dir, L"\\RTX3090-UNLOCK", EFI_FILE_MODE_READ, 0) == EFI_SUCCESS && dir) {
    for (UINTN guard = 0; guard < 4096; guard++) {
      union { EFI_FILE_INFO info; UINT8 bytes[1024]; } entry;
      UINTN size = sizeof(entry);
      if (dir->Read(dir, &size, &entry) != EFI_SUCCESS || size == 0) break;
      const CHAR16 *n = entry.info.FileName;
      if (!(entry.info.Attribute & EFI_FILE_DIRECTORY) &&
          (n[0] | 0x20) == 'd' && (n[1] | 0x20) == 'i' && (n[2] | 0x20) == 'a' && (n[3] | 0x20) == 'g' &&
          n[4] >= '0' && n[4] <= '9' && n[5] >= '0' && n[5] <= '9' && n[6] == '.' &&
          (n[7] | 0x20) == 't' && (n[8] | 0x20) == 'x' && (n[9] | 0x20) == 't' && n[10] == 0) count++;
    }
    dir->Close(dir);
  }
  root->Close(root);
  return count;
}
static UINTN Dumps;
#endif

static const CHAR16 *Notice = L"";

static VOID Draw(UINTN Selected, UINTN TicksLeft, BOOLEAN TimerOn) {
#if MENU_HAS_UNLOCK
  static const CHAR16 *Items[3] = {
    L"  1. Windows + GPU-Unlock",
    L"  2. GPU dump (read-only probe), then Windows without unlock",
    L"  3. Windows without GPU-Unlock",
  };
#else
  static const CHAR16 *Items[3] = {
    L"  1. Windows + GPU-Unlock          (not ready yet: no profile on this stick)",
    L"  2. GPU dump (read-only probe), then Windows without unlock",
    L"  3. Windows without GPU-Unlock",
  };
#endif
  CHAR16 text[LINE_WIDTH + 1];
  UINTN n;
  Line(0, L" GPU-UNLOCK boot menu", FALSE);
#if MENU_HAS_UNLOCK
  Line(1, L" Profile: " MENU_PROFILE_NAME, FALSE);
#else
  n = Append(text, 0, L" Dump phase: ");
  n = AppendNumber(text, n, Dumps);
  n = Append(text, n, L" dump(s) on this stick; 2 from full shutdowns are needed.");
  Line(1, text, FALSE);
#endif
  Line(2, L"", FALSE);
  for (UINTN i = 0; i < 3; i++) Line(3 + i, Items[i], i == Selected);
  Line(6, L"", FALSE);
  Line(7, L" Up/Down + Enter, or press 1, 2, 3.  Esc = 3.", FALSE);
  if (TimerOn) {
    n = Append(text, 0, L" Item ");
    n = AppendNumber(text, n, MENU_DEFAULT_ITEM);
    n = Append(text, n, L" starts in ");
    n = AppendNumber(text, n, (TicksLeft + 9) / 10);
    n = Append(text, n, L" s. Any key stops the timer.");
    Line(8, text, FALSE);
  } else {
    Line(8, L" Timer stopped. Choose an item.", FALSE);
  }
  Line(9, Notice, FALSE);
#if MENU_HAS_UNLOCK
  Line(10, L" After choosing 1: do not press any keys. The screen goes black for a moment,", FALSE);
  Line(11, L" then Windows starts. If it stays black: remove the stick, power off, power on.", FALSE);
#else
  Line(10, L" Press 2 only after a full shutdown (not Restart). After two dumps, run", FALSE);
  Line(11, L" make-stick.ps1 again: it builds the profile and adds the unlock to this stick.", FALSE);
#endif
  Line(12, L"", FALSE);
  Line(13, L" Vibecoded with love by Claude", FALSE);
}

static VOID DrainKeys(VOID) {
  if (!St->ConIn) return;
  for (UINTN i = 0; i < 64; i++) {
    EFI_INPUT_KEY key;
    if (St->ConIn->ReadKeyStroke(St->ConIn, &key) != EFI_SUCCESS) break;
  }
}

/* Item 1 without an unlock on the stick: refuse and stay in the menu. */
static BOOLEAN Allowed(UINTN Item) {
#if MENU_HAS_UNLOCK
  (void)Item;
  return TRUE;
#else
  if (Item != 0) return TRUE;
  Notice = L" Item 1 is not ready: take two dumps (item 2), then run make-stick.ps1 again.";
  return FALSE;
#endif
}

/* Returns 0, 1 or 2 for items 1-3. */
static UINTN Choose(VOID) {
  const UINTN fallback = MENU_DEFAULT_ITEM - 1;
  UINTN selected = fallback, ticks = MENU_TIMEOUT_SECONDS * 10U;
  BOOLEAN timer = TRUE;
  if (!St->ConIn || !St->ConIn->ReadKeyStroke) return fallback;
  DrainKeys();
  Draw(selected, ticks, timer);
  for (;;) {
    EFI_INPUT_KEY key;
    EFI_STATUS s = St->ConIn->ReadKeyStroke(St->ConIn, &key);
    if (s == EFI_SUCCESS) {
      timer = FALSE;
      if (key.UnicodeChar >= '1' && key.UnicodeChar <= '3') {
        UINTN item = (UINTN)(key.UnicodeChar - '1');
        if (Allowed(item)) return item;
        selected = item;
      } else if (key.UnicodeChar == CHAR_CARRIAGE_RETURN) {
        if (Allowed(selected)) return selected;
      } else if (key.ScanCode == SCAN_ESC || key.UnicodeChar == 27) {
        return 2;
      } else if (key.ScanCode == SCAN_UP) {
        selected = selected ? selected - 1 : 2;
      } else if (key.ScanCode == SCAN_DOWN) {
        selected = (selected + 1) % 3;
      }
      Draw(selected, ticks, timer);
      continue;
    }
    if (s != EFI_NOT_READY) return fallback; /* broken input: keep the default */
    Bs->Stall(TICK_US);
    if (timer) {
      if (--ticks == 0) return fallback;
      if (ticks % 10 == 0) Draw(selected, ticks, timer);
    }
  }
}

static EFI_STATUS PathFor(EFI_HANDLE Device, EFI_DEVICE_PATH_PROTOCOL **Out) {
  *Out = NULL;
  EFI_STATUS s = Bs->HandleProtocol(Device, &PathGuid, (VOID **)Out);
  return s == EFI_SUCCESS && *Out ? EFI_SUCCESS : EFI_UNSUPPORTED;
}

static EFI_STATUS FindPartition(const EFI_GUID *Guid, EFI_HANDLE *Out) {
  EFI_HANDLE *handles = NULL;
  UINTN count = 0, matches = 0;
  *Out = NULL;
  EFI_STATUS s = Bs->LocateHandleBuffer(ByProtocol, &FsGuid, NULL, &count, &handles);
  if (s != EFI_SUCCESS) return s;
  for (UINTN i = 0; i < count; i++) {
    EFI_DEVICE_PATH_PROTOCOL *p = NULL;
    if (PathFor(handles[i], &p) == EFI_SUCCESS && GuPathIsPartition(p, Guid)) { matches++; *Out = handles[i]; }
  }
  if (handles) Bs->FreePool(handles);
  return matches == 1 ? EFI_SUCCESS : matches ? EFI_COMPROMISED_DATA : EFI_NOT_FOUND;
}

static EFI_STATUS FilePath(EFI_HANDLE Device, const CHAR16 *Name, EFI_DEVICE_PATH_PROTOCOL **Out) {
  EFI_DEVICE_PATH_PROTOCOL *base = NULL;
  UINTN baseBytes = 0, chars = 0;
  *Out = NULL;
  EFI_STATUS s = PathFor(Device, &base);
  if (s != EFI_SUCCESS || !GuInspectPath(base, NULL, &baseBytes, NULL, NULL)) return EFI_UNSUPPORTED;
  while (Name[chars] && chars < 256) chars++;
  if (!chars || chars == 256) return EFI_INVALID_PARAMETER;
  UINTN nodeBytes = 4 + (chars + 1) * sizeof(CHAR16), total = baseBytes - 4 + nodeBytes + 4;
  UINT8 *data = NULL;
  s = Bs->AllocatePool(EfiBootServicesData, total, (VOID **)&data);
  if (s != EFI_SUCCESS || !data) return EFI_OUT_OF_RESOURCES;
  for (UINTN i = 0; i < baseBytes - 4; i++) data[i] = ((UINT8 *)base)[i];
  EFI_DEVICE_PATH_PROTOCOL *node = (VOID *)(data + baseBytes - 4);
  node->Type = MEDIA_DEVICE_PATH; node->SubType = MEDIA_FILEPATH_DP;
  node->Length[0] = (UINT8)nodeBytes; node->Length[1] = (UINT8)(nodeBytes >> 8);
  for (UINTN i = 0; i < (chars + 1) * sizeof(CHAR16); i++) ((UINT8 *)node)[4 + i] = ((const UINT8 *)Name)[i];
  EFI_DEVICE_PATH_PROTOCOL *end = (VOID *)((UINT8 *)node + nodeBytes);
  end->Type = END_DEVICE_PATH_TYPE; end->SubType = END_ENTIRE_DEVICE_PATH_SUBTYPE;
  end->Length[0] = 4; end->Length[1] = 0;
  *Out = (VOID *)data;
  return EFI_SUCCESS;
}

/* Read Name from this stick, require exact size and SHA-256, load from those bytes. */
static EFI_STATUS LoadVerified(const CHAR16 *Name, UINTN Bytes, const char *Sha256, EFI_HANDLE *Image) {
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL *fs = NULL;
  EFI_FILE_PROTOCOL *root = NULL, *file = NULL;
  UINT8 *data = NULL;
  *Image = NULL;
  EFI_STATUS s = Bs->HandleProtocol(OwnDevice, &FsGuid, (VOID **)&fs);
  if (s != EFI_SUCCESS || !fs) return EFI_UNSUPPORTED;
  s = fs->OpenVolume(fs, &root);
  if (s != EFI_SUCCESS || !root) return EFI_DEVICE_ERROR;
  s = root->Open(root, &file, (CHAR16 *)Name, EFI_FILE_MODE_READ, 0);
  if (s == EFI_SUCCESS && !file) s = EFI_NOT_FOUND;
  if (s == EFI_SUCCESS) {
    union { EFI_FILE_INFO info; UINT8 bytes[512]; } metadata;
    UINTN size = sizeof(metadata);
    s = file->GetInfo(file, &InfoGuid, &size, &metadata);
    if (s == EFI_SUCCESS && (size < sizeof(EFI_FILE_INFO) || metadata.info.FileSize != Bytes ||
                             (metadata.info.Attribute & EFI_FILE_DIRECTORY))) s = EFI_BAD_BUFFER_SIZE;
    if (s == EFI_SUCCESS) s = Bs->AllocatePool(EfiBootServicesData, Bytes, (VOID **)&data);
    if (s == EFI_SUCCESS && !data) s = EFI_OUT_OF_RESOURCES;
    if (s == EFI_SUCCESS) {
      size = Bytes;
      s = file->Read(file, &size, data);
      if (s == EFI_SUCCESS && size != Bytes) s = EFI_END_OF_FILE;
    }
    file->Close(file);
  }
  root->Close(root);
  if (s == EFI_SUCCESS && !GuHashMatches(data, Bytes, Sha256)) s = EFI_CRC_ERROR;
  EFI_DEVICE_PATH_PROTOCOL *path = NULL;
  if (s == EFI_SUCCESS) s = FilePath(OwnDevice, Name, &path);
  if (s == EFI_SUCCESS) s = Bs->LoadImage(FALSE, Self, path, data, Bytes, Image);
  if (path) Bs->FreePool(path);
  if (data) Bs->FreePool(data);
  if (s != EFI_SUCCESS) return s;
  EFI_LOADED_IMAGE_PROTOCOL *loaded = NULL;
  s = Bs->HandleProtocol(*Image, &LoadedGuid, (VOID **)&loaded);
  if (s != EFI_SUCCESS || !loaded || loaded->DeviceHandle != OwnDevice) {
    Bs->UnloadImage(*Image);
    *Image = NULL;
    return EFI_COMPROMISED_DATA;
  }
  return EFI_SUCCESS;
}

static EFI_STATUS BootWindows(VOID) {
  EFI_HANDLE windows = NULL, image = NULL;
  EFI_DEVICE_PATH_PROTOCOL *path = NULL;
  EFI_STATUS s = FindPartition(&GuWindowsPartition, &windows);
  if (s == EFI_SUCCESS && windows == OwnDevice) s = EFI_COMPROMISED_DATA;
  if (s == EFI_SUCCESS) s = FilePath(windows, L"\\EFI\\Microsoft\\Boot\\bootmgfw.efi", &path);
  if (s == EFI_SUCCESS) s = Bs->LoadImage(FALSE, Self, path, NULL, 0, &image);
  if (path) Bs->FreePool(path);
  if (s != EFI_SUCCESS) return s;
  return Bs->StartImage(image, NULL, NULL);
}

static VOID Pause(UINTN Seconds) {
  for (UINTN i = 0; i < Seconds * 10; i++) Bs->Stall(TICK_US);
}

EFI_STATUS EFIAPI efi_main(EFI_HANDLE Image, EFI_SYSTEM_TABLE *Table) {
  St = Table; Self = Image;
  if (!St || !St->BootServices || !St->ConOut) return EFI_NOT_STARTED;
  Bs = St->BootServices;
  /* The timer can be stopped and the menu left open; the firmware's 5 minute boot
     watchdog would otherwise reset the PC. The wrapper and probe disable it themselves. */
  Bs->SetWatchdogTimer(0, 0, 0, NULL);
  SavedAttribute = St->ConOut->Mode ? (UINTN)St->ConOut->Mode->Attribute : (EFI_LIGHTGRAY | EFI_BACKGROUND_BLACK);

  EFI_LOADED_IMAGE_PROTOCOL *loaded = NULL;
  EFI_DEVICE_PATH_PROTOCOL *ownPath = NULL;
  BOOLEAN usb = FALSE;
  EFI_STATUS s = Bs->HandleProtocol(Image, &LoadedGuid, (VOID **)&loaded);
  if (s == EFI_SUCCESS && loaded) OwnDevice = loaded->DeviceHandle;
  if (!OwnDevice || PathFor(OwnDevice, &ownPath) != EFI_SUCCESS || !GuInspectPath(ownPath, NULL, NULL, &usb, NULL) || !usb) {
    Say(L"GPU-UNLOCK menu: not started from a USB stick. Booting Windows without unlock.\r\n");
    s = BootWindows();
    SayStatus(L"Windows Boot Manager could not be started: ", s);
    return EFI_NOT_STARTED;
  }
#if !MENU_HAS_UNLOCK
  Dumps = CountDumps();
#endif

  St->ConOut->ClearScreen(St->ConOut);
  UINTN choice = Choose();
  DrainKeys();
  St->ConOut->SetAttribute(St->ConOut, SavedAttribute);
  St->ConOut->ClearScreen(St->ConOut);

  if (choice == 0 || choice == 1) {
    EFI_HANDLE child = NULL;
#if MENU_HAS_UNLOCK
    if (choice == 0) {
      Say(L"GPU-UNLOCK: starting the unlock. Do not press any keys.\r\n");
      s = LoadVerified(L"\\EFI\\GPU-UNLOCK\\UNLOCK.EFI", MENU_UNLOCK_BYTES, MENU_UNLOCK_SHA256, &child);
    } else
#endif
    {
      Say(L"GPU-UNLOCK: read-only GPU dump to this stick, then Windows.\r\n");
      s = LoadVerified(L"\\EFI\\GPU-UNLOCK\\PROBE.EFI", MENU_PROBE_BYTES, MENU_PROBE_SHA256, &child);
    }
    if (s == EFI_SUCCESS) s = Bs->StartImage(child, NULL, NULL);
    /* Reaching here means the image returned before touching the GPU (or failed to load). */
    SayStatus(L"\r\nGPU-UNLOCK: the selected item returned, status ", s);
    Say(L"Nothing was changed on the GPU. Starting Windows without unlock in 5 s...\r\n");
    Pause(5);
  }

  s = BootWindows();
  SayStatus(L"\r\nGPU-UNLOCK: Windows Boot Manager could not be started, status ", s);
  Say(L"Returning to the firmware boot order in 10 s.\r\n");
  Pause(10);
  return EFI_NOT_STARTED;
}
