/* SPDX-License-Identifier: GPL-2.0-only */
#include "boot-splash.h"
#include <Protocol/GraphicsOutput.h>
#include <Protocol/Timestamp.h>
#include "../unlock/sha256.h"
#include "build/headless/splash-contract.h"

typedef EFI_GRAPHICS_OUTPUT_BLT_PIXEL PIXEL;
static EFI_SYSTEM_TABLE *St;
static EFI_GRAPHICS_OUTPUT_PROTOCOL *Gop;
static EFI_GRAPHICS_OUTPUT_PROTOCOL_MODE *Mode;
static EFI_TIMESTAMP_PROTOCOL *Clock;
static EFI_TIMESTAMP_PROPERTIES ClockProperties;
static UINT32 Width,Height,ModeNumber;
static UINTN PresentedFrames;
static BOOLEAN Visible;
static UINT64 Stamp(VOID){return Clock?Clock->GetTimestamp():0;}
static UINT64 Micros(UINT64 start,UINT64 now){
 if(!Clock||start>ClockProperties.EndValue||now>ClockProperties.EndValue)return 0;
 UINT64 ticks=now>=start?now-start:ClockProperties.EndValue-start+1+now;
 // Bound arithmetic and reject a broken/wandering optional firmware counter.
 if(ticks>ClockProperties.Frequency*60)return 0;
 return ticks/ClockProperties.Frequency*1000000+(ticks%ClockProperties.Frequency)*1000000/ClockProperties.Frequency;
}
static VOID FindClock(VOID){
 Clock=NULL;EFI_GUID guid=EFI_TIMESTAMP_PROTOCOL_GUID;
 if(!St->BootServices->LocateProtocol)return;
 EFI_TIMESTAMP_PROTOCOL *candidate=NULL;EFI_TIMESTAMP_PROPERTIES properties;
 if(St->BootServices->LocateProtocol(&guid,NULL,(VOID**)&candidate)!=EFI_SUCCESS||!candidate||!candidate->GetTimestamp||!candidate->GetProperties)return;
 if(candidate->GetProperties(&properties)!=EFI_SUCCESS||!properties.Frequency||properties.Frequency>1000000000000ULL||properties.EndValue/properties.Frequency<10)return;
 Clock=candidate;ClockProperties=properties;
}
static BOOLEAN Geometry(VOID) {
 return Visible&&Gop&&Gop->Mode==Mode&&Mode->Info&&
        Mode->SizeOfInfo>=sizeof(*Mode->Info)&&Mode->Mode==ModeNumber&&
        Mode->Info->HorizontalResolution==Width&&Mode->Info->VerticalResolution==Height;
}
#define MATRIX_WIDTH 1920U
#define MATRIX_HEIGHT 1080U
#define MATRIX_FRAMES 112U
#define MATRIX_PIXELS (MATRIX_WIDTH * MATRIX_HEIGHT)
#define MATRIX_LIMIT (192U * 1024U * 1024U)
#define MATRIX_MAX_WIDTH (2U * MATRIX_WIDTH)
#define MATRIX_MAX_HEIGHT (2U * MATRIX_HEIGHT)
#define MATRIX_PROBE_BUDGET_US 24000U

static EFI_FILE_PROTOCOL *MatrixVolume;
static UINT8 *MatrixAsset;
static UINT16 *MatrixCurrent, *MatrixPrevious;
static PIXEL *MatrixPixels;
static UINT32 MatrixOffsets[MATRIX_FRAMES + 1];
static UINTN MatrixFrame;
static UINTN MatrixOutputWidth=MATRIX_WIDTH, MatrixOutputHeight=MATRIX_HEIGHT;
static UINT16 MatrixColumns[MATRIX_MAX_WIDTH], MatrixRows[MATRIX_MAX_HEIGHT];
static BOOLEAN MatrixHasFrame, MatrixDirect;

/* Decode one independent LZ4 block. Every length and backreference is bounded. */
static BOOLEAN MatrixLength(const UINT8 **source, const UINT8 *end, UINTN *length) {
 if(*length!=15)return TRUE;
 UINT8 next;
 do {
  if(*source==end)return FALSE;
  next=*(*source)++;
  *length+=next;
  if(*length>MATRIX_PIXELS*2U)return FALSE;
 }while(next==255);
 return TRUE;
}

