/* GPL-2.0-only. Aggregate frontend plus actual host-only release research.
 * All interfaces/images are synthetic RAM; each Run models a fresh EFI image. */
#define main legacy_aggregate_main
#include "test_aggregate_full.c"
#undef main

static EFI_PCI_IO_PROTOCOL BridgeIo;
static UINT32 BridgeConfig[64];
static UINT8 BridgePath[22];
static UINTN BridgeTag[8];
#define BRIDGE_HANDLE ((EFI_HANDLE)&BridgeTag[3])
static BOOLEAN Reenter;
static unsigned BridgeReads,FaultRead,OpenMode,CloseMode,ForeignBefore,RecursiveChecks;
static unsigned TplDepth,TplRaises,TplRestores;
static const char *EdidInput,*NvInput,*PromInput,*ConfigInput;
static unsigned EffectFault,EffectAt,EdidFault,EdidSelected,OwnerFault,OwnerQueries;
static BOOLEAN Injected,StatusLayout;
static BOOLEAN LateGraphFault,EnableIntentSeen,LateGraphInjected;
static unsigned StopRemaining;
static BOOLEAN LateSubsetFault,LateSubsetInjected;
#ifdef GU_RELEASE_IOMEM_MODEL
#define MODEL_COMMAND 3U
#define MODEL_TARGET (GU_DS_IO|GU_DS_MEMORY)
#else
#define MODEL_COMMAND 2U
#define MODEL_TARGET GU_DS_MEMORY
#endif
static EFI_STATUS AuditLog(VOID *context,const char *event,EFI_STATUS status) {
  if(!strcmp(event,"pci-decode-restore-intent-io-mem-only"))EnableIntentSeen=TRUE;
  return Log(context,event,status);
}
static UINTN SelfRefs(VOID) {
  UINTN n=0;for(UINTN i=0;i<Live.Count;i++)if(Live.Edges[i].Handle==H(PCI) && Live.Edges[i].Agent==H(APP) && GuGuidEqual(&Live.Edges[i].Protocol,&PciGuid))n+=Live.Edges[i].Count;
  return n;
}
static UINTN OtherRefs(VOID) {
  UINTN n=0;for(UINTN i=0;i<Live.Count;i++)if(Live.Edges[i].Handle==H(PCI) && Live.Edges[i].Agent==H(OBSERVER) && GuGuidEqual(&Live.Edges[i].Protocol,&PciGuid))n+=Live.Edges[i].Count;
  return n;
}
static EFI_STATUS EFIAPI AuditHandle(EFI_HANDLE h,EFI_GUID *g,VOID **out) {
  if(h==BRIDGE_HANDLE) {
    *out=NULL;if(GuGuidEqual(g,&PciGuid))*out=&BridgeIo;if(GuGuidEqual(g,&PathGuid))*out=BridgePath;
    return *out?EFI_SUCCESS:EFI_UNSUPPORTED;
  }
  return Handle(h,g,out);
}
static EFI_STATUS EFIAPI AuditLocate(EFI_LOCATE_SEARCH_TYPE type,EFI_GUID *g,VOID *key,UINTN *count,EFI_HANDLE **out) {
  EFI_STATUS s=Locate(type,g,key,count,out);
  if(s==EFI_SUCCESS && type==AllHandles) {
    EFI_HANDLE *p=realloc(*out,(*count+1)*sizeof(**out));Check(p!=NULL,"extended parent handle inventory");
    *out=p;(*out)[(*count)++]=BRIDGE_HANDLE;
  }
  return s;
}
static EFI_STATUS EFIAPI AuditProtocols(EFI_HANDLE h,EFI_GUID ***out,UINTN *count) {
  if(h!=BRIDGE_HANDLE)return Protocols(h,out,count);
  *out=malloc(2*sizeof(**out));Check(*out!=NULL,"parent protocol inventory");
  (*out)[0]=&PciGuid;(*out)[1]=&PathGuid;*count=2;return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI AuditFind(EFI_GUID *g,EFI_DEVICE_PATH_PROTOCOL **path,EFI_HANDLE *h) {
  if((VOID *)*path==DisplayPaths[0] || (VOID *)*path==DisplayPaths[1] || (VOID *)*path==FaultDisplayPath)
    return FindPci(g,path,h); /* Preserve all legacy shortened/longer/parent drift faults. */
  Check(GuGuidEqual(g,&PciGuid),"PCI collector lookup");const UINT8 *p=(const VOID *)*path;
  if(!memcmp(p,BridgePath,sizeof(BridgePath))){*h=BRIDGE_HANDLE;*path=(VOID *)(p+18);return EFI_SUCCESS;}
  if(!memcmp(p,ControllerPath,sizeof(ControllerPath))){*h=H(PCI);*path=(VOID *)(p+TEST_CONTROLLER_BYTES);return EFI_SUCCESS;}
  return EFI_UNSUPPORTED;
}
static EFI_STATUS EFIAPI AuditLocation(EFI_PCI_IO_PROTOCOL *io,UINTN *s,UINTN *b,UINTN *d,UINTN *f) {
  if(io!=&BridgeIo)return Location(io,s,b,d,f);
  *s=GU_TARGET_SEGMENT;*b=0;*d=BridgePath[17];*f=BridgePath[16];return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI AuditRead(EFI_PCI_IO_PROTOCOL *io,EFI_PCI_IO_PROTOCOL_WIDTH w,UINT32 at,UINTN count,VOID *out) {
  if(LateSubsetFault && ReleaseAudit.AfterReady && Full.Owned && !LateSubsetInjected) {
    Config[1]|=1U;Attributes|=GU_DS_IO;LateSubsetInjected=TRUE;
  }
  if(LateGraphFault && Full.Owned && EnableIntentSeen && !LateGraphInjected) {
    Edge(PROTECTED,COMBO,PROTECTED,&PrivateGuid,EFI_OPEN_PROTOCOL_BY_DRIVER);LateGraphInjected=TRUE;
  }
  if(Reenter) {
    unsigned before=BridgeReads;UINTN next=ReleaseAudit.Next;
    Check(GuPrepareConsole(&Table,Log,NULL)==EFI_ALREADY_STARTED,"recursive aggregate prepare refused");
    Check(GuReleaseGop(&Table,H(APP),Log,NULL)==EFI_ALREADY_STARTED,"recursive aggregate release refused");
    if(ReleaseAudit.Verifying)Check(GuVerifyReleased(&Table,FALSE)==EFI_ALREADY_STARTED,"recursive aggregate verifier refused");
    Check(before==BridgeReads && next==ReleaseAudit.Next,"reentry cannot consume observations");RecursiveChecks++;
  }
  if(io!=&BridgeIo)return Read(io,w,at,count,out);
  Check(w==EfiPciIoWidthUint32 && !at && count==64,"bounded parent PCI read");BridgeReads++;
  if(BridgeReads<=2)Check(!Calls,"aggregate parent baseline before first driver release");
  if(BridgeReads==EffectAt) {
    Injected=TRUE;
    if(EffectFault==1)Boot.OpenProtocol=NULL;if(EffectFault==2)Boot.CloseProtocol=NULL;
    if(EffectFault==3)Boot.DisconnectController=NULL;if(EffectFault==4)Boot.RaiseTPL=NULL;
    if(EffectFault==5)Boot.RestoreTPL=NULL;
  }
  memcpy(out,BridgeConfig,sizeof(BridgeConfig));if(BridgeReads==FaultRead)((UINT32 *)out)[63]^=1;
  return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI AuditAttr(EFI_PCI_IO_PROTOCOL *io,EFI_PCI_IO_PROTOCOL_ATTRIBUTE_OPERATION op,UINT64 mask,UINT64 *out) {
  if(io!=&BridgeIo) {
    UINT64 removed=MODEL_TARGET&~((StopRemaining&1?GU_DS_IO:0)|(StopRemaining&2?GU_DS_MEMORY:0));
    if(op==EfiPciIoAttributeOperationEnable)Check(mask==removed && ReleaseAudit.HeldQuery && SelfRefs()==1,"only missing original decode under precise held claim");
    return Attr(io,op,mask,out);
  }
  Check(!mask && out && (op==EfiPciIoAttributeOperationGet || op==EfiPciIoAttributeOperationSupported),"parent never written");
  *out=op==EfiPciIoAttributeOperationGet?GU_DS_MEMORY:GU_DS_IO|GU_DS_MEMORY|GU_DS_MASTER;return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI AuditOpen(EFI_HANDLE h,EFI_GUID *g,VOID **out,EFI_HANDLE owner,EFI_HANDLE controller,UINT32 attr) {
  Check(ReleaseAudit.HeldQuery!=NULL,"no-self query retained until aggregate Open");
  if(OpenMode==1 || OpenMode==2){Claims++;*out=NULL;return OpenMode==1?EFI_DEVICE_ERROR:EFI_WARN_UNKNOWN_GLYPH;}
  EFI_STATUS s=Open(h,g,out,owner,controller,attr);
  if(OpenMode==3)return EFI_DEVICE_ERROR;if(OpenMode==4)return EFI_WARN_UNKNOWN_GLYPH;
  if(OpenMode==5)*out=&BridgeIo;
  if(OpenMode==6)Live.Edges[Live.Count-1].Count=2;
  if(OpenMode==7)Edge(PCI,OBSERVER,PCI,&PciGuid,EFI_OPEN_PROTOCOL_BY_DRIVER);
  return s;
}
static EFI_STATUS EFIAPI AuditClose(EFI_HANDLE h,EFI_GUID *g,EFI_HANDLE owner,EFI_HANDLE controller) {
  Check(h==H(PCI) && owner==H(APP) && !controller && ReleaseAudit.HeldQuery && SelfRefs()==1,"exact attributable aggregate Close");
  Closes++;
  if(CloseMode!=1 && CloseMode!=3 && CloseMode!=5) {
    UINTN n=0;for(UINTN i=0;i<Live.Count;i++) {
      EDGE e=Live.Edges[i];
      if(!(e.Handle==h && e.Agent==owner && e.Controller==controller && GuGuidEqual(&e.Protocol,g)))Live.Edges[n++]=e;
    }Live.Count=n;
  }
  if(CloseMode==1 || CloseMode==2)return EFI_DEVICE_ERROR;
  if(CloseMode==3 || CloseMode==4)return EFI_WARN_UNKNOWN_GLYPH;
  return EFI_SUCCESS;
}
static EFI_STATUS EFIAPI AuditOwners(EFI_HANDLE h,EFI_GUID *g,EFI_OPEN_PROTOCOL_INFORMATION_ENTRY **out,UINTN *count) {
  OwnerQueries++;EFI_STATUS s=Opens(h,g,out,count);
  if(h==H(PCI) && GuGuidEqual(g,&PciGuid)) {
    if(OwnerFault==1 && ReleaseAudit.OwnershipStarted && !ReleaseAudit.OpenInvoked)return EFI_DEVICE_ERROR;
    if(OwnerFault>=2 && ReleaseAudit.OpenInvoked && !ReleaseAudit.CloseInvoked) {
      Free(*out);*out=OwnerFault==2?BRIDGE_HANDLE:(VOID *)((UINT8 *)PreparedGraph+sizeof(UINTN));*count=1;
    }
  }
  return s;
}
static EFI_STATUS EFIAPI AuditFree(VOID *p) {
  UINTN address=(UINTN)p,base=(UINTN)BridgeTag;
  Check(address<base || address-base>=sizeof(BridgeTag),"never free borrowed aggregate parent handle");
  base=(UINTN)PreparedGraph;Check(!PreparedGraph || address<base || address-base>=sizeof(*PreparedGraph),"never free borrowed aggregate graph");
  return Free(p);
}
static EFI_STATUS EFIAPI AuditDisconnect(EFI_HANDLE h,EFI_HANDLE agent,EFI_HANDLE child) {
  BOOLEAN inject=EdidFault && agent==H(EDID) && EdidCalls+1==EdidSelected;
  EFI_STATUS s=Disconnect(h,agent,child);
  if(agent==H(NV) && s==EFI_SUCCESS && StopRemaining) {
    Config[1]|=StopRemaining;Attributes|=(StopRemaining&1?GU_DS_IO:0)|(StopRemaining&2?GU_DS_MEMORY:0);
  }
  if(inject) {
    if(EdidFault==1)return EFI_DEVICE_ERROR;if(EdidFault==2)return EFI_WARN_UNKNOWN_GLYPH;
    if(EdidFault==3)BridgeConfig[63]^=1;
    if(EdidFault==4)DisplayPaths[1][TEST_CONTROLLER_BYTES+4]^=1;
    if(EdidFault==5)Bindings[1].Version++;
    if(EdidFault==6)EdidMemory[0x1000]^=1;
  }
  return s;
}
static EFI_TPL EFIAPI AuditRaise(EFI_TPL level) {Check(level==TPL_NOTIFY,"known TPL");TplRaises++;return TplDepth++?TPL_NOTIFY:TPL_APPLICATION;}
static VOID EFIAPI AuditRestore(EFI_TPL old) {Check(TplDepth>0,"balanced TPL");TplDepth--;TplRestores++;Check(old==(TplDepth?TPL_NOTIFY:TPL_APPLICATION),"restored old TPL");}
static void InstallParent(void) {
  Check(TEST_CONTROLLER_BYTES==24,"explicit one-parent synthetic route");
  memcpy(BridgePath,ControllerPath,18);memcpy(BridgePath+18,(UINT8[]){127,255,4,0},4);
  memset(BridgeConfig,0,sizeof(BridgeConfig));BridgeConfig[0]=0x14831022;BridgeConfig[1]=2;
  BridgeConfig[2]=0x06040000;BridgeConfig[3]=0x10000;BridgeConfig[6]=(GU_TARGET_BUS<<8)|(GU_TARGET_BUS<<16);
  if(StatusLayout)BridgeConfig[32]=0x90000;
  BridgeIo=(EFI_PCI_IO_PROTOCOL){0};BridgeIo.GetLocation=AuditLocation;BridgeIo.Pci.Read=AuditRead;BridgeIo.Attributes=AuditAttr;
  Io.GetLocation=AuditLocation;Io.Pci.Read=AuditRead;Io.Attributes=AuditAttr;
  Boot.HandleProtocol=AuditHandle;Boot.LocateDevicePath=AuditFind;Boot.LocateHandleBuffer=AuditLocate;Boot.ProtocolsPerHandle=AuditProtocols;
  Boot.OpenProtocol=AuditOpen;Boot.CloseProtocol=AuditClose;Boot.RaiseTPL=AuditRaise;Boot.RestoreTPL=AuditRestore;
  Boot.OpenProtocolInformation=AuditOwners;Boot.FreePool=AuditFree;Boot.DisconnectController=AuditDisconnect;
}
static EFI_STATUS Run(unsigned mode,BOOLEAN mismatch,unsigned fault,BOOLEAN reenter) {
  /* Each call represents a new image, not an API for retrying a live release. */
  ReleaseAudit=(GU_RELEASE_AUDIT_STATE){0};Mode=mode;FaultRead=fault;Reenter=reenter;
  BridgeReads=TplDepth=TplRaises=TplRestores=OwnerQueries=0;Injected=FALSE;EnableIntentSeen=LateGraphInjected=LateSubsetInjected=FALSE;
  Setup();InstallParent();LoadExact(EdidInput,EdidMemory,sizeof(EdidMemory));LoadExact(NvInput,NvMemory,sizeof(NvMemory));LoadExact(PromInput,PromMemory,sizeof(PromMemory));
  LoadExact(ConfigInput,Config,sizeof(Config));Check(!memcmp(Config,FixtureFullRtxConfig,sizeof(Config)),"input config matches generated complete aggregate capture");
  Check((Config[1]&0xffff)==MODEL_COMMAND,"aggregate typed baseline uses the explicit original command");
  if(StatusLayout){Config[30]=0x0012b410;Config[32]=0x00092930;} /* Explicit synthetic post-child policy vector. */
  Attributes=mismatch?GU_DS_IO|GU_DS_MEMORY:MODEL_TARGET;
  if(ForeignBefore)Edge(PCI,OBSERVER,0,&PciGuid,EFI_OPEN_PROTOCOL_GET_PROTOCOL);
  EFI_STATUS s=GuPrepareConsole(&Table,AuditLog,NULL);
  Check(!Calls,"aggregate prepare performs zero Disconnect calls");
  if(!fault && !EffectFault
#ifndef GU_RELEASE_MISMATCH_RESEARCH
     && !mismatch
#endif
  )Check(s==EFI_SUCCESS,"aggregate prepare succeeds before release-stage scenarios");
  if(s==EFI_SUCCESS && Mode>=15) {
    ScenarioReached=TRUE;
    if(Mode==15)NvMemory[0x280]^=1;if(Mode==16)EdidMemory[0x1000]^=1;
    if(Mode==17)DisplayPaths[0][TEST_CONTROLLER_BYTES+4]^=1;
    if(Mode==18)Bindings[2].Stop=(EFI_DRIVER_BINDING_STOP)(ComboMemory+GU_COMBO_STOP+1);
    if(Mode==19)ParentDrift=TRUE;if(Mode==20 || Mode==21)ChangePathLength(Mode==21);
    if(Mode==22)DisplayPaths[0][16]^=1;if(Mode==23)SegmentDrift=TRUE;
  }
  if(s==EFI_SUCCESS)s=GuReleaseGop(&Table,H(APP),AuditLog,NULL);
  Check(!TplDepth && TplRaises==TplRestores,"aggregate return balances TPL on every path");return s;
}
int main(int argc,char **argv) {
  Check(argc==5,"synthetic EDID/NVIDIA/PROM/config images required");EdidInput=argv[1];NvInput=argv[2];PromInput=argv[3];ConfigInput=argv[4];
#ifdef GU_RELEASE_MISMATCH_RESEARCH
  const unsigned routes=2;
#else
  const unsigned routes=1;
#endif
  unsigned readBudget=0;
  for(unsigned route=0;route<routes;route++) {
    for(unsigned mode=0;mode<24;mode++) {
      EFI_STATUS s=Run(mode,(BOOLEAN)route,0,FALSE);
      if(!mode || mode==6) {
        Check(s==EFI_SUCCESS && Calls==TEST_CHILDREN+1 && EdidCalls==TEST_CHILDREN && NvCalls==1,"actual aggregate release preserves both normal and surviving virtual GOP routes");
        Check(Enables==1 && Claims==1 && Closes==1 && !SelfRefs() && !ReleaseAudit.ClaimMayRemain && Attributes==MODEL_TARGET && (Config[1]&7)==MODEL_COMMAND,"original decode restore and observed cleanup");
        Check(Full.Attributes==(route?GU_DS_IO|GU_DS_MEMORY:MODEL_TARGET) && Full.TargetAttributes==MODEL_TARGET,"observed origin retained separately from target");
#ifdef GU_RELEASE_IOMEM_MODEL
        Check(ReleaseAudit.IoMem && !ReleaseAudit.Mismatch && !ReleaseAudit.PlanReady && ReleaseAudit.AfterReady,
          "consistent command3 never enters mismatch correction");
#endif
        VOID *survivor=NULL;EFI_STATUS present=AuditHandle(H(AGG),&GopGuid,&survivor);
        if(mode==6)Check(present==EFI_SUCCESS && survivor==&Aggregate && !AggregateMode.FrameBufferBase && !AggregateMode.FrameBufferSize,
          "reviewed virtual aggregate GOP actually survives without a framebuffer");
        else Check(present==EFI_UNSUPPORTED && !survivor,"ordinary route actually removes the aggregate GOP");
        Check(GuVerifyReleased(&Table,TRUE)==EFI_SUCCESS && GuVerifyReleased(&Table,FALSE)==EFI_SUCCESS,"aggregate cold/post-child typed verification");
        if(!mode)readBudget=BridgeReads;
      } else {
        Check(ScenarioReached && s!=EFI_SUCCESS && !Enables && !Claims && !Closes,"original aggregate negative gate reached before claim/write");
        unsigned expected=(mode==5 || mode>=15)?0:((mode==1 || mode==2 || mode==14)?1:TEST_CHILDREN);
        Check(EdidCalls==expected && NvCalls==((mode==1 || mode==2 || mode==5 || mode==14 || mode>=15)?0U:1U),"original aggregate failure occurs at intended Stop boundary");
        if(mode==15 || mode==16)Check(s==EFI_CRC_ERROR && FirstError && !strcmp(FirstError,mode==15?"nvidia-code-profile":"ami-runtime-code-profile"),"exact original CRC gate");
      }
    }
    /* Budget above includes two external verifies; inject all release reads. */
    Check(Run(0,(BOOLEAN)route,0,FALSE)==EFI_SUCCESS,"release-only parent budget");unsigned releaseReads=BridgeReads;
    for(unsigned fault=1;fault<=releaseReads;fault++) {
      Check(Run(0,(BOOLEAN)route,fault,FALSE)!=EFI_SUCCESS,"parent drift at every actual aggregate release observation refuses");
      Check(BridgeReads==fault || BridgeReads==fault+1,"parent fault actually reached");
      Check(!ReleaseAudit.ClaimMayRemain && !SelfRefs(),"known claim cleaned after parent refusal");
    }
    for(unsigned kind=1;kind<=5;kind++)for(unsigned at=1;at<=releaseReads;at++) {
      EffectFault=kind;EffectAt=at;
      Check(Run(0,(BOOLEAN)route,0,FALSE)!=EFI_SUCCESS && Injected,"effect dispatch mutation in aggregate audit refuses");
      Check(!SelfRefs(),"frozen aggregate cleanup removes known claim after dispatch drift");
    }
    EffectFault=EffectAt=0;
    LateGraphFault=TRUE;
    Check(Run(0,(BOOLEAN)route,0,FALSE)!=EFI_SUCCESS && LateGraphInjected && Claims==1 && !Enables && Closes==1 && !SelfRefs(),
      "protected graph mutation during pre-Enable audit blocks write while preserving precise cleanup");
    LateGraphFault=FALSE;
    for(unsigned child=1;child<=TEST_CHILDREN;child++)for(unsigned fault=1;fault<=3;fault++) {
      EdidFault=fault;EdidSelected=child;EFI_STATUS s=Run(0,(BOOLEAN)route,0,FALSE);
      Check(s!=EFI_SUCCESS && EdidCalls==child && !NvCalls && !Claims && !Enables,"each aggregate EDID partial effect/parent drift prevents subsequent Stop or write");
      if(fault==1)Check(s==EFI_DEVICE_ERROR,"aggregate raw EDID partial error");
      if(fault==2)Check(s==EFI_WARN_UNKNOWN_GLYPH,"aggregate raw EDID partial warning");
    }
    if(TEST_CHILDREN==2)for(unsigned fault=4;fault<=6;fault++) {
      EdidFault=fault;EdidSelected=1;
      Check(Run(0,(BOOLEAN)route,0,FALSE)!=EFI_SUCCESS && EdidCalls==1 && !NvCalls && !Claims && !Enables,"remaining aggregate child path/binding/code drift refuses");
    }
    EdidFault=EdidSelected=0;
    for(unsigned mode=1;mode<=7;mode++) {
      OpenMode=mode;EFI_STATUS s=Run(0,(BOOLEAN)route,0,FALSE);
      Check(s!=EFI_SUCCESS && !Enables && Claims==1,"partial/wrong/ambiguous aggregate Open never permits restore");
      if(mode==1 || mode==3)Check(s==EFI_DEVICE_ERROR && ReleaseAudit.OpenStatus==s,"aggregate raw Open error preserved");
      if(mode==2 || mode==4)Check(s==EFI_WARN_UNKNOWN_GLYPH && ReleaseAudit.OpenStatus==s,"aggregate raw Open warning preserved");
      Check(Closes==(mode==3 || mode==4 || mode==5 || mode==7?1U:0U),"aggregate cleanup attributed exactly");
      if(mode==6)Check(SelfRefs()==2 && ReleaseAudit.ClaimMayRemain,"ambiguous aggregate self references untouched");
      else Check(!SelfRefs(),"known aggregate self removed or absent");
      if(mode==7)Check(OtherRefs()==1,"foreign aggregate owner preserved");
    }
    OpenMode=0;
    for(unsigned mode=1;mode<=5;mode++) {
      CloseMode=mode;EFI_STATUS s=Run(0,(BOOLEAN)route,0,FALSE);
      Check(s!=EFI_SUCCESS && Enables==1 && Closes==1 && !Full.Restored,"partial/retained aggregate Close blocks completion");
      if(mode==1 || mode==2)Check(s==EFI_DEVICE_ERROR && ReleaseAudit.CloseStatus==s,"aggregate raw Close error preserved");
      if(mode==3 || mode==4)Check(s==EFI_WARN_UNKNOWN_GLYPH && ReleaseAudit.CloseStatus==s,"aggregate raw Close warning preserved");
      Check(SelfRefs()==(mode==1 || mode==3 || mode==5?1U:0U),"aggregate residual claim observed");
    }
    CloseMode=0;
    ForeignBefore=1;Check(Run(0,(BOOLEAN)route,0,FALSE)==EFI_SUCCESS && OtherRefs()==1,"precise aggregate cleanup preserves baseline foreign passive");ForeignBefore=0;
    OwnerFault=1;Check(Run(0,(BOOLEAN)route,0,FALSE)==EFI_DEVICE_ERROR && !Claims && !Enables,"aggregate failed owner baseline grants nothing");
    OwnerFault=0;unsigned queried=OwnerQueries;EFI_PCI_IO_PROTOCOL *retry=NULL;
    Check(AuditOwnershipAcquire(&retry)==EFI_ACCESS_DENIED && OwnerQueries==queried && !Claims,"failed aggregate baseline cannot be reused");
    for(unsigned fault=2;fault<=3;fault++) {
      OwnerFault=fault;Check(Run(0,(BOOLEAN)route,0,FALSE)!=EFI_SUCCESS && Claims==1 && !Closes && !Enables && SelfRefs()==1 && ReleaseAudit.ClaimMayRemain,"borrowed aggregate owner buffer never grants cleanup/write");
    }
    OwnerFault=0;
    Check(Run(0,(BOOLEAN)route,0,TRUE)==EFI_SUCCESS && RecursiveChecks,"aggregate preparation/release/verify recursion refused");
    Check(Run(0,(BOOLEAN)route,0,FALSE)==EFI_SUCCESS,"fresh aggregate image for final parent fault");
    BridgeConfig[63]^=1;Check(GuVerifyReleased(&Table,FALSE)!=EFI_SUCCESS,"post-child parent drift blocks aggregate handoff");
    StatusLayout=TRUE;
    Check(Run(0,(BOOLEAN)route,0,FALSE)==EFI_SUCCESS,"aggregate synthetic status-layout vector");
    Config[32]&=~0x90000;Check(GuVerifyReleased(&Table,FALSE)==EFI_SUCCESS && Full.Config[32]==0x00092930,"aggregate reviewed GPU status clear keeps original observation");
    Check(Run(0,(BOOLEAN)route,0,FALSE)==EFI_SUCCESS,"aggregate new image for strict parent status");
    BridgeConfig[32]&=~0x90000;Check(GuVerifyReleased(&Table,FALSE)!=EFI_SUCCESS,"GPU status-clear policy never applies to aggregate parent");
    StatusLayout=FALSE;
  }
#if !defined(GU_RELEASE_MISMATCH_RESEARCH) && !defined(GU_RELEASE_IOMEM_MODEL)
  Check(Run(0,TRUE,0,FALSE)==EFI_NOT_READY && !Calls && !Claims && !Enables,
    "aggregate audit-only refuses cache300 before any driver release");
#endif
#ifdef GU_RELEASE_IOMEM_MODEL
  for(unsigned remaining=1;remaining<=3;remaining++) {
    StopRemaining=remaining;
    Check(Run(0,FALSE,0,FALSE)==EFI_SUCCESS && Attributes==MODEL_TARGET && (Config[1]&7U)==3U,
      "actual source restores each coherent IO/MEM subset to original300");
    Check(Enables==(remaining==3?0U:1U) && Claims==1 && Closes==1 && !SelfRefs(),"zero missing mask makes no Enable call while cleanup remains precise");
    Check(GuVerifyReleased(&Table,FALSE)==EFI_SUCCESS,"partial decode restore passes actual post-child verification");
  }
  StopRemaining=0;LateSubsetFault=TRUE;
  Check(Run(0,FALSE,0,FALSE)!=EFI_SUCCESS && LateSubsetInjected && !Enables && !SelfRefs(),
    "a different coherent subset after the first post-Stop observation cannot authorize Enable");
  LateSubsetFault=FALSE;
#endif
  printf("PASS aggregate release audit: %u children, %u parent read budget, %u checks; actual production phases, RAM only\n",TEST_CHILDREN,readBudget,Checks);
  return 0;
}
