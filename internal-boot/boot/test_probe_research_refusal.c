/* RAM-only: pins outside the separately reviewed resource tuple cannot read. */
#define GU_PROBE_PARENT_FIXTURE
#include "test_probe_generic.c"
#undef main
int main(void) {
  GenericSetup(G_OK);TestId=GU_PROBE_EXPECTED_ID;TestSubsystem=GU_PROBE_EXPECTED_SUBSYSTEM;
  Check(GuCaptureGraphOnVolume(&Table,&LogFile,&RootFile)==EFI_NOT_READY,"unreviewed research pin tuple refused");
  Check(!S.RegReads && !S.PromReads && !AttributeOthers,"no MMIO/PROM/attribute write for unreviewed tuple");
  printf("PASS research tuple refusal: %d; RAM mocks only\n",Checks);
  return 0;
}