static BOOLEAN MatrixDecode(const UINT8 *source, UINTN bytes, UINT16 *pixels) {
 const UINT8 *end=source+bytes;
 UINT8 *output=(UINT8*)pixels;
 UINTN written=0, capacity=MATRIX_PIXELS*2U;
 while(source<end){
  UINT8 token=*source++;
  UINTN literal=token>>4;
  if(!MatrixLength(&source,end,&literal)||literal>(UINTN)(end-source)||literal>capacity-written)return FALSE;
  for(UINTN i=0;i<literal;i++)output[written++]=*source++;
  if(source==end)return written==capacity;
  if(end-source<2)return FALSE;
  UINTN offset=(UINTN)source[0]|((UINTN)source[1]<<8);
  source+=2;
  UINTN match=token&15U;
  if(!offset||offset>written||!MatrixLength(&source,end,&match)||match+4>capacity-written)return FALSE;
  match+=4;
  for(UINTN i=0;i<match;i++){output[written]=output[written-offset];written++;}
 }
 return FALSE;
}

static EFI_STATUS MatrixClose(VOID) {
 EFI_STATUS status=EFI_SUCCESS;
 VOID *buffers[]={MatrixAsset,MatrixCurrent,MatrixPrevious,MatrixPixels};
 for(UINTN i=0;i<sizeof(buffers)/sizeof(buffers[0]);i++)if(buffers[i]){
  EFI_STATUS released=St->BootServices->FreePool(buffers[i]);
  if(status==EFI_SUCCESS)status=released;
 }
 MatrixAsset=NULL;MatrixCurrent=NULL;MatrixPrevious=NULL;MatrixPixels=NULL;
 MatrixHasFrame=FALSE;MatrixDirect=FALSE;
 MatrixOutputWidth=MATRIX_WIDTH;MatrixOutputHeight=MATRIX_HEIGHT;
 return status;
}

static EFI_STATUS MatrixLoad(VOID) {
 if(!MatrixVolume||!MatrixVolume->Open||Width<MATRIX_WIDTH||Height<MATRIX_HEIGHT)return EFI_UNSUPPORTED;
 EFI_FILE_PROTOCOL *file=NULL;
 EFI_STATUS status=MatrixVolume->Open(MatrixVolume,&file,L"\\EFI\\WindowsGPUUnlock\\SPLASH.BIN",EFI_FILE_MODE_READ,0);
 if(status!=EFI_SUCCESS)return status;
 if(!file)return EFI_DEVICE_ERROR;
 UINT32 header[5+MATRIX_FRAMES+1];
 UINTN size=sizeof(header);
 status=file->Read(file,&size,header);
 if(status==EFI_SUCCESS&&(size!=sizeof(header)||header[0]!=0x414d5547U||header[1]!=0x31305854U||
    header[2]!=MATRIX_WIDTH||header[3]!=MATRIX_HEIGHT||header[4]!=MATRIX_FRAMES||header[5]!=0))status=EFI_COMPROMISED_DATA;
 if(status==EFI_SUCCESS){
  for(UINTN i=0;i<=MATRIX_FRAMES;i++){
   MatrixOffsets[i]=header[5+i];
   if(i&&(MatrixOffsets[i]<=MatrixOffsets[i-1]||MatrixOffsets[i]>MATRIX_LIMIT||
      MatrixOffsets[i]-MatrixOffsets[i-1]>MATRIX_PIXELS*2U+65536U)){status=EFI_COMPROMISED_DATA;break;}
  }
 }
 if(status==EFI_SUCCESS&&sizeof(header)+MatrixOffsets[MATRIX_FRAMES]!=GU_SPLASH_BYTES)status=EFI_COMPROMISED_DATA;
 if(status==EFI_SUCCESS)status=St->BootServices->AllocatePool(EfiBootServicesData,GU_SPLASH_BYTES,(VOID**)&MatrixAsset);
 if(status==EFI_SUCCESS&&!MatrixAsset)status=EFI_OUT_OF_RESOURCES;
 if(status==EFI_SUCCESS)for(UINTN i=0;i<sizeof(header);i++)MatrixAsset[i]=((const UINT8*)header)[i];
 for(UINTN read=sizeof(header);status==EFI_SUCCESS&&read<GU_SPLASH_BYTES;){
  UINTN remaining=GU_SPLASH_BYTES-read;
  UINTN requested=remaining>1048576U?1048576U:remaining;
  size=requested;
  status=file->Read(file,&size,MatrixAsset+read);
  if(status==EFI_SUCCESS&&size!=requested)status=EFI_DEVICE_ERROR;
  read+=requested;
 }
 if(status==EFI_SUCCESS){
  UINT8 extra;size=1;status=file->Read(file,&size,&extra);
  if(status==EFI_SUCCESS&&size!=0)status=EFI_COMPROMISED_DATA;
 }
 EFI_STATUS closed=file->Close(file);
 if(status==EFI_SUCCESS)status=closed;
 if(status==EFI_SUCCESS&&!GuHashMatches(MatrixAsset,GU_SPLASH_BYTES,GU_SPLASH_SHA256))status=EFI_CRC_ERROR;
 if(status==EFI_SUCCESS)status=St->BootServices->AllocatePool(EfiBootServicesData,MATRIX_PIXELS*sizeof(UINT16),(VOID**)&MatrixCurrent);
 if(status==EFI_SUCCESS)status=St->BootServices->AllocatePool(EfiBootServicesData,MATRIX_PIXELS*sizeof(UINT16),(VOID**)&MatrixPrevious);
 if(status==EFI_SUCCESS)status=St->BootServices->AllocatePool(EfiBootServicesData,MATRIX_PIXELS*sizeof(PIXEL),(VOID**)&MatrixPixels);
 if(status==EFI_SUCCESS&&(!MatrixCurrent||!MatrixPrevious||!MatrixPixels))status=EFI_OUT_OF_RESOURCES;
 if(status!=EFI_SUCCESS){(void)MatrixClose();return status;}
 return EFI_SUCCESS;
}

