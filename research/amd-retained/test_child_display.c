/* GPL-2.0-only. Actual child display gate and RAM-only firmware mocks. */
#define GU_EXACT_FIXTURE
#include "../../internal-boot/unlock/tests/test_3090_preflight.c"
#undef main
VOID GuLog(const char *,...);
VOID GuLogText(const char *);
#include "../../internal-boot/unlock/app.c"
#ifdef GU_AUTOMATIC_BOOT
#include "../../internal-boot/boot/media.h"
static UINT8 AutoUiMedia[46];
#endif

static UINT8 ActualAmdPath[36];
static const UINT8 HistoricalAmdPath[]={2,1,12,0,0xd0,0x41,3,0x0a,0,0,0,0,
  1,1,6,0,1,8,1,1,6,0,0,0,2,3,8,0,0,3,1,0x80,0x7f,0xff,4,0};
static unsigned ExtraFault,Duplicate,Cases;
static EFI_STATUS EFIAPI display_handle(EFI_HANDLE h,EFI_GUID *g,VOID **p) {
#ifdef GU_AUTOMATIC_BOOT
  if(h==H(2) && guid(g,&dg)){*p=AutoUiMedia;return EFI_SUCCESS;}
#endif
  if(h==H(5) && guid(g,&dg)){*p=ActualAmdPath;return EFI_SUCCESS;}
  return preflight_handle(h,g,p);
}
static EFI_STATUS EFIAPI display_location(EFI_PCI_IO_PROTOCOL *p,UINTN *s,UINTN *b,UINTN *d,UINTN *f) {
  if(ExtraFault>=1 && ExtraFault<=4) {
    CHECK(p==&amd);if(ExtraFault!=1)*s=0;if(ExtraFault!=2)*b=12;
    if(ExtraFault!=3)*d=0;if(ExtraFault!=4)*f=0;return EFI_SUCCESS;
  }
  EFI_STATUS result=amd_location(p,s,b,d,f);
  if(ExtraFault==7)amd.Pci.Read=NULL;
  return ExtraFault==5?EFI_WARN_UNKNOWN_GLYPH:result;
}
static EFI_STATUS EFIAPI display_read(EFI_PCI_IO_PROTOCOL *p,EFI_PCI_IO_PROTOCOL_WIDTH w,UINT32 o,UINTN n,VOID *v) {
  EFI_STATUS result=amd_read(p,w,o,n,v);
  if(ExtraFault==8 && o==0)amd.GetLocation=NULL;
  if(ExtraFault==9 && o==0x2c)amd.Pci.Read=NULL;
  return ExtraFault==6?EFI_WARN_UNKNOWN_GLYPH:result;
}
static EFI_STATUS EFIAPI display_locate(EFI_LOCATE_SEARCH_TYPE t,EFI_GUID *g,VOID *key,UINTN *n,EFI_HANDLE **h) {
  if(!Duplicate || !guid(g,&gg))return preflight_locate(t,g,key,n,h);
  *n=2;CHECK(allocate_pool(EfiLoaderData,2*sizeof(**h),(VOID **)h)==EFI_SUCCESS);
  (*h)[0]=(*h)[1]=H(5);return EFI_SUCCESS;
}
static void DisplaySetup(void) {
  app_setup(APP_SUCCESS);negative=ExtraFault=Duplicate=0;
  Cases++;AmdDisplayPathPinned=FALSE;memset(AmdDisplayPathPin,0,sizeof(AmdDisplayPathPin));
  memcpy(ActualAmdPath,HistoricalAmdPath,sizeof(ActualAmdPath));
  memset(&amd,0,sizeof(amd));amd.GetLocation=display_location;amd.Pci.Read=display_read;
  bs.HandleProtocol=display_handle;bs.LocateDevicePath=resolve;bs.LocateHandleBuffer=display_locate;
#ifdef GU_AUTOMATIC_BOOT
  memset(AutoUiMedia,0,sizeof(AutoUiMedia));AutoUiMedia[0]=4;AutoUiMedia[1]=1;AutoUiMedia[2]=42;
  AutoUiMedia[4]=1;AutoUiMedia[16]=1;memcpy(AutoUiMedia+24,&GuInternalPartition,16);
  AutoUiMedia[40]=AutoUiMedia[41]=2;memcpy(AutoUiMedia+42,"\x7f\xff\x04\x00",4);
#endif
  modes[0].FrameBufferBase=0xfce0000000ULL;modes[0].FrameBufferSize=8294400;
  infos[0].HorizontalResolution=infos[0].PixelsPerScanLine=1920;infos[0].VerticalResolution=1080;
  Table=&st;GuInit(&bs,NULL);CHECK(GuIoOpen(H(1),&st)==EFI_SUCCESS);
}
static void DisposeDisplay(void) {
  CHECK(!fake.mmio_writes && !fake.pci_writes && !fake.flrs && !disconnect_calls && !exclusive_calls);
  CHECK(!Gu.started && !Gu.armed);GuIoClose();dispose_host_fixture();
}
#ifdef GU_AUTOMATIC_BOOT
static unsigned AutoUiCase,AutoUiReads;
static EFI_STATUS EFIAPI AutoUiKey(EFI_SIMPLE_TEXT_INPUT_PROTOCOL *p,EFI_INPUT_KEY *k) {
  CHECK(p==&conin);AutoUiReads++;
  if(AutoUiCase==1){k->ScanCode=0x17;k->UnicodeChar=0;return EFI_SUCCESS;}
  return AutoUiCase==2?EFI_DEVICE_ERROR:AutoUiCase==3?EFI_WARN_UNKNOWN_GLYPH:EFI_NOT_READY;
}
static EFI_STATUS EFIAPI AutoUiReset(EFI_SIMPLE_TEXT_INPUT_PROTOCOL *p,BOOLEAN extended) {
  CHECK(p==&conin && !extended);return AutoUiCase==4?EFI_DEVICE_ERROR:EFI_SUCCESS;
}
static EFI_STATUS EFIAPI AutoUiStall(UINTN ticks) {
  CHECK(ticks==100000);return AutoUiCase==5?EFI_DEVICE_ERROR:EFI_SUCCESS;
}
#endif
int main(void) {
  DisplaySetup();ActualAmdPath[28]=1;
  CHECK(DisplayCheck()); /* FULL05/RUN08: same GPU, ADR 80010301. */
  CHECK(AmdDisplayPathPinned && SameAmdDisplayPath(ActualAmdPath,AmdDisplayPathPin));
  ActualAmdPath[28]=0;CHECK(!DisplayCheck());
  CHECK(AmdDisplayPathPinned && AmdDisplayPathPin[28]==1);
  ActualAmdPath[28]=1;CHECK(DisplayCheck());
  DisposeDisplay();
  for(unsigned byte=28;byte<32;byte++)for(unsigned bit=0;bit<8;bit++) {
    DisplaySetup();ActualAmdPath[byte]^=(UINT8)(1U<<bit);CHECK(DisplayCheck());
    ActualAmdPath[byte]^=(UINT8)(1U<<bit);CHECK(!DisplayCheck());DisposeDisplay();
  }
  for(unsigned byte=0;byte<36;byte++)if(byte<28 || byte>=32) {
    DisplaySetup();ActualAmdPath[byte]^=0x40;
    CHECK(!DisplayCheck() && !AmdDisplayPathPinned);DisposeDisplay();
  }
  for(unsigned fault=1;fault<=9;fault++) {
    DisplaySetup();ExtraFault=fault;CHECK(!DisplayCheck() && !AmdDisplayPathPinned);DisposeDisplay();
  }
  for(unsigned fault=2;fault<=7;fault++) {
    DisplaySetup();negative=fault;CHECK(!DisplayCheck() && !AmdDisplayPathPinned);DisposeDisplay();
  }
  DisplaySetup();negative=2;CHECK(!DisplayCheck() && !AmdDisplayPathPinned);
  negative=0;ActualAmdPath[28]=1;CHECK(DisplayCheck() && AmdDisplayPathPin[28]==1);DisposeDisplay();
  DisplaySetup();Duplicate=1;CHECK(!DisplayCheck() && !AmdDisplayPathPinned);DisposeDisplay();
  DisplaySetup();app_mode=APP_FLUSH;CHECK(!DisplayCheck() && !AmdDisplayPathPinned);DisposeDisplay();
  DisplaySetup();ActualAmdPath[28]=1;CHECK(DisplayCheck());
  /* A new EFI invocation must clear the old pin even when an earlier gate
   * refuses before DisplayCheck. All services remain RAM mocks. */
  GuIoClose();dispose_host_fixture();app_setup(APP_SUCCESS);
  CHECK(EFI_ERROR(efi_main(H(1),&st)) && !AmdDisplayPathPinned);
  DisposeDisplay();
#ifdef GU_AUTOMATIC_BOOT
  for(AutoUiCase=0;AutoUiCase<6;AutoUiCase++) {
    DisplaySetup();AutoUiReads=0;Gu.profile_verified=Gu.prom_verified=Gu.owned=Gu.display_ok=TRUE;
    memset(&PendingOwner,0,sizeof(PendingOwner));
    conin.ReadKeyStroke=AutoUiKey;conin.Reset=AutoUiReset;bs.Stall=AutoUiStall;
    EFI_STATUS result=Arm();
    CHECK(AutoUiCase?result!=EFI_SUCCESS:result==EFI_SUCCESS);
    CHECK(AutoUiCase || AutoUiReads==30); /* Thirty NOT_READY polls: no U. */
    Gu.owned=FALSE;DisposeDisplay();
  }
  puts("PASS automatic Arm: no-U countdown, Esc and input/reset/stall errors; RAM only");
#endif
  printf("PASS %u child AMD output/identity/pinning RAM scenarios; no hardware access\n",Cases);return 0;
}
