/* GPL-2.0-only. Actual production config reader; RAM services only. */
#include "full-release.c"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static EFI_SYSTEM_TABLE TestTable,OtherTable;
static EFI_BOOT_SERVICES TestBoot,OtherBoot;
static EFI_PCI_IO_PROTOCOL TestIo,OtherIo;
static UINT32 Config[64],Output[64],Original[64];
static UINTN Callback,At,Action,Reads,SkipRead,SkipByte,MissingLocation,MissingAt,DriftWord;
static BOOLEAN Drift,MapChanged;
static unsigned Cases;
#define CHECK(x) do { if(!(x)){fprintf(stderr,"ASSERTION FAILED line %d case %u\n",__LINE__,Cases);exit(1);} } while(0)
static EFI_STATUS EFIAPI TestHandle(EFI_HANDLE,EFI_GUID *,VOID **);
static EFI_STATUS EFIAPI TestLocation(EFI_PCI_IO_PROTOCOL *,UINTN *,UINTN *,UINTN *,UINTN *);
static EFI_STATUS EFIAPI TestRead(EFI_PCI_IO_PROTOCOL *,EFI_PCI_IO_PROTOCOL_WIDTH,UINT32,UINTN,VOID *);
static EFI_STATUS Boundary(VOID) {
  CHECK(!Drift);Callback++;
  if(Callback!=At)return EFI_SUCCESS;
  if(Action==1)return EFI_WARN_UNKNOWN_GLYPH;
  if(Action==2)return EFI_DEVICE_ERROR;
  Drift=TRUE;
  switch(Action) {
  case 3:TestIo.Pci.Read=NULL;break;
  case 4:TestIo.GetLocation=NULL;break;
  case 5:TestBoot.HandleProtocol=NULL;break;
  case 6:PreparedPlan.RtxIo=&OtherIo;break;
  case 7:PreparedPlan.RtxPci=(EFI_HANDLE)2;break;
  case 8:Full.Table=&OtherTable;break;
  case 9:TestTable.BootServices=&OtherBoot;break;
  case 10:TestIo.Pci.Read=(EFI_PCI_IO_PROTOCOL_CONFIG)(UINTN)1;break;
  case 11:break; /* HandleProtocol returns a different interface below. */
  case 12:MapChanged=TRUE;Drift=FALSE;break;
  default:CHECK(FALSE);
  }
  return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI TestHandle(EFI_HANDLE h,EFI_GUID *g,VOID **out) {
  CHECK(h==(EFI_HANDLE)1 && GuGuidEqual(g,&PciGuid));*out=MapChanged?&OtherIo:&TestIo;
  EFI_STATUS s=Boundary();
  if(Action==11 && Callback==At){*out=&OtherIo;Drift=TRUE;}
  return s;
}
static EFI_STATUS EFIAPI TestLocation(EFI_PCI_IO_PROTOCOL *io,UINTN *s,UINTN *b,UINTN *d,UINTN *f) {
  CHECK(io==&TestIo);
  UINTN missing=Callback+1==MissingAt?MissingLocation:0;
  if(missing!=1)*s=GU_TARGET_SEGMENT;
  if(missing!=2)*b=GU_TARGET_BUS;
  if(missing!=3)*d=0;
  if(missing!=4)*f=0;
  return Boundary();
}
static EFI_STATUS EFIAPI TestRead(EFI_PCI_IO_PROTOCOL *io,EFI_PCI_IO_PROTOCOL_WIDTH width,UINT32 offset,UINTN count,VOID *out) {
  CHECK(io==&TestIo && width==EfiPciIoWidthUint32 && !offset && count==64);Reads++;
  for(UINTN i=0;i<sizeof(Config);i++)
    if(!((!SkipRead || SkipRead==Reads) && i==SkipByte))((UINT8 *)out)[i]=((UINT8 *)Config)[i];
  if(Reads==2 && DriftWord<64)((UINT32 *)out)[DriftWord]^=1;
  return Boundary();
}
static VOID Setup(VOID) {
  Cases++;Callback=At=Action=Reads=SkipRead=MissingLocation=MissingAt=0;SkipByte=sizeof(Config);DriftWord=64;Drift=MapChanged=FALSE;
  Full=(FULL){0};PreparedPlan=(PLAN){0};
  TestTable=(EFI_SYSTEM_TABLE){0};TestBoot=(EFI_BOOT_SERVICES){0};TestIo=(EFI_PCI_IO_PROTOCOL){0};
  TestTable.BootServices=&TestBoot;TestBoot.HandleProtocol=TestHandle;
  TestIo.GetLocation=TestLocation;TestIo.Pci.Read=TestRead;
  Full.Table=&TestTable;PreparedPlan.RtxIo=&TestIo;PreparedPlan.RtxPci=(EFI_HANDLE)1;
  for(UINTN i=0;i<64;i++){Config[i]=0x11111111U;Original[i]=Output[i]=0xc3c3c3c3U;}
  Config[0]=GU_BOARD_ID;Config[1]=2;Config[2]=0x030000a1;Config[4]=(UINT32)GU_BAR0_BASE;Config[11]=GU_BOARD_SUBSYSTEM;
}
static VOID Refused(VOID) {
  CHECK(ReadConfigFull(Output)!=EFI_SUCCESS);CHECK(!memcmp(Output,Original,sizeof(Output)));
}
int main(VOID) {
  for(UINTN command=0;command<4;command++) {
    Setup();Config[1]=(UINT32)command;
    Config[60]=0xa5a5a5a5U;Config[61]=0x5a5a5a5aU;Config[62]=0xffffffffU;Config[63]=0;
    CHECK(ReadConfigFull(Output)==EFI_SUCCESS && Reads==2 && Callback==11);
    CHECK(!memcmp(Output,Config,sizeof(Output)));
  }
  Setup();At=10;Action=12;Refused();CHECK(Reads==2);
  const UINTN locations[]={2,5,7,10};
  for(UINTN where=0;where<4;where++)for(UINTN field=1;field<=4;field++) {
    Setup();MissingLocation=field;MissingAt=locations[where];Refused();CHECK(Callback==MissingAt);
  }
  for(UINTN read=0;read<=2;read++)for(UINTN byte=0;byte<256;byte++) {
    Setup();SkipRead=read;SkipByte=byte;Refused();
  }
  for(UINTN word=0;word<64;word++){Setup();DriftWord=word;Refused();}
  for(UINTN at=1;at<=11;at++)for(UINTN action=1;action<=10;action++) {
    Setup();At=at;Action=action;Refused();CHECK(Callback==at);
  }
  for(UINTN at=1;at<=11;at++)if(at==1 || at==4 || at==6 || at==9 || at==11) {
    Setup();At=at;Action=11;Refused();CHECK(Callback==at);
  }
  Setup();Config[1]|=4;Refused();
  Setup();CHECK(ReadConfigFull(NULL)==EFI_INVALID_PARAMETER && !Callback);
  printf("PASS %u production config-reader scenarios; RAM only, output unchanged on refusal\n",Cases);
  return 0;
}