static UINTN MatrixLeft(UINTN width) {return ((Width-width)/2U)&~(UINTN)3U;}

static EFI_STATUS MatrixCopy(UINTN x,UINTN y,UINTN width,UINTN height) {
 for(UINTN row=y;row<y+height;row++)for(UINTN col=x;col<x+width;col++){
  UINTN i=row*MATRIX_WIDTH+col;
  UINT16 color=MatrixCurrent[i];
  UINT8 red=(UINT8)(color>>11),green=(UINT8)((color>>5)&63U),blue=(UINT8)(color&31U);
  MatrixPixels[i]=(PIXEL){(UINT8)((blue<<3)|(blue>>2)),(UINT8)((green<<2)|(green>>4)),(UINT8)((red<<3)|(red>>2)),0};
 }
 return Gop->Blt(Gop,MatrixPixels,EfiBltBufferToVideo,x,y,MatrixLeft(MATRIX_WIDTH)+x,(Height-MATRIX_HEIGHT)/2+y,width,height,MATRIX_WIDTH*sizeof(PIXEL));
}

static BOOLEAN MatrixChanged(UINTN x,UINTN y) {
 for(UINTN row=y;row<y+24;row++)for(UINTN col=x;col<x+64;col++){
  UINTN i=row*MATRIX_WIDTH+col;
  if(MatrixCurrent[i]!=MatrixPrevious[i])return TRUE;
 }
 return FALSE;
}

typedef struct {
 UINTN Base;
 UINTN Pitch;
 BOOLEAN Rgb;
} MATRIX_FRAMEBUFFER;
typedef UINT32 MATRIX_QUAD __attribute__((vector_size(16)));

/* Only the linear pixel surface explicitly exposed by the current GOP mode.
 * Leave hardware registers, PCI mappings and cache attributes alone. */
