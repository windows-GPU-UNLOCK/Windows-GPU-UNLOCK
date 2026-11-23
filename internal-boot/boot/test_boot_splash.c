/* SPDX-License-Identifier: GPL-2.0-only */
/* Production player, simulated UEFI. All video destinations are ordinary RAM. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#undef NULL
#include "boot-splash.c"

typedef struct {
    UINT64 Due;
    UINT64 Period;
} TEST_TIMER;

typedef struct {
    UINTN ShortRead;
    UINTN ReadError;
    UINTN Allocation;
    BOOLEAN NullAllocation;
    BOOLEAN OpenError;
    BOOLEAN CloseFileError;
    BOOLEAN FreeError;
    BOOLEAN ExtraByte;
    BOOLEAN NoClock;
    BOOLEAN SplitConsole;
    UINTN Outputs;
    BOOLEAN BltError;
    UINTN CreateEvent;
    UINTN SetTimer;
    UINTN WaitEvent;
    UINTN CloseEvent;
    BOOLEAN InputError;
} FAULTS;

static EFI_SYSTEM_TABLE System;
static EFI_BOOT_SERVICES Services;
static EFI_SIMPLE_TEXT_INPUT_PROTOCOL Input;
static EFI_GRAPHICS_OUTPUT_PROTOCOL Graphics;
static EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE GraphicsMode;
static EFI_GRAPHICS_OUTPUT_MODE_INFORMATION Info;
static EFI_TIMESTAMP_PROTOCOL Timestamp;
static EFI_FILE_PROTOCOL Volume, File;
static UINT8 *Fixture, *Original;
static UINTN FixtureSize, Position;
static FAULTS Fault;
static UINTN Checks, Reads, Allocations, Opens, Files, Pools, Events;
static UINTN Creates, Sets, Waits, Closes, Blts, Stamps;
static UINT64 Now, EscapeAt, BltDelay, StampStep;
static UINT8 *DisplayAllocation;
static UINT32 *Display;
static UINTN DisplayBytes;

static void Check(int condition, const char *message) {
    Checks++;
    if (!condition) {
        fprintf(stderr, "FAIL %s (reads=%zu alloc=%zu events=%zu)\n", message, Reads, Allocations, Events);
        exit(1);
    }
}

static VOID *Guarded(UINTN bytes) {
    UINT8 *allocation = malloc(bytes + 32);
    Check(allocation != NULL, "test allocation succeeds");
    memset(allocation, 0xa5, bytes + 32);
    return allocation + 16;
}

static void CheckGuard(const VOID *buffer, UINTN bytes) {
    const UINT8 *allocation = (const UINT8 *)buffer - 16;
    for (UINTN index = 0; index < 16; index++) {
        Check(allocation[index] == 0xa5 && allocation[bytes + 16 + index] == 0xa5,
              "guard bytes unchanged");
    }
}

static EFI_STATUS EFIAPI Allocate(EFI_MEMORY_TYPE type, UINTN bytes, VOID **result) {
    (void)type;
    *result = NULL;
    Allocations++;
    if (Allocations == Fault.Allocation) return Fault.NullAllocation ? EFI_SUCCESS : EFI_OUT_OF_RESOURCES;
    *result = calloc(1, bytes);
    if (!*result) return EFI_OUT_OF_RESOURCES;
    Pools++;
    return EFI_SUCCESS;
}

static EFI_STATUS EFIAPI Release(VOID *buffer) {
    Check(buffer != NULL && Pools > 0, "release a live allocation once");
    free(buffer);
    Pools--;
    return Fault.FreeError ? EFI_DEVICE_ERROR : EFI_SUCCESS;
}

static EFI_STATUS EFIAPI Open(EFI_FILE_PROTOCOL *volume, EFI_FILE_PROTOCOL **result,
                              CHAR16 *path, UINT64 mode, UINT64 attributes) {
    (void)attributes;
    Check(volume == &Volume && mode == EFI_FILE_MODE_READ, "asset is opened read-only");
    const CHAR16 expected[] = L"\\EFI\\WindowsGPUUnlock\\SPLASH.BIN";
    Check(memcmp(path, expected, sizeof(expected)) == 0, "generic asset path");
    Opens++;
    *result = NULL;
    if (Fault.OpenError) return EFI_NOT_FOUND;
    Position = 0;
    *result = &File;
    Files++;
    return EFI_SUCCESS;
}

static EFI_STATUS EFIAPI Read(EFI_FILE_PROTOCOL *file, UINTN *bytes, VOID *buffer) {
    Check(file == &File && Files == 1, "read a live file");
    Reads++;
    if (Reads == Fault.ReadError) return EFI_DEVICE_ERROR;
    UINTN available = FixtureSize - Position;
    UINTN size = *bytes < available ? *bytes : available;
    if (Position == FixtureSize && Fault.ExtraByte && *bytes) {
        *(UINT8 *)buffer = 1;
        *bytes = 1;
        return EFI_SUCCESS;
    }
    if (Reads == Fault.ShortRead && size) size--;
    memcpy(buffer, Fixture + Position, size);
    Position += size;
    *bytes = size;
    return EFI_SUCCESS;
}

static EFI_STATUS EFIAPI CloseFile(EFI_FILE_PROTOCOL *file) {
    Check(file == &File && Files == 1, "close asset exactly once");
    Files--;
    return Fault.CloseFileError ? EFI_DEVICE_ERROR : EFI_SUCCESS;
}

static EFI_STATUS EFIAPI GetHandle(EFI_HANDLE handle, EFI_GUID *guid, VOID **result) {
    (void)guid;
    *result = NULL;
    if (handle == System.ConsoleOutHandle && Fault.SplitConsole) return EFI_UNSUPPORTED;
    *result = &Graphics;
    return EFI_SUCCESS;
}

static EFI_STATUS EFIAPI LocateHandles(EFI_LOCATE_SEARCH_TYPE search, EFI_GUID *guid,
                                       VOID *key, UINTN *count, EFI_HANDLE **handles) {
    (void)search; (void)guid; (void)key;
    *handles = NULL;
    *count = Fault.Outputs;
    if (!*count) return EFI_NOT_FOUND;
    EFI_STATUS status = Allocate(EfiBootServicesData, *count * sizeof(EFI_HANDLE), (VOID **)handles);
    if (status == EFI_SUCCESS && *handles) {
        for (UINTN index = 0; index < *count; index++) (*handles)[index] = (EFI_HANDLE)(index + 1);
    }
    return status;
}

static EFI_STATUS EFIAPI Blit(EFI_GRAPHICS_OUTPUT_PROTOCOL *graphics, PIXEL *pixels,
                              EFI_GRAPHICS_OUTPUT_BLT_OPERATION operation,
                              UINTN sx, UINTN sy, UINTN dx, UINTN dy,
                              UINTN width, UINTN height, UINTN delta) {
    Check(graphics == &Graphics, "use simulated GOP only");
    Check(dx <= Info.HorizontalResolution && width <= Info.HorizontalResolution - dx &&
          dy <= Info.VerticalResolution && height <= Info.VerticalResolution - dy,
          "GOP destination stays in the display");
    Blts++;
    Now += BltDelay;
    if (Fault.BltError) return EFI_DEVICE_ERROR;
    Check(operation == EfiBltVideoFill || operation == EfiBltBufferToVideo, "supported drawing operation");
    if (operation == EfiBltBufferToVideo) {
        Check(sx + width <= MATRIX_WIDTH && sy + height <= MATRIX_HEIGHT &&
              delta == MATRIX_WIDTH * sizeof(PIXEL), "GOP source stays in decoded surface");
    }
    for (UINTN y = 0; y < height; y++) {
        for (UINTN x = 0; x < width; x++) {
            PIXEL pixel = operation == EfiBltVideoFill ? *pixels : pixels[(sy + y) * MATRIX_WIDTH + sx + x];
            UINT32 packed = pixel.Blue | ((UINT32)pixel.Green << 8) | ((UINT32)pixel.Red << 16);
            if (Info.PixelFormat == PixelRedGreenBlueReserved8BitPerColor)
                packed = pixel.Red | ((UINT32)pixel.Green << 8) | ((UINT32)pixel.Blue << 16);
            Display[(dy + y) * Info.PixelsPerScanLine + dx + x] = packed;
        }
    }
    return EFI_SUCCESS;
}

static UINT64 EFIAPI GetStamp(VOID) { Stamps++; Now += StampStep; return Now; }

static EFI_STATUS EFIAPI GetProperties(EFI_TIMESTAMP_PROPERTIES *properties) {
    properties->Frequency = 10000000;
    properties->EndValue = ~(UINT64)0;
    return EFI_SUCCESS;
}

static EFI_STATUS EFIAPI LocateClock(EFI_GUID *guid, VOID *registration, VOID **result) {
    (void)guid; (void)registration;
    *result = Fault.NoClock ? NULL : &Timestamp;
    return Fault.NoClock ? EFI_NOT_FOUND : EFI_SUCCESS;
}

static EFI_STATUS EFIAPI CreateEvent(UINT32 type, EFI_TPL tpl, EFI_EVENT_NOTIFY callback,
                                     VOID *context, EFI_EVENT *result) {
    (void)context;
    Check(type == EVT_TIMER && tpl == TPL_CALLBACK && !callback, "synchronous graphics with timer events");
    *result = NULL;
    if (++Creates == Fault.CreateEvent) return EFI_OUT_OF_RESOURCES;
    *result = calloc(1, sizeof(TEST_TIMER));
    Check(*result != NULL, "allocate simulated timer");
    Events++;
    return EFI_SUCCESS;
}

static EFI_STATUS EFIAPI SetTimer(EFI_EVENT event, EFI_TIMER_DELAY kind, UINT64 interval) {
    if (++Sets == Fault.SetTimer) return EFI_DEVICE_ERROR;
    TEST_TIMER *timer = event;
    timer->Due = Now + interval;
    timer->Period = kind == TimerPeriodic ? interval : 0;
    return EFI_SUCCESS;
}

static EFI_STATUS EFIAPI WaitEvent(UINTN count, EFI_EVENT *events, UINTN *index) {
    if (++Waits == Fault.WaitEvent) return EFI_DEVICE_ERROR;
    UINT64 next = ~(UINT64)0;
    *index = 0;
    for (UINTN at = 0; at < count; at++) {
        if (events[at] == Input.WaitForKey) continue;
        TEST_TIMER *timer = events[at];
        if (timer->Due < next) { next = timer->Due; *index = at; }
    }
    Check(next != ~(UINT64)0, "wait has an armed timer");
    if (Now < next) Now = next;
    TEST_TIMER *timer = events[*index];
    timer->Due = timer->Period ? timer->Due + timer->Period : ~(UINT64)0;
    return EFI_SUCCESS;
}

static EFI_STATUS EFIAPI CloseEvent(EFI_EVENT event) {
    Check(event != NULL && Events > 0, "close a live event once");
    free(event);
    Events--;
    return ++Closes == Fault.CloseEvent ? EFI_DEVICE_ERROR : EFI_SUCCESS;
}

static EFI_STATUS EFIAPI ReadKey(EFI_SIMPLE_TEXT_INPUT_PROTOCOL *input, EFI_INPUT_KEY *key) {
    Check(input == &Input, "read simulated keyboard");
    if (Fault.InputError) return EFI_DEVICE_ERROR;
    if (Now < EscapeAt) return EFI_NOT_READY;
    key->ScanCode = 0x17;
    key->UnicodeChar = 0;
    return EFI_SUCCESS;
}

static void Setup(UINT32 width, UINT32 height) {
    Check(!St && !Pools && !Events && !Files, "previous session fully closed");
    if (DisplayAllocation) {
        CheckGuard(Display, DisplayBytes);
        free(DisplayAllocation);
    }
    memset(&Fault, 0, sizeof(Fault));
    memset(&Info, 0, sizeof(Info));
    memcpy(Fixture, Original, FixtureSize);
    Position = Reads = Allocations = Opens = Creates = Sets = Waits = Closes = Blts = Stamps = 0;
    Now = BltDelay = StampStep = 0;
    EscapeAt = ~(UINT64)0;
    Info.HorizontalResolution = width;
    Info.VerticalResolution = height;
    Info.PixelsPerScanLine = (width + 31U) & ~31U;
    Info.PixelFormat = PixelRedGreenBlueReserved8BitPerColor;
    DisplayBytes = (UINTN)Info.PixelsPerScanLine * height * 4;
    Display = Guarded(DisplayBytes);
    DisplayAllocation = (UINT8 *)Display - 16;
    memset(&GraphicsMode, 0, sizeof(GraphicsMode));
    GraphicsMode.Info = &Info;
    GraphicsMode.SizeOfInfo = sizeof(Info);
    GraphicsMode.FrameBufferBase = (UINTN)Display;
    GraphicsMode.FrameBufferSize = DisplayBytes;
    Graphics.Mode = &GraphicsMode;
    Graphics.Blt = Blit;
    Timestamp.GetTimestamp = GetStamp;
    Timestamp.GetProperties = GetProperties;
    Services.AllocatePool = Allocate;
    Services.FreePool = Release;
    Services.HandleProtocol = GetHandle;
    Services.LocateHandleBuffer = LocateHandles;
    Services.LocateProtocol = LocateClock;
    Services.CreateEvent = CreateEvent;
    Services.SetTimer = SetTimer;
    Services.WaitForEvent = WaitEvent;
    Services.CloseEvent = CloseEvent;
    Input.ReadKeyStroke = ReadKey;
    Input.WaitForKey = (EFI_EVENT)&Input;
    System.BootServices = &Services;
    System.ConIn = &Input;
    System.ConsoleOutHandle = (EFI_HANDLE)&System;
    Volume.Open = Open;
    File.Read = Read;
    File.Close = CloseFile;
}

static void Finish(EFI_STATUS expected) {
    Check(GuBootSplashEnd() == expected, "teardown reports status");
    Check(!Pools && !Events && !Files && !GuBootSplashVisible(), "all acquired resources released");
    UINTN blits = Blts, stamps = Stamps;
    BOOLEAN skip = FALSE;
    Check(GuBootSplashEnd() == EFI_SUCCESS, "teardown is idempotent");
    Check(GuBootSplashPlay(TRUE, &skip) == EFI_INVALID_PARAMETER, "play after teardown is rejected");
    MatrixDraw(1);
    Check(Blts == blits && Stamps == stamps, "zero graphics and timestamp callbacks after teardown");
    CheckGuard(Display, DisplayBytes);
}

static void RejectBegin(EFI_STATUS expected) {
    Check(GuBootSplashBegin(&System, &Volume) == expected, "begin rejects fault with expected status");
    Check(!St && !Pools && !Files && !Blts, "failed load closes resources before graphics");
    Finish(EFI_SUCCESS);
}

static void TestFiles(void) {
    Setup(1920, 1080);
    Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "valid pinned fixture loads");
    UINTN readCount = Reads;
    Check(readCount >= 4, "fixture exercises multiple chunk reads and EOF");
    Finish(EFI_SUCCESS);
    for (UINTN index = 1; index < readCount; index++) {
        Setup(1920, 1080); Fault.ShortRead = index;
        RejectBegin(index == 1 ? EFI_COMPROMISED_DATA : EFI_DEVICE_ERROR);
    }
    for (UINTN index = 1; index <= readCount; index++) {
        Setup(1920, 1080); Fault.ReadError = index; RejectBegin(EFI_DEVICE_ERROR);
    }
    Setup(1920, 1080); Fault.OpenError = TRUE; RejectBegin(EFI_NOT_FOUND);
    Setup(1920, 1080); Fault.CloseFileError = TRUE; RejectBegin(EFI_DEVICE_ERROR);
    Setup(1920, 1080); Fault.ExtraByte = TRUE; RejectBegin(EFI_COMPROMISED_DATA);
    Setup(1920, 1080); Fixture[FixtureSize - 1] ^= 1; RejectBegin(EFI_CRC_ERROR);
    const UINTN fields[] = {0, 1, 2, 3, 4, 5, 6, 6, 6, 117};
    const UINT32 values[] = {0, 0, 1919, 1079, 111, 1, 0, MATRIX_LIMIT + 1,
                             MATRIX_PIXELS * 2U + 65537U, MATRIX_LIMIT};
    for (UINTN index = 0; index < sizeof(fields) / sizeof(fields[0]); index++) {
        Setup(1920, 1080);
        ((UINT32 *)Fixture)[fields[index]] = values[index];
        RejectBegin(EFI_COMPROMISED_DATA);
    }
    for (UINTN index = 1; index <= 4; index++) {
        Setup(1920, 1080); Fault.Allocation = index;
        RejectBegin(EFI_OUT_OF_RESOURCES);
        Setup(1920, 1080); Fault.Allocation = index; Fault.NullAllocation = TRUE;
        RejectBegin(EFI_OUT_OF_RESOURCES);
    }
    puts("PASS file headers, offsets, hash pins, short/error reads, EOF and allocation failures");
}

static void TestDecoder(void) {
    UINT16 *output = Guarded(MATRIX_PIXELS * 2U);
    const UINT32 *offsets = (const UINT32 *)Original + 5;
    for (UINTN frame = 0; frame < MATRIX_FRAMES; frame++) {
        const UINT8 *data = Original + 472 + offsets[frame];
        UINTN size = offsets[frame + 1] - offsets[frame];
        Check(MatrixDecode(data, size, output), "every synthetic frame decodes");
        Check(output[0] == (frame % 2 ? 0x001f : 0xf800) && output[MATRIX_PIXELS - 1] == output[0],
              "overlapping LZ4 match reproduces expected pixels");
        Check(!MatrixDecode(data, size - 1, output), "truncated trailing literals rejected");
    }
    const UINT8 bad[][6] = {{0}, {0xf0}, {0x20,1}, {0,0,0}, {0,1,0}, {0x1f,1,1,0}, {0x10,1,1}};
    const UINTN sizes[] = {0, 1, 2, 3, 3, 4, 3};
    for (UINTN index = 0; index < sizeof(sizes) / sizeof(sizes[0]); index++)
        Check(!MatrixDecode(bad[index], sizes[index], output), "malformed LZ4 rejected");
    UINT8 *oversized = malloc(MATRIX_PIXELS * 2U / 255U + 32U);
    Check(oversized != NULL, "allocate overflow fixture");
    oversized[0] = 0xf0;
    memset(oversized + 1, 255, MATRIX_PIXELS * 2U / 255U + 30U);
    Check(!MatrixDecode(oversized, MATRIX_PIXELS * 2U / 255U + 31U, output), "literal length overflow rejected");
    oversized[0] = 0x1f; oversized[1] = 1; oversized[2] = 1; oversized[3] = 0;
    Check(!MatrixDecode(oversized, MATRIX_PIXELS * 2U / 255U + 31U, output), "match length overflow rejected");
    CheckGuard(output, MATRIX_PIXELS * 2U);
    free((UINT8 *)output - 16);
    free(oversized);
    puts("PASS LZ4 decoding, overlap, truncation, backreferences and output guards");
}

static UINTN WriteLength(UINT8 *destination, UINTN length) {
    UINTN bytes = 0;
    while (length >= 255) { destination[bytes++] = 255; length -= 255; }
    destination[bytes++] = (UINT8)length;
    return bytes;
}

static void CheckRepeatedBlock(UINTN literal, UINTN distance, UINTN match) {
    const UINTN capacity = MATRIX_PIXELS * 2U;
    UINT8 *encoded = malloc(capacity + capacity / 255U + 32U);
    UINT8 *decoded = Guarded(capacity);
    Check(encoded != NULL && literal + match + 5 == capacity && match >= 4,
          "valid independent LZ4 reference case");
    UINTN size = 0;
    encoded[size++] = (UINT8)(((literal < 15 ? literal : 15) << 4) | (match < 19 ? match - 4 : 15));
    if (literal >= 15) size += WriteLength(encoded + size, literal - 15);
    for (UINTN index = 0; index < literal; index++) encoded[size++] = (UINT8)((index % distance) * 37U);
    encoded[size++] = (UINT8)distance;
    encoded[size++] = (UINT8)(distance >> 8);
    if (match >= 19) size += WriteLength(encoded + size, match - 19);
    encoded[size++] = 0x50;
    for (UINTN index = capacity - 5; index < capacity; index++) encoded[size++] = (UINT8)((index % distance) * 37U);
    Check(MatrixDecode(encoded, size, (UINT16 *)decoded), "decode repeated block across copy boundaries");
    UINTN index = 0;
    while (index < capacity && decoded[index] == (UINT8)((index % distance) * 37U)) index++;
    Check(index == capacity, "all decoded bytes equal independently generated periodic data");
    CheckGuard(decoded, capacity);
    free(encoded); free(decoded - 16);
}

static void TestVectorCopies(void) {
    const UINTN distances[] = {1,2,3,5,7,8,9,15,16,17,24,31,32,33,63,64,127,255,256,4095,4096,65535};
    for (UINTN index = 0; index < sizeof(distances) / sizeof(distances[0]); index++) {
        UINTN distance = distances[index];
        CheckRepeatedBlock(distance, distance, MATRIX_PIXELS * 2U - distance - 5U);
    }
    const UINTN matches[] = {4,5,7,8,15,16,17,31,32,33};
    for (UINTN index = 0; index < sizeof(matches) / sizeof(matches[0]); index++)
        CheckRepeatedBlock(MATRIX_PIXELS * 2U - matches[index] - 5U, 3, matches[index]);
    for (UINTN color = 0; color < 65536; color += 4) {
        UINT16 words[] = {(UINT16)color, (UINT16)(color + 1), (UINT16)(color + 2), (UINT16)(color + 3)};
        MATRIX_QUAD rgb = MatrixPackedFour(words, TRUE), bgr = MatrixPackedFour(words, FALSE);
        for (UINTN index = 0; index < 4; index++) {
            Check(rgb[index] == MatrixPacked(words[index], TRUE) && bgr[index] == MatrixPacked(words[index], FALSE),
                  "vector conversion preserves every RGB565 color in both output layouts");
        }
    }
    puts("PASS repeated-pattern distances, vector-copy tails and all 65536 RGB565 colors");
}

static void TestPlayback(void) {
    Setup(1920, 1080);
    Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "start playback");
    BOOLEAN skip = FALSE;
    Check(GuBootSplashPlay(TRUE, &skip) == EFI_SUCCESS && !skip && Now == 30000000,
          "countdown deadline is three seconds");
    UINT64 before = Now;
    Check(GuBootSplashPlay(FALSE, &skip) == EFI_SUCCESS && Now - before == 7333333 && MatrixFrame == 111,
          "burst ends on the final frame");
    Finish(EFI_SUCCESS);
    Setup(1920, 1080); EscapeAt = 5000000;
    Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "start cancellation case");
    Check(GuBootSplashPlay(TRUE, &skip) == EFI_SUCCESS && skip && Now < 30000000, "Esc cancels countdown");
    Finish(EFI_SUCCESS);
    for (UINTN index = 1; index <= 2; index++) {
        Setup(1920, 1080); Fault.CreateEvent = index;
        Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "timer creation failure setup");
        Check(GuBootSplashPlay(TRUE, &skip) == EFI_OUT_OF_RESOURCES && !Events, "partial timer creation cleanup");
        Finish(EFI_SUCCESS);
        Setup(1920, 1080); Fault.SetTimer = index;
        Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "timer configuration failure setup");
        Check(GuBootSplashPlay(TRUE, &skip) == EFI_DEVICE_ERROR && !Events, "timer configuration failure cleanup");
        Finish(EFI_SUCCESS);
        Setup(1920, 1080); Fault.CloseEvent = index; EscapeAt = 0;
        Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "timer close failure setup");
        Check(GuBootSplashPlay(TRUE, &skip) == EFI_DEVICE_ERROR && !Events, "all timer closes attempted after error");
        Finish(EFI_SUCCESS);
    }
    Setup(1920, 1080); Fault.WaitEvent = 1;
    Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "wait failure setup");
    Check(GuBootSplashPlay(TRUE, &skip) == EFI_DEVICE_ERROR && !Events, "wait error closes events");
    Finish(EFI_SUCCESS);
    Setup(1920, 1080); Fault.InputError = TRUE;
    Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "input failure setup");
    Check(GuBootSplashPlay(TRUE, &skip) == EFI_DEVICE_ERROR && !Events, "input error closes events");
    Finish(EFI_SUCCESS);
    Setup(1920, 1080);
    Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "free failure setup");
    Fault.FreeError = TRUE;
    Finish(EFI_DEVICE_ERROR);
    puts("PASS countdown, burst, Esc, timer/input failures and teardown lifecycle");
}

static void TestGraphics(void) {
    for (UINTN format = 0; format <= PixelBltOnly; format++) {
        Setup(1920, 1080); Info.PixelFormat = (EFI_GRAPHICS_PIXEL_FORMAT)format;
        Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "GOP supports standard pixel formats");
        MATRIX_FRAMEBUFFER surface;
        Check(MatrixFramebuffer(&surface, 1920, 1080) == (format < PixelBitMask),
              "direct writes restricted to compatible RGB/BGR surfaces");
        if (format < PixelBitMask) {
            memcpy(MatrixCurrent, MatrixPrevious, MATRIX_PIXELS * sizeof(UINT16));
            MatrixWriteFramebuffer(&surface, FALSE);
            Check(Display[0] == (format == PixelRedGreenBlueReserved8BitPerColor ? 0xffU : 0xff0000U),
                  "direct RGB/BGR pixel packing");
        }
        Finish(EFI_SUCCESS);
    }
    Setup(1920, 1080); Info.PixelFormat = PixelFormatMax; RejectBegin(EFI_UNSUPPORTED);
    Setup(1920, 1080); Fault.NoClock = TRUE; RejectBegin(EFI_UNSUPPORTED);
    Setup(1280, 720); RejectBegin(EFI_UNSUPPORTED);
    Setup(1920, 1080); Fault.SplitConsole = TRUE; RejectBegin(EFI_UNSUPPORTED);
    Setup(1920, 1080); Fault.SplitConsole = TRUE; Fault.Outputs = 2; RejectBegin(EFI_UNSUPPORTED);
    Setup(1920, 1080); Fault.SplitConsole = TRUE; Fault.Outputs = 1;
    Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "single physical GOP behind console splitter");
    Finish(EFI_SUCCESS);
    Setup(1920, 1080); Fault.BltError = TRUE;
    Check(GuBootSplashBegin(&System, &Volume) == EFI_DEVICE_ERROR && !Pools && !St, "initial blit failure cleans up");
    Finish(EFI_SUCCESS);
    for (UINTN change = 0; change < 11; change++) {
        Setup(1920, 1080);
        Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "geometry drift setup");
        switch (change) {
            case 0: Info.HorizontalResolution++; break;
            case 1: Info.VerticalResolution++; break;
            case 2: GraphicsMode.Mode++; break;
            case 3: GraphicsMode.SizeOfInfo = 0; break;
            case 4: Graphics.Mode = NULL; break;
            case 5: GraphicsMode.Info = NULL; break;
            case 6: GraphicsMode.FrameBufferSize = 1; MatrixDirect = TRUE; break;
            case 7: Info.PixelFormat = PixelBlueGreenRedReserved8BitPerColor; break;
            case 8: Info.PixelsPerScanLine += 32; break;
            case 9: GraphicsMode.FrameBufferBase += 16; break;
            case 10: GraphicsMode.FrameBufferSize -= 16; break;
        }
        UINTN before = Blts;
        MatrixDraw(1);
        Check(!GuBootSplashVisible() && Blts == before, "geometry drift stops drawing before a graphics call");
        Finish(EFI_SUCCESS);
    }
    puts("PASS GOP formats, ambiguous outputs, blit failure and geometry drift");
}

static void TestLargeDisplays(void) {
    Setup(3840, 2160);
    StampStep = 100; BltDelay = 500000;
    Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS && MatrixDirect && MatrixOutputWidth == 3840,
          "4K selects the faster direct path and a proportional viewport");
    Check(Display[0] == 0xffU && Display[1] == Display[0] && Display[Info.PixelsPerScanLine] == Display[0],
          "4K doubles the decoded pixels correctly");
    MatrixDraw(1);
    Check(Display[0] == 0xff0000U && Display[3840U * 2160U - 1] == 0xff0000U, "4K delta updates reach last pixel");
    Finish(EFI_SUCCESS);
    Setup(3840, 2160);
    StampStep = 250000; BltDelay = 1000000;
    Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS && MatrixDirect && MatrixOutputWidth == 1920,
          "slow 4K retains centered Full HD direct rendering");
    UINTN center = 540U * Info.PixelsPerScanLine + 960U;
    Check(Display[0] == 0 && Display[center] == 0xffU, "4K fallback clears margins and centers artwork");
    Finish(EFI_SUCCESS);
    Setup(3440, 1440);
    StampStep = 100; BltDelay = 500000;
    Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS && MatrixOutputWidth == 2560 && MatrixOutputHeight == 1440,
          "ultrawide keeps a centered 16 by 9 viewport");
    Check(Display[439] == 0 && Display[440] == 0xffU && Display[2999] == 0xffU && Display[3000] == 0,
          "fractional scaling preserves ultrawide side margins");
    MATRIX_FRAMEBUFFER surface;
    GraphicsMode.FrameBufferBase += 1;
    Check(!MatrixFramebuffer(&surface, 1920, 1080), "reject misaligned framebuffer");
    GraphicsMode.FrameBufferBase = (UINTN)Display;
    Info.PixelsPerScanLine = 3439;
    Check(!MatrixFramebuffer(&surface, 1920, 1080), "reject short row stride");
    Info.PixelsPerScanLine = 9000;
    Check(!MatrixFramebuffer(&surface, 1920, 1080), "reject oversized row stride");
    Info.PixelsPerScanLine = 3456;
    GraphicsMode.FrameBufferBase = (~(UINT64)0) & ~15ULL;
    Check(!MatrixFramebuffer(&surface, 1920, 1080), "reject address overflow");
    Finish(EFI_SUCCESS);
    puts("PASS 4K selection/fallback, ultrawide scaling, alignment, stride and address bounds");
}

int main(int argc, char **argv) {
    Check(argc == 2 || argc == 4, "synthetic asset argument");
    FILE *input = fopen(argv[1], "rb");
    Check(input != NULL, "open synthetic fixture");
    FixtureSize = GU_SPLASH_BYTES;
    Original = malloc(FixtureSize);
    Fixture = malloc(FixtureSize);
    Check(Original && Fixture, "allocate synthetic file buffers");
    Check(fread(Original, 1, FixtureSize, input) == FixtureSize && fgetc(input) == EOF, "read entire fixture");
    fclose(input);
    if (argc == 4) {
        Check(strcmp(argv[2], "--bad-frame") == 0, "malformed frame case");
        UINTN frame = (UINTN)strtoul(argv[3], NULL, 10);
        Setup(1920, 1080);
        Check(GuHashMatches(Fixture, FixtureSize, GU_SPLASH_SHA256), "malformed fixture has a valid pinned hash");
        if (!frame) {
            Check(GuBootSplashBegin(&System, &Volume) == EFI_DEVICE_ERROR && !St && !Pools && !Blts,
                  "malformed first frame fails begin and releases resources");
        } else {
            Check(GuBootSplashBegin(&System, &Volume) == EFI_SUCCESS, "valid first frame loads");
            UINTN before = Blts;
            MatrixDraw(frame);
            Check(!GuBootSplashVisible() && Blts == before, "malformed later frame stops before graphics");
        }
        Finish(EFI_SUCCESS);
        CheckGuard(Display, DisplayBytes);
        free(DisplayAllocation); free(Fixture); free(Original);
        printf("PASS pinned malformed frame %zu and teardown\n", frame);
        return 0;
    }
    TestFiles();
    TestDecoder();
    TestVectorCopies();
    TestPlayback();
    TestGraphics();
    TestLargeDisplays();
    CheckGuard(Display, DisplayBytes);
    free(DisplayAllocation);
    free(Fixture);
    free(Original);
    printf("PASS %zu checks; production player, CPU-only simulated UEFI\n", Checks);
    return 0;
}