static BOOLEAN MatrixFramebuffer(MATRIX_FRAMEBUFFER *surface,UINTN width,UINTN height) {
 if(!Geometry()||!width||width>Width||width%4U||!height||height>Height)return FALSE;
 EFI_GRAPHICS_OUTPUT_MODE_INFORMATION *info=Mode->Info;
 if(info->PixelFormat!=PixelRedGreenBlueReserved8BitPerColor&&
    info->PixelFormat!=PixelBlueGreenRedReserved8BitPerColor)return FALSE;
 if(info->PixelsPerScanLine<Width||info->PixelsPerScanLine>8192||Height>4320)return FALSE;
 UINTN pitch=(UINTN)info->PixelsPerScanLine*4U;
 UINTN used=Height*pitch;
 UINT64 base=Mode->FrameBufferBase;
 if(!base||(base&15U)||(pitch&15U)||used>Mode->FrameBufferSize||
    base>(UINT64)(UINTN)-1-used)return FALSE;
 surface->Base=(UINTN)base+((Height-height)/2U)*pitch+MatrixLeft(width)*4U;
 surface->Pitch=pitch;
 surface->Rgb=info->PixelFormat==PixelRedGreenBlueReserved8BitPerColor;
 return TRUE;
}

static UINT32 MatrixPacked(UINT16 color,BOOLEAN rgb) {
 UINT32 red=color>>11,green=(color>>5)&63U,blue=color&31U;
 red=(red<<3)|(red>>2);
 green=(green<<2)|(green>>4);
 blue=(blue<<3)|(blue>>2);
 return rgb?red|(green<<8)|(blue<<16):blue|(green<<8)|(red<<16);
}

static VOID MatrixWriteFramebuffer(const MATRIX_FRAMEBUFFER *surface,BOOLEAN delta) {
 for(UINTN y=0;y<MATRIX_HEIGHT;y++){
  const UINT16 *row=MatrixCurrent+y*MATRIX_WIDTH;
  const UINT16 *previous=MatrixPrevious+y*MATRIX_WIDTH;
  UINTN destination=surface->Base+y*surface->Pitch;
  for(UINTN x=0;x<MATRIX_WIDTH;x+=16){
   if(delta){
    UINTN i=0;
    while(i<16&&row[x+i]==previous[x+i])i++;
    if(i==16)continue;
   }
   for(UINTN i=x;i<x+16;i+=4){
    MATRIX_QUAD pixels={
     MatrixPacked(row[i],surface->Rgb),MatrixPacked(row[i+1],surface->Rgb),
     MatrixPacked(row[i+2],surface->Rgb),MatrixPacked(row[i+3],surface->Rgb)
    };
    __builtin_nontemporal_store(pixels,(volatile MATRIX_QUAD *)(destination+i*4U));
   }
  }
 }
 __builtin_ia32_sfence();
}

static UINTN MatrixFitUnits(VOID) {
 UINTN horizontal=Width/16U,vertical=Height/9U;
 UINTN units=horizontal<vertical?horizontal:vertical;
 return units<MATRIX_MAX_WIDTH/16U?units:MATRIX_MAX_WIDTH/16U;
}

static VOID MatrixWriteDouble(const MATRIX_FRAMEBUFFER *surface,BOOLEAN delta) {
 for(UINTN y=0;y<MATRIX_HEIGHT;y++){
  const UINT16 *row=MatrixCurrent+y*MATRIX_WIDTH;
  const UINT16 *previous=MatrixPrevious+y*MATRIX_WIDTH;
  UINTN top=surface->Base+2U*y*surface->Pitch;
  UINTN bottom=top+surface->Pitch;
  for(UINTN x=0;x<MATRIX_WIDTH;x+=16){
   if(delta){
    UINTN i=0;
    while(i<16&&row[x+i]==previous[x+i])i++;
    if(i==16)continue;
   }
   for(UINTN i=x;i<x+16;i+=2){
    UINT32 first=MatrixPacked(row[i],surface->Rgb),second=MatrixPacked(row[i+1],surface->Rgb);
    MATRIX_QUAD pixels={first,first,second,second};
    __builtin_nontemporal_store(pixels,(volatile MATRIX_QUAD *)(top+i*8U));
    __builtin_nontemporal_store(pixels,(volatile MATRIX_QUAD *)(bottom+i*8U));
   }
  }
 }
 __builtin_ia32_sfence();
}

static VOID MatrixWriteScaled(const MATRIX_FRAMEBUFFER *surface,UINTN width,UINTN height,BOOLEAN delta) {
 if(width==MATRIX_MAX_WIDTH&&height==MATRIX_MAX_HEIGHT){MatrixWriteDouble(surface,delta);return;}
 for(UINTN y=0;y<height;y++){
  const UINT16 *row=MatrixCurrent+MatrixRows[y]*MATRIX_WIDTH;
  const UINT16 *previous=MatrixPrevious+MatrixRows[y]*MATRIX_WIDTH;
  UINTN destination=surface->Base+y*surface->Pitch;
  for(UINTN x=0;x<width;x+=4){
   UINTN a=MatrixColumns[x],b=MatrixColumns[x+1],c=MatrixColumns[x+2],d=MatrixColumns[x+3];
   if(delta&&row[a]==previous[a]&&row[b]==previous[b]&&row[c]==previous[c]&&row[d]==previous[d])continue;
   MATRIX_QUAD pixels={MatrixPacked(row[a],surface->Rgb),MatrixPacked(row[b],surface->Rgb),
                       MatrixPacked(row[c],surface->Rgb),MatrixPacked(row[d],surface->Rgb)};
   __builtin_nontemporal_store(pixels,(volatile MATRIX_QUAD *)(destination+x*4U));
  }
 }
 __builtin_ia32_sfence();
}

static VOID MatrixPrepareScale(UINTN width,UINTN height) {
 for(UINTN x=0;x<width;x++)MatrixColumns[x]=(UINT16)(x*MATRIX_WIDTH/width);
 for(UINTN y=0;y<height;y++)MatrixRows[y]=(UINT16)(y*MATRIX_HEIGHT/height);
}

static BOOLEAN MatrixFitsBudget(UINT64 decodeUs,UINT64 writeUs) {
 return decodeUs&&writeUs&&decodeUs<MATRIX_PROBE_BUDGET_US&&writeUs<=MATRIX_PROBE_BUDGET_US-decodeUs;
}

static EFI_STATUS MatrixProbeScale(const MATRIX_FRAMEBUFFER *native,UINT64 decodeUs) {
 UINTN units=MatrixFitUnits(),width=units*16U,height=units*9U;
 MATRIX_FRAMEBUFFER surface;
 if(width<=MATRIX_WIDTH||!MatrixFramebuffer(&surface,width,height))return EFI_SUCCESS;
 if(width!=MATRIX_MAX_WIDTH||height!=MATRIX_MAX_HEIGHT)MatrixPrepareScale(width,height);
 UINT64 start=Stamp();
 MatrixWriteScaled(&surface,width,height,FALSE);
 if(MatrixFitsBudget(decodeUs,Micros(start,Stamp()))){
  MatrixOutputWidth=width;MatrixOutputHeight=height;
  return EFI_SUCCESS;
 }
 PIXEL black={0,0,0,0};
 EFI_STATUS status=Gop->Blt(Gop,&black,EfiBltVideoFill,0,0,MatrixLeft(width),(Height-height)/2U,width,height,0);
 if(status==EFI_SUCCESS)MatrixWriteFramebuffer(native,FALSE);
 return status;
}

static VOID MatrixDraw(UINTN frame) {
 if(!Geometry()){Visible=FALSE;return;}
 if(frame>=MATRIX_FRAMES||(MatrixHasFrame&&frame==MatrixFrame))return;
 UINT64 start=Stamp();
 UINT32 offset=MatrixOffsets[frame];
 const UINTN headerBytes=(5+MATRIX_FRAMES+1)*sizeof(UINT32);
 if(!MatrixDecode(MatrixAsset+headerBytes+offset,MatrixOffsets[frame+1]-offset,MatrixCurrent)){Visible=FALSE;return;}
 UINT64 decodeUs=Micros(start,Stamp());
 start=Stamp();
 EFI_STATUS status=EFI_SUCCESS;
 MATRIX_FRAMEBUFFER surface;
 if(MatrixDirect){
  if(!MatrixFramebuffer(&surface,MatrixOutputWidth,MatrixOutputHeight)){Visible=FALSE;return;}
  if(MatrixOutputWidth==MATRIX_WIDTH)MatrixWriteFramebuffer(&surface,TRUE);
  else MatrixWriteScaled(&surface,MatrixOutputWidth,MatrixOutputHeight,TRUE);
 }
 else if(!MatrixHasFrame){
  status=MatrixCopy(0,0,MATRIX_WIDTH,MATRIX_HEIGHT);
  UINT64 gopTime=Micros(start,Stamp());
  if(status==EFI_SUCCESS&&gopTime&&MatrixFramebuffer(&surface,MATRIX_WIDTH,MATRIX_HEIGHT)){
   UINT64 directStart=Stamp();
   MatrixWriteFramebuffer(&surface,FALSE);
   UINT64 directTime=Micros(directStart,Stamp());
   MatrixDirect=directTime&&directTime<gopTime-gopTime/8;
   if(MatrixDirect&&MatrixFitsBudget(decodeUs,directTime))status=MatrixProbeScale(&surface,decodeUs);
  }
 }
 else {
  BOOLEAN changed[MATRIX_HEIGHT/24][MATRIX_WIDTH/64];
  UINTN tiles=0;
  for(UINTN y=0;y<MATRIX_HEIGHT/24;y++)for(UINTN x=0;x<MATRIX_WIDTH/64;x++){
   changed[y][x]=MatrixChanged(x*64,y*24);
   if(changed[y][x])tiles++;
  }
  if(tiles>=(MATRIX_HEIGHT/24)*(MATRIX_WIDTH/64)*3/4)status=MatrixCopy(0,0,MATRIX_WIDTH,MATRIX_HEIGHT);
  else for(UINTN y=0;y<MATRIX_HEIGHT/24&&status==EFI_SUCCESS;y++){
   for(UINTN x=0;x<MATRIX_WIDTH/64&&status==EFI_SUCCESS;){
    if(!changed[y][x]){x++;continue;}
    UINTN first=x++;
    while(x<MATRIX_WIDTH/64&&changed[y][x])x++;
    status=MatrixCopy(first*64,y*24,(x-first)*64,24);
   }
  }
 }
 if(status!=EFI_SUCCESS){Visible=FALSE;return;}
 UINT16 *previous=MatrixPrevious;MatrixPrevious=MatrixCurrent;MatrixCurrent=previous;
 MatrixFrame=frame;MatrixHasFrame=TRUE;PresentedFrames++;
}
static BOOLEAN Drawable(EFI_GRAPHICS_OUTPUT_PROTOCOL *g){
 return g&&g->Blt&&g->Mode&&g->Mode->Info&&g->Mode->SizeOfInfo>=sizeof(*g->Mode->Info)&&g->Mode->Info->HorizontalResolution>=MATRIX_WIDTH&&g->Mode->Info->VerticalResolution>=MATRIX_HEIGHT;
}
static EFI_STATUS FindGraphics(VOID){
 EFI_GUID guid=EFI_GRAPHICS_OUTPUT_PROTOCOL_GUID;
 EFI_STATUS s=St->BootServices->HandleProtocol(St->ConsoleOutHandle,&guid,(VOID**)&Gop);
 if(s==EFI_SUCCESS&&Drawable(Gop))return EFI_SUCCESS;
 // AMI exposes ConOut on its text splitter, while the real GOP is on a
 // separate display child. Accept exactly one physical drawable GOP. Never
 // reconnect drivers, change modes or guess between multiple display outputs.
 Gop=NULL;EFI_HANDLE *handles=NULL;UINTN n=0,count=0;EFI_GRAPHICS_OUTPUT_PROTOCOL *candidate=NULL;
 s=St->BootServices->LocateHandleBuffer(ByProtocol,&guid,NULL,&n,&handles);
 if(s==EFI_SUCCESS&&handles&&n<=128)for(UINTN i=0;i<n;i++){
  EFI_GRAPHICS_OUTPUT_PROTOCOL *g=NULL;
  if(St->BootServices->HandleProtocol(handles[i],&guid,(VOID**)&g)==EFI_SUCCESS&&Drawable(g)&&g->Mode->FrameBufferBase&&g->Mode->FrameBufferSize){count++;candidate=g;}
 }
 EFI_STATUS freed=EFI_SUCCESS;if(handles)freed=St->BootServices->FreePool(handles);
 if(s!=EFI_SUCCESS)return s==EFI_NOT_FOUND?EFI_UNSUPPORTED:s;
 if(freed!=EFI_SUCCESS)return freed;
 if(count!=1)return EFI_UNSUPPORTED;
 Gop=candidate;return EFI_SUCCESS;
}

EFI_STATUS GuBootSplashEnd(VOID) {
 EFI_STATUS status=St?MatrixClose():EFI_SUCCESS;
 St=NULL;Gop=NULL;Mode=NULL;Clock=NULL;MatrixVolume=NULL;Visible=FALSE;
 return status;
}

EFI_STATUS GuBootSplashBegin(EFI_SYSTEM_TABLE *table, EFI_FILE_PROTOCOL *volume) {
 if(St||!table||!table->BootServices||!table->ConIn||
    !table->ConIn->ReadKeyStroke||!table->ConIn->WaitForKey)return EFI_UNSUPPORTED;
 St=table;
 MatrixVolume=volume;
 PresentedFrames=0;
 FindClock();
 EFI_STATUS status=Clock?FindGraphics():EFI_UNSUPPORTED;
 if(status==EFI_SUCCESS){
  Mode=Gop->Mode;
  Width=Mode->Info->HorizontalResolution;
  Height=Mode->Info->VerticalResolution;
  ModeNumber=Mode->Mode;
  if(Width>8192||Height>4320||Mode->Info->PixelFormat>PixelBltOnly)status=EFI_UNSUPPORTED;
 }
 if(status==EFI_SUCCESS)status=MatrixLoad();
 if(status==EFI_SUCCESS){
  Visible=TRUE;
  if(Width!=MATRIX_WIDTH||Height!=MATRIX_HEIGHT){
   PIXEL black={0,0,0,0};
   status=Gop->Blt(Gop,&black,EfiBltVideoFill,0,0,0,0,Width,Height,0);
  }
  if(status==EFI_SUCCESS)MatrixDraw(0);
  else Visible=FALSE;
  if(Visible)return EFI_SUCCESS;
  status=EFI_DEVICE_ERROR;
 }
 EFI_STATUS closed=GuBootSplashEnd();
 return closed==EFI_SUCCESS?status:closed;
}

EFI_STATUS GuBootSplashPlay(BOOLEAN countdown, BOOLEAN *skip) {
 if(!St||!skip)return EFI_INVALID_PARAMETER;
 *skip=FALSE;
 EFI_BOOT_SERVICES *bs=St->BootServices;
 EFI_EVENT deadline=NULL,tick=NULL;
 EFI_STATUS status=bs->CreateEvent(EVT_TIMER,TPL_CALLBACK,NULL,NULL,&deadline);
 if(status==EFI_SUCCESS)status=bs->CreateEvent(EVT_TIMER,TPL_CALLBACK,NULL,NULL,&tick);
 UINT64 start=Stamp();
 if(status==EFI_SUCCESS)status=bs->SetTimer(deadline,TimerRelative,countdown?30000000:7333333);
 if(status==EFI_SUCCESS)status=bs->SetTimer(tick,TimerPeriodic,333333);
 while(status==EFI_SUCCESS){
  if(countdown){
   EFI_INPUT_KEY key;
   EFI_STATUS input=St->ConIn->ReadKeyStroke(St->ConIn,&key);
   if(input==EFI_SUCCESS&&(key.ScanCode==0x17||key.UnicodeChar==27)){*skip=TRUE;break;}
   if(input!=EFI_SUCCESS&&input!=EFI_NOT_READY){status=input;break;}
  }
  EFI_EVENT events[]={deadline,tick,St->ConIn->WaitForKey};
  UINTN index=0;
  status=bs->WaitForEvent(countdown?3:2,events,&index);
  if(status!=EFI_SUCCESS||index==0)break;
  if(index==1&&Visible){
   UINTN frame=(UINTN)(Micros(start,Stamp())*30/1000000);
   MatrixDraw(countdown?(frame<90?frame:89):(frame<22?90+frame:111));
  }
 }
 if(status==EFI_SUCCESS&&!countdown&&Visible)MatrixDraw(111);
 if(tick){EFI_STATUS closed=bs->CloseEvent(tick);if(status==EFI_SUCCESS)status=closed;}
 if(deadline){EFI_STATUS closed=bs->CloseEvent(deadline);if(status==EFI_SUCCESS)status=closed;}
 return status;
}

BOOLEAN GuBootSplashVisible(VOID){return Visible;}
BOOLEAN GuBootSplashDirect(VOID){return MatrixDirect;}
UINTN GuBootSplashWidth(VOID){return MatrixOutputWidth;}
UINTN GuBootSplashFrames(VOID){return PresentedFrames;}
