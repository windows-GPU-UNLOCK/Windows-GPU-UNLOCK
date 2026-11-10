# PCI decode-cache synchronization research

The correction core and owned adapter are host-testable research libraries,
**not an executable fix**. No production build, probe, LOCAL profile gate or USB
staging script invokes correction. The generic diagnostic uses only the shared
read-only collector/predicates for optional observations. Current captures with
inconsistent PCI attributes remain refused by LOCAL admission.

Reports [#102](https://github.com/impacifist/Windows-GPU-UNLOCK/issues/102),
[#121](https://github.com/impacifist/Windows-GPU-UNLOCK/issues/121) and
[#129](https://github.com/impacifist/Windows-GPU-UNLOCK/issues/129) describe a
GPU command register of `0x0002` but PciIo attributes of `0x300` (IO + memory).
Contributors report that disabling the IO attribute reconciled these values
before running their separate unlock workflow. Their results concern specific
firmware/builds; they do not establish a generic firmware correction.

The independent cache-correction core offers exactly one write capability:
`DisableIo`. It does not adopt the contributor pre-step's initial IO-enable attempt.
Its callback must eventually be bound to the reviewed GPU's
`PciIo->Attributes(Disable, IO)`. The research library adapter described below is
implemented and tested only against RAM-backed EFIAPI mocks; it is not connected
to any shipped boot image and has not been authorized or tested on physical hardware.
The separately gated MEMORY restoration experiment is described at the end of
this document; it does not broaden the correction core's capabilities.

`GuDecodeSync` requires an exact baseline GPU and 1–16 caller-verified immediate
parent bridges, including location, handle/interface tokens, all 64 config
dwords and full attribute/support values. It rejects aliasing, invalid BDF ranges,
inconsistent parent buses and unreviewed target identities. GPU command must be
exactly `2`; the only admitted discrepancy is raw attributes `0x300` instead of
`0x200`. An already consistent baseline is observed without a write.

Before the single Disable call, the core freezes its input/callback table, flushes
the intent log and checks a fresh complete snapshot. It compares the complete GPU
and every parent after the call and at four bounded logical follow-ups. Only the
GPU's IO attribute may clear; raw PCI config, memory/BME state, other attributes,
locations, interfaces and parents must remain identical. Only `EFI_SUCCESS` and
canonical boolean log success are accepted. A failed write still receives one
bounded observation because an error does not prove that state was unchanged.
There is no retry, rollback, IO/BME enable, config/MMIO write or chainload capability.

The caller must retain one zero-initialized transaction object and never reset
it to retry. Reentry using the same object refuses before a callback. The caller
must also serialize operations and prevent reuse through another object. The
snapshot callback's honesty, ownership and freshness are separate obligations;
tokens and a `Complete` flag are not authenticated evidence. Parent topology must
be verified from actual device paths by the future adapter, not inferred only
from matching bus numbers. Immediate host samples do not prove timed stability
or detect every change between observations. Hidden firmware state and real GPU
behavior are outside this mock model.

Run only the host model from an MSVC/Windows SDK developer environment:

```powershell
python -I research/pci-decode/test-decode-sync.py --mutations --clang C:\TOOLS\LLVM20\bin\clang.exe --output research/pci-decode/build/your-new-run
```

Use a new output directory. Tests exercise failures/warnings/partial output,
callback reentry and input mutation, log failure/drift, changes in every config
dword of the GPU and all 16 parents, full attribute/token/location drift, and
attempts to reuse a transaction. All protocol effects are RAM callbacks; no GPU,
firmware, boot setting or physical media is accessed. Passing this model grants
no hardware support, LOCAL write evidence or permission to run a correction.
The optional mutation checks compile thirty-four deliberately broken copies in the ignored
output directory and require the host tests to reject them. A compile failure does
not count as detecting a broken guard. Original source files remain unchanged.

## Research UEFI adapter

`efi-adapter.c` binds an exact caller-supplied baseline and PCI controller paths.
Initialization requires the caller's non-NULL `OwnerImage`, validates/copies inputs without firmware calls and cannot reset a
used context. Run freezes a private copy and spends the context before its first
callback, including against reentry through a fresh core transaction object.
Caller-owned policy changes cannot alter the active copy. Contexts must remain
private, zero-initialized and serialized; callers must not reset/recreate them to retry.

The adapter now observes an already-held exclusive claim on the GPU's PciIo
protocol. It never acquires or closes that claim. The caller must retain it for
the entire call, retain the input/context/transaction storage and all interface
lifetimes, and serialize other operations. The research-only initialization API
adds `OwnerImage` immediately after `Boot`; no shipped API or build uses it.

`OpenProtocolInformation` must return exactly one self-agent, NULL-controller,
`EXCLUSIVE`, `OpenCount=1` record. Additional observation records may have only
the exact passive attributes 1/2/4 and positive counts. Driver/child openers,
BY_DRIVER|EXCLUSIVE, foreign/duplicate exclusive records, missing output, warnings
and malformed counts refuse. Queries are bounded to 64 records; byte-range checks
reject known borrowed storage, misalignment and address overflow before access or
free. These checks cannot authenticate an arbitrary pointer as a pool allocation;
the firmware service's allocation contract remains a requirement. This follows the
[UEFI OpenProtocolInformation and pool-buffer contract](https://uefi.org/specs/UEFI/2.10/07_Services_Boot_Services.html).

Ownership is sampled around full snapshots, after successful logging, and once
more before Disable(IO). The final query's pool buffer stays allocated until after
that call, avoiding an intervening FreePool callback. Holding this buffer does
**not** lock or extend protocol ownership. OpenProtocolInformation and FreePool
method pointers join the frozen whole-chain capability checks. Returned allocations
are freed once, including valid outputs accompanying an error; cleanup failure is
not retried and permanently marks `OwnershipFault`.

The context separately retains `OwnershipStatus`, `CleanupStatus` and the actual
`DisableIoStatus`. `OwnershipObserved`, `CleanupObserved` and `DisableInvoked`
distinguish an uncalled operation from a real EFI_NOT_STARTED return. First failures
survive subsequent successful observations. The core's Attempted/adapter WriteSpent
flags can be set before the actual protocol call; neither proves that Disable ran.
A failed cleanup after a write therefore remains an attempted write with uncertain
cleanup, even if the write itself succeeded.

This is a guard for one protocol's observed opener list, not ownership acquisition,
all-controller isolation or an atomic snapshot. In particular, a final ownership
query or cleanup callback that violates its read-only/device-state contract can
change GPU/parent state after an earlier read. Finite rechecks cannot exclude every
such window. Caller serialization, continued claim/lifetime retention and trusted
firmware API behavior remain necessary; passing mocks does not prove physical safety.

Shipped integration is still unresolved: default full-release's CapturePermit rejects
the real mismatch before NVIDIA Stop, whereas its exclusive claim is acquired
after Stop in RestoreDecode. A self-exclusive adapter cannot simply replace the
contributor pre-step while NVIDIA still owns the protocol. This change does not
relax CapturePermit, stop a driver, force an exclusive OpenProtocol, restore decode,
stage an image or qualify any of the reported machines. The separate research
caller below adds a bounded claim lifecycle for an already unmanaged controller;
it does not change that production ordering.

## Research owned lifecycle caller

`efi-owned.h/c` composes current-boot capture, exclusive protocol acquisition,
the existing correction adapter, exact-tuple CloseProtocol and post-close checks.
There is no EFI entry point or production/build/staging connection. Callers supply
one zero-initialized `GU_DO_TRANSACTION`, their retained image handle, a qualified
exact target and a durable logger. Calls require TPL_APPLICATION, serialized
controller access and live interfaces/storage. A private per-image workspace and
busy guard reject callback reentry even through a fresh transaction. They are not
a multiprocessor lock; do not reset/recreate transactions to retry.

The initial collector must accept the full GPU/parent snapshot. Already-consistent
memory-only attributes receive another logged snapshot without acquiring a claim
or writing. The correction path requires command=2/cache=0x300. Command 0/1 after
a driver stop, BME-on states and other unqualified configurations refuse before
claim acquisition. This caller does not enable decode to make them eligible.

Before Open, two opener views allow only canonical passive records, with exact
agent/controller/attribute/count preservation. Any existing reference by the
same OwnerImage, managing/child/exclusive/unknown record or malformed output
refuses. At most 63 passives leave room for the existing adapter's 64-record bound
including one new self claim. A logged intent and repeated complete capture
precede the final view. Its query allocation stays held across the single Open;
no logging or FreePool callback intervenes. Boot/PCI methods are frozen.

Importantly, [UEFI OpenProtocol](https://uefi.org/specs/UEFI/2.10/07_Services_Boot_Services.html#efi-boot-services-openprotocol)
EXCLUSIVE can implicitly disconnect a BY_DRIVER consumer. This library never
directly calls Stop/Disconnect, but cannot promise their absence if the opener
state changes during Open. Observing no manager is not a lock. Trusted firmware
and read-only callbacks plus caller serialization/quiescence remain prerequisites.
[CloseProtocol](https://uefi.org/specs/UEFI/2.10/07_Services_Boot_Services.html#efi-boot-services-closeprotocol)
removes the tuple's references; rejecting pre-existing self references is what
allows this caller to attribute cleanup to its new acquisition.

Open must succeed with the exact pinned interface and an observed self-exclusive,
NULL-controller/count=1 record alongside the unchanged passives before adapter
execution. Cleanup calls frozen Close at most once after strict Open success or
an attributable observed self claim. An error/warning can leave a claim behind:
an observable attributable claim is cleaned without promoting the failure; an
unobservable error-side claim is left explicitly uncertain, without blind Close.
No retry or automatic recovery/chainload capability is offered.

Close is followed by an exact no-self/passive view, another full capture and a
final opener view. The earlier view's failure cannot be erased by the later one.
A reproduced host regression showed that a capture callback could recreate the
self claim after the first no-self view; the final view now catches that case.
All evidence still ends at finite callback boundaries. In particular, the final
query's FreePool callback must obey the trusted contract: subsequent hidden
mutation cannot be ruled out atomically by more finite samples.

The report separates invocation flags from real Open/Close statuses and
`ClaimMayRemain`. Lifecycle ownership/cleanup statuses are separate from the
adapter's ownership/cleanup/Disable statuses, each with observed/invoked flags;
an actual EFI_NOT_STARTED is never mistaken for an uncalled sentinel.
`AfterObserved` records a complete capture even when its comparison fails.
Neither a clean mock claim nor `GU_DO_FIXED` grants firmware eligibility.

The host runner includes the owned caller: 822,653 lifecycle assertions cover
1–15 parents, segment boundaries, every service error/warning, empty/63/64-record
opener boundaries, same-agent references, borrowed buffers, missing output,
Open partial effects, Close uncertainty, post-close claim recreation, reentry and
caller-input mutation. Thirty-four compiled guard mutants cover the combined
libraries. All effects are RAM mocks; none is a physical driver-release proof.

The full lifecycle now also compiles/links into an invalid-target synthetic EFI
for PE/import and function-stack checks. This is not a deployment package; it is
never executed or staged. The workspace and remaining integration limits follow.

## Bounded correction workspaces and link checks

Core ops/policy/current snapshots and adapter active context/read-pair/Disable
snapshots use bounded private per-image storage. The core refuses a fresh
transaction while any core call is active. Adapter Initialize/Run likewise refuse
fresh contexts before changing caller state or shared storage. Normal nested
Owned -> Adapter -> Core calls remain valid. Every completed or failed session
releases its workspace guard; spent caller objects remain spent. Callers still
serialize CPUs and retain storage/interfaces; these flags are not locks.

The adapter's pool checks protect the complete private active context, both read
snapshots, Disable snapshot and the current Core Read output. The pure internal
`GuDecodeWorkspaceOverlap` helper also protects the complete core ops/pin/now
region when query buffers arrive outside an active Read. Known borrowed/partly
overlapping storage is never freed as a firmware pool allocation. Arbitrary pool
pointer authenticity still depends on the firmware contract.

The host suite exercises fresh-context reentry in protocol and log callbacks,
normal sessions after every failure, and 21 whole/interior/boundary-overlapping
private-storage aliases. Address-probe helpers exist only under an explicitly
hosted test define; freestanding compilation rejects that define and the linked
image must contain no address-probe symbol.

```powershell
python -I research/pci-decode/test-owned-image.py --clang C:\TOOLS\LLVM20\bin\clang.exe --lld-link C:\TOOLS\LLVM20\bin\lld-link.exe --stack-mutations --output research/pci-decode/build/your-new-owned-link
```

This test retains the actual capture/claim/adapter/core code behind a volatile
entry dispatch with an invalid target. It verifies PE/imports, required lifecycle
symbols and compiler stack records, with a 2 KiB per-function frame limit. Tested
clang 20 flags report 248 bytes maximum across the linked implementation, compared
with historical 11,176-byte frames. Four negative variants separately restore
automatic core snapshots, adapter context, read pair or Disable snapshot. Each
must compile and then fail the freestanding link for `__chkstk`; compile failures
do not count. No stub, disabled probing or hardware execution is used.

A per-function limit does not measure the maximum dynamic call-chain stack, external
firmware stack or physical safety. Passing PE/link checks does not authorize this
synthetic image, acquire a real claim or solve the production pre-Stop/cache-order
gap. No production/probe/LOCAL/staging path links correction as a result.

The GPU controller route uses the existing bounded PNP0A03/PNP0A08 parser. Two to
sixteen PCI nodes correspond to one to fifteen immediate parent bridges. Each
parent's path must be the exact corresponding prefix plus an End node; its PCI
device/function must match the last node. This adapter's parent limit is smaller
than the standalone core's sixteen-parent bound.

Each snapshot uses `HandleProtocol`, `LocateDevicePath`, `GetLocation`, a full
64-dword PCI read, and Attributes Get/Supported. It requires the pinned interface,
exact path bytes and exact Locate consumption at the End node. Two full chain
scans use different config initialization patterns, so successful partial reads
cannot pass merely by leaving the same sentinel twice. Method pointers and both
BootServices methods are pinned and rechecked, including all devices after the
last callback. Before the sole Disable(IO), the adapter performs another full
scan and callback-free whole-chain capability check. It does not expose generic
Attributes, config-write, MMIO, install/uninstall, disk or boot capabilities.

The mock adapter suite injects warning/error with valid output, absent output,
partial config, path/Locate-consumption errors, changed interfaces/methods,
early and late parent drift, Init/Run reentry, caller input changes and a failing
write that nevertheless changes state. Mutation checks also break Locate bounds,
the differing sentinels, whole-chain method checks and one-shot initialization.
Ownership fixtures cover callback-time claim loss, passive/managing combinations,
known borrowed/misaligned/overflowing buffers, output-less success, error with valid
output and pre/post-write cleanup failures. A reproduced EFI_NOT_STARTED status-loss
regression verifies that later successful queries cannot erase the first error.

This is not ownership acquisition, GPU qualification, a snapshot of all firmware
state, atomic observation across devices or proof of real-time stability. A future
experiment must independently establish authorized ownership, lifetime/freshness,
boot/display consequences, logging durability and physical validation. Existing
read-only probes, LOCAL admission and build-evidence rules remain unchanged.

## Current-boot baseline collector

Pure snapshot data/predicates now live in `snapshot.{h,c}` and EFI binding data in
`efi-binding.h`. The collector depends only on that read-only layer. The actuator
core and ownership adapter remain separate source units; a diagnostic must not
link them just to obtain snapshot helpers. This split preserves the existing
predicate bodies and ID/command admission without widening either envelope.

`efi-capture.c` supplies read-only baseline acquisition for the research adapter.
The caller supplies an exact GPU handle, segment/bus, PCI/subsystem IDs, BAR0 and
bounded controller-path bytes. The collector follows each immediate parent prefix
using LocateDevicePath, verifies exact End consumption and current live path bytes,
and reads GetLocation, all 64 PCI config dwords and Attributes Get/Supported.
It never calls OpenProtocolInformation, Allocate/FreePool, Attributes Enable/Disable,
config writes, MMIO, driver release, logging or boot services that launch an image.

Two full scans use different config sentinels and out-of-range location/attribute
sentinels. The first scan fixes every handle/interface/method; the second cannot
silently adopt replacements. Both must satisfy the caller's GPU pins, the existing
decode-core shape restrictions and exact full-snapshot equality. Whole-chain method
checks also run after callbacks, catching a late parent changing an earlier device's
method. `efi-path.h` shares controller validation with the existing adapter.

Use one private zero-initialized `GU_DS_CAPTURE`. It is spent before any service
callback and refuses reentry/reuse. Input/context/Boot overlap refuses without
clearing those aliased arguments. Failures during a fresh, disjoint capture publish
zero bindings/snapshot, Count=0 and Ready=FALSE; only success commits a complete result.
Reuse/reentry rejection preserves the old result. Always require this call's
EFI_SUCCESS, rather than interpreting an earlier Ready flag as a new capture. Request values are
copied privately before callbacks; interface and backing storage lifetimes still
belong to the caller. Protocol-returned pointers must obey the firmware API contract.

The current bound remains 2–16 PCI nodes (1–15 PciIo parent bridges), PNP0A03/PNP0A08
roots with captured UID, 16-bit segment and nonzero GPU bus. The decode-core ID scope
remains 2204/2203/2484/2487/2504, command=2, reviewed class/BAR shape and consistent
parent buses/attributes. In particular, production LOCAL's newer 24c9 admission
does not automatically widen this research correction scope; it is tested as refused.

Ready means a consistent observation under these rules. It proves neither absence
of another GPU nor chip/VRAM/PROM/driver-code qualification, ownership, atomicity or
timed stability. It does not authenticate a previously unknown device or authorize
an unlock. The returned binding array and snapshot can feed GuDsEfiInitialize only
after its independent held-claim/lifetime/serialization requirements are met.
The composition test does this against RAM EFIAPI mocks; no firmware code executes.
The shipped pre-NVIDIA-Stop integration issue described above is unchanged.

The collector uses bounded private per-image scratch rather than large automatic
WORK/snapshot arrays. A guard rejects callback reentry even through a fresh context
before that scratch can be overwritten. It is not a multiprocessor lock; callers
must still serialize operations. Results are copied into the caller's context and
do not retain pointers to the scratch arrays.

Before connecting this code to a shipped diagnostic, validate its actual EFI link,
not only COFF compilation. Run this from an ordinary host shell:

```powershell
python -I research/pci-decode/test-readonly-image.py --clang C:\TOOLS\LLVM20\bin\clang.exe --lld-link C:\TOOLS\LLVM20\bin\lld-link.exe --stack-mutation --output research/pci-decode/build/your-new-readonly-link
```

This builds a synthetic, invalid-target entry point with only the collector,
snapshot predicates and RAM runtime. It checks the real PE/map, refuses actuator
symbols, records compiler stack usage and requires each frame to stay within
2 KiB. The optional negative restores the old automatic arrays: it must compile,
then fail the freestanding link specifically for `__chkstk`, with a frame above
4 KiB. Do not hide that failure with a stack-probe stub or by disabling probing.
The tested clang 20 build reports 248 bytes maximum versus 13,960 bytes in the
negative. These are build observations, not physical firmware stack guarantees.
No image is executed, staged or an authorized package.

The generic diagnostic now links only this read-only layer for optional parent
baseline records, under `GU_PROBE_PARENT_BASELINE`. Its manifests bind the external
read-only files; LOCAL input hashes include the same files. Parent records use
distinct syntax, and the final target/capability check remains before bounded MMIO.
An unavailable optional observation never permits a changed/NULL method to be
called. Capability compromise ends the capture using frozen cleanup, without
continuing into graph services whose methods may have changed. Named probes do
not request this extra collection. The correction core and owned adapter remain
unconnected; no physical EFI or unlock qualification was performed.

Capture fixtures cover all parent depths, both root types, UID/segment boundaries,
stable wrong GPU pins, bad bus chains, interface replacement between scans, missing
parent resolution, partial output, strict status handling, mutable input, callback
reentry and overlapping arguments. Four extra compiled mutations remove GPU pinning,
two-scan equality, interface pinning and whole-chain capability checks and must fail.


## Exact MSI 3080 Ti research envelope

The local MSI predicate in snapshot.c restricts research admission for 10de:2208 to the
ASUS 1043:8803 subsystem at segment zero, 2d:00.0, BAR0 0xfa000000,
and one AMD 1022:1483 parent at 00:03.1 forwarding only bus 2d.
The shared snapshot predicates still validate complete snapshots, raw command, cache,
parent attributes/support and the one-shot transaction. The adapter additionally
validates controller paths, interface capabilities, complete repeated reads and
the upstream exclusive GPU ownership claim. No ownership check is relaxed.

This is a PCI snapshot envelope, not authentication of motherboard/BIOS,
PROM, GPU memory geometry or firmware signatures. Parent cache/support values
in the new tests are synthetic consistent assumptions, not values observed
by the private hardware helper. The mock uses supplied protocol/path bindings
and needs no active owner edge for the parent. No captured code or private
asset is needed.

The [hardware report](../../evidence/msi-x570-3080ti/README.md) concerns a
different private implementation. It supplies supporting observations, not
hardware validation of this adapter or permission to wire it into production.
The snapshot envelope is also used by the read-only baseline collector; an
accepted snapshot is not permission to correct the device. The owned adapter
still requires its independent self-exclusive claim and lifetime guarantees.
In particular, the documented pre-NVIDIA-Stop integration gap remains unresolved.
Normal profile/family/firmware/proven admission remains unchanged. The added
mutation must compile and then be rejected when the MSI-specific restrictions
are bypassed; compilation errors do not count as guard detection.

## Post-Stop observation transition

`stop-transition.{h,c}` supplies a separate pure research predicate for the
post-Stop state described in the MSI report. A baseline must pass the existing
snapshot policy and have corrected attributes exactly MEMORY, with raw command
2. A complete observation may retain that state or lose only the raw memory
decode bit and its corresponding cached MEMORY attribute. All other GPU config
bits (including PCI status), handles/interfaces, locations and supported bits,
and every parent field must remain exactly equal. A memory-off result also
requires MEMORY in the unchanged supported mask. IO, BME, unknown cache bits,
uncorrected baselines, partial observations and unrelated drift are refused.

The enum result is REFUSED, UNCHANGED or MEMORY_OFF. There is no output pointer,
allocation, callback or write; supplied input storage must remain immutable during
the call. MEMORY_OFF describes the observed delta, **not permission to restore**.
The function does not prove that NVIDIA Stop ran, establish exclusive ownership,
authenticate captures or establish freshness/atomicity. BAR/PROM/cold-state,
driver release and final handoff checks remain independent requirements.

```powershell
python -I research/pci-decode/test-stop-transition.py --clang C:\TOOLS\LLVM20\bin\clang.exe --mutations --output research/pci-decode/build/your-new-stop-transition
```

Run from a host shell with the existing MSVC headers/libraries available. The
runner builds a RAM executable and a freestanding COFF object, records source
hashes and requires ten broken guards to compile before explicit assertion failures.
Fixtures sweep every config bit and metadata/attribute/support bit of the GPU
and all 1..16 synthetic parents, over three PCI segments. They are synthetic
models, not private captured snapshots or another hardware success. No EFI image
is linked/executed/staged by this runner. The predicate is not connected to
production, the generic read-only collector, or the owned correction caller.
The ordinary capture still requires memory-on command2. The opt-in research
collector below can obtain a memory-off observation; the pre-Stop
mismatch/ownership ordering remains necessary integration work.

## Opt-in post-Stop read-only collector

When compiled with `GU_DS_POST_STOP_CAPTURE=1`, `efi-capture.c` additionally offers
`GuDsEfiCaptureAfterStop(Context, Boot, Target, Before)`. Other defined values are
compile errors. Normal builds neither expose this entry nor reference the new
transition library. No shipped builder selects this option.

The caller must supply a corrected pre-Stop baseline obtained with the same pinned
target. The snapshot contains no historical device path, so this past-path
association is a caller contract, not something the function can authenticate.
The function freezes that baseline before firmware callbacks, checks disjoint
input/output/service storage, and uses the existing bounded parent-path collector
and shared reentry guard. Both complete scans must pass `GuDsStopTransition` and
agree exactly: switching between two individually allowed states is refused.
The ordinary entry retains its original policy even in an opt-in build.

This entry makes only the original read-only calls. It neither stops drivers,
claims a protocol, restores MEMORY, nor invokes the correction adapter. Serialized
controller access, trusted firmware/read-only callbacks and retained lifetimes
remain caller requirements. Two matching scans do not prove an atomic snapshot
or exclude changes after the last read. The code is not wired into the production
release lifecycle and has no physical qualification.

```powershell
python -I research/pci-decode/test-post-stop-capture.py --clang C:\TOOLS\LLVM20\bin\clang.exe --mutations --output research/pci-decode/build/your-new-post-stop-capture
python -I research/pci-decode/test-readonly-image.py --post-stop --clang C:\TOOLS\LLVM20\bin\clang.exe --lld-link C:\TOOLS\LLVM20\bin\lld-link.exe --stack-mutation --output research/pci-decode/build/your-new-post-stop-image
```

The host model runs the ordinary collector suite as well as the post-Stop cases,
including cross-entry fresh-context reentry, callback faults, partial output,
capability/target/parent drift, caller baseline edits, storage overlap and changes
between scans. Each ordinary service-failure case is followed by a separate valid
session to check guard release. Eight broken guards must compile and fail at runtime;
define values 0 and 2 must fail compilation. The link test retains both read-only
entries and the pure transition, checks PE/imports/no-actuator symbols and bounded
function stack frames. Without `--post-stop`, it also checks that the ordinary
collector object contains no post-Stop entry or transition reference. The synthetic
images are never executed or staged and are not deployment packages.

## Opt-in held-claim MEMORY restoration

`GU_DS_POST_STOP_RESTORE=1` additionally enables `GuDsEfiInitializeRestore` and
`GuDsEfiRestoreRun` in the research adapter. Values 0 and 2 are compile errors.
Ordinary builds contain neither restoration entry nor a transition dependency;
no shipped builder selects this option. All translation units sharing adapter
contexts must use the same feature definitions. Ordinary Run refuses restore-mode
contexts, and RestoreRun refuses ordinary/noncanonical modes.

Initialization freezes the corrected pre-Stop baseline and pinned bindings,
requires MEMORY support and performs no firmware calls. The caller must already
hold and retain the exact self-exclusive GPU claim; the adapter does not acquire
or close it. The same target/path association, trusted firmware/callbacks,
serialized access and retained storage/interface lifetimes remain prerequisites.
Driver Stop, BAR/PROM/cold-state qualification and handoff checks are separate.

The run validates two complete observations around a durable intent log. Each
scan must satisfy the restricted post-Stop policy, both scans must agree, and the
state after logging must equal the initial post-Stop state. If MEMORY is already
enabled, the operation logs/rechecks without writing. Otherwise it holds the last
validated ownership-query allocation across one frozen
`Attributes(Enable, MEMORY, NULL)` call. No FreePool or log callback occurs between
that final query and Enable. IO/BME enable, config/MMIO writes, retries and rollback
are not offered. Retaining a query buffer is not an ownership lock or atomicity
guarantee.

Only exact EFI_SUCCESS is accepted. Enable warning/error remains failed even if
its bounded post-observation matches the baseline. Cleanup uncertainty stops
further work and preserves the raw status. Successful restoration requires exact
GPU/parent equality with the corrected baseline, a durable observation log and
another complete matching observation after that log. This does not exclude
changes after the last sampled read or trusted callback.

The single-use `GU_DR_TRANSACTION` separately records Started, EnableInvoked,
PostObserved, ReleasedOrigin, raw EnableStatus and ObservationStatus. ReleasedOrigin
names the policy path, not proof that Stop occurred or evidence was authenticated.
EnableStatus starts at
EFI_NOT_STARTED; EnableInvoked distinguishes no call from that actual firmware
error. PostObserved means a successful complete owned observation after Enable,
not proof of a successful write. Existing adapter ownership/cleanup statuses and
observed flags remain separate. Active policy/report/snapshots use private bounded
storage and the shared workspace guard, including across fresh-context callbacks.
Pool alias checks cover that storage and the actual restoration report size.

```powershell
python -I research/pci-decode/test-efi-restore.py --clang C:\TOOLS\LLVM20\bin\clang.exe --mutations --output research/pci-decode/build/your-new-restore-model
python -I research/pci-decode/test-owned-image.py --restore --clang C:\TOOLS\LLVM20\bin\clang.exe --lld-link C:\TOOLS\LLVM20\bin\lld-link.exe --stack-mutations --output research/pci-decode/build/your-new-restore-link
```

The RAM model composes the real opt-in collector, held-claim restoration and final
collector verification. It also runs the ordinary adapter suite, callback
fault/warning/partial-output sweeps, no-effect and partial-effect Enable errors,
cross-mode/reentry, policy/report edits, claim loss, log/cleanup failures and 39
private/caller-report/original-input pool aliases. Fifteen broken variants must compile and fail
explicit assertions; process crashes do not count. The stop-snapshot alias mutant
removes both overlapping defenses, because either alone still protects that
storage. The link fixture retains both experiments and the existing correction
lifecycle, records PE/import/symbol and bounded stack evidence, and rejects five
compiled automatic-storage variants. None of these synthetic images is executed,
staged or a qualified deployment package. Production pre-Stop cache/claim ordering
and physical hardware qualification remain unresolved.

## Uncorrected-before release hypothesis: observation only

The contributor's [pinned pre-step](https://github.com/kevinwwillis/Windows-GPU-UNLOCK/blob/ff93077/research/msi-x570-3090/prestep/prestep.c)
opens PCI protocols using GET_PROTOCOL, not an exclusive claim. Its
[core](https://github.com/kevinwwillis/Windows-GPU-UNLOCK/blob/ff93077/research/msi-x570-3090/prestep/decode-sync.c)
first attempts Enable(IO), then Disable(IO). This differs from the shared
held-claim correction contract and is not adopted here. The published wrapper log
shows raw command2 before NVIDIA Stop and0 afterwards, with only the MEM raw bit
changing across the complete GPU config; this boot followed the contributor's
cache correction. It does **not** establish that Stop directly from an uncorrected
cache300 state will reach raw0/cache0. That alternative remains a synthetic
hypothesis, not another reported hardware success.

`GuDsPlanReleasedMismatch(Before, After, Plan)` validates actual raw2/cache300
and actual raw0/cache0 snapshots. All other GPU config/status, identity/location,
support and every parent field must match exactly, and MEMORY must be supported.
Only then does it produce `GU_DS_RELEASE_PLAN`: a separately named PlannedGpu with
the original GPU config and target MEMORY attributes, plus the observed attribute
values and MEMORY restore mask. This type contains no Snapshot/Complete field.
It never rewrites either observation or labels the derived target as an observed
corrected pre-Stop baseline. Disjoint failures clear the plan; overlap refusal
preserves argument storage.

`GuDsReleasePlanMatches` revalidates the supplied pair and the derived GPU fields.
It is **not a fingerprint of earlier snapshots**: the plan stores no parent
contents, so a different valid pair with the same GPU target and parent count can
derive the same plan. A future actuator must retain private copies of the actual
full original snapshots and the pinned paths, then revalidate those copies at use.
Ready or a matching plan alone grants no Stop/claim/write permission.

With the existing `GU_DS_POST_STOP_CAPTURE=1` research option,
`GuDsEfiCaptureReleasedMismatch` freezes an actual cache300 baseline and collects
only the restricted raw0/cache0 observation. Each full scan must produce a valid
plan and both scans must agree exactly. The output remains the actual raw0/cache0
snapshot. The corrected-before `GuDsEfiCaptureAfterStop` and ordinary capture
contracts remain unchanged. The plan and collector are tested by the existing
transition/post-Stop host runners and retained by the opt-in synthetic link tests.

The alternate collector adds no driver Stop, ownership acquisition or restoration.
Its derived target is not passed into `GuDsEfiInitializeRestore`, whose
corrected-observed-before contract still applies. The separate initializer below
retains the actual observations and explicitly derived target before reusing the
research-only held-claim restoration algorithm.
Default CapturePermit, Full.Attributes, RestoreDecode, final verification,
profile/proven admission and handoff are unchanged. Relaxing only CapturePermit
would be incorrect: the existing restoration/final verification would still
expect the original300 attributes. Exact driver/console-release qualification
and hardware evidence for the uncorrected Stop transition remain outstanding.

### Explicit released-origin restoration binding

Under `GU_DS_POST_STOP_RESTORE=1`, `GuDsEfiInitializeReleasedRestore` accepts actual
Before300, actual After0, their separately derived Plan and the caller's pinned
bindings. It revalidates the full pair and plan without firmware callbacks, then
copies both complete originals and the plan into private context fields.
Expected is constructed from that private Before with only the verified
Plan.PlannedGpu substituted; `ReleasedOrigin=TRUE` explicitly labels Expected as a
planned target. The input observations remain unchanged. All translation units
must use the same feature definitions because the context layout changes.

Initialized context fields are private and immutable by contract. At Run, the
adapter revalidates the frozen pair/plan and requires Expected to equal the private
Before with only cached IO cleared. It rejects noncanonical origin values and a
false origin flag with remaining released-history metadata. The complete context
and report are copied into private per-image storage before callbacks. Original
input pointers are retained only for lifetime/alias protection; later caller input
edits cannot change the run's policy. This protects the chosen input pair during
the operation, not against a caller fabricating data or deliberately rewriting an
entire private context before Run.

The first current owned observation must exactly equal private ActualAfter before
the existing intent-log/recheck/Enable sequence can begin. Already-MEMORY-on or a
different otherwise valid observation is refused at this boundary. All original
parent contents are retained, so a matching GPU-only plan cannot silently replace
the parent baseline. Original Before/After/Plan, the extended private/caller context,
scratch and the output report are covered by pool/output alias checks.

The host model composes the actual released-mismatch collector, this explicit
initializer, one held-claim MEMORY restoration and an ordinary final collector.
Tests cover bounded routes, callback faults, raw failed-Enable and cleanup status,
partial Init refusal through both Run APIs, changed parent history, already-on
current state, mutated plans/origin, caller input/context/report edits and additional
original-buffer aliases. These remain RAM models and invalid-target link fixtures.
The binding neither performs nor qualifies NVIDIA Stop, obtains a claim, changes a
production gate, or establishes physical compatibility for the hypothesis.

### Production configuration-reader regression

The separate `test-config-read.py` runner tests the existing production
`ReadConfigFull` helper from `internal-boot/boot/full-release.c`. It does not link
the correction/restoration experiments above into a boot path.

The helper freezes its target interface and dispatch methods, checks exact BDF
outputs initialized to nonmatching values, and compares two complete 64-DWORD
reads with complementary initial fills. The caller's buffer is published only
after agreement and the existing identity/class/BAR/BME checks. Failure leaves
that buffer unchanged. All PCI values remain representable; no sentinel value
is forbidden as device data. Command values with MEMORY disabled remain valid
for the existing post-driver-release restoration checks.

```powershell
python -I research/pci-decode/test-config-read.py --clang C:\TOOLS\LLVM20\bin\clang.exe --mutations --output research/pci-decode/build/config-read-check-1
```

The RAM model covers omitted location fields/bytes, inconsistent full reads,
warning/error statuses, changed method/service/target bindings, unchanged output
on refusal and legitimate A5/5A/all-ones config words. Fixed profiles and synthetic
LOCAL segment/bus variants use the actual helper; deliberate broken guards must
fail assertions. Synthetic headers/configuration remain in the new test output;
the runner never installs a LOCAL header, writes qualification evidence, accesses
hardware or executes EFI. The two reads check stability at service-return
boundaries, not atomicity or truthful behavior of arbitrary firmware.

### Host-only bridge through actual release phases

`GU_RELEASE_PARENT_AUDIT=1` connects typed parent observations to the actual
`GuPrepareConsole` and `GuReleaseGop` source paths. It requires hosted compilation
and `GU_DS_POST_STOP_CAPTURE=1`; freestanding EFI builds are rejected. No shipped
builder, LOCAL admission or staging path enables it.

The baseline is captured before the first console Disconnect, not after console
preparation. Fresh full GPU/parent observations precede console/EDID/NVIDIA
release, exclusive acquisition and MEMORY restoration. Audits run before the
existing final console/code/config/graph/ownership checks, so their callbacks do
not silently replace those checks. Effect dispatch is frozen, including cleanup.
Shared operation guards reject nested preparation/release before static state
can be reset, and each observation uses a distinct bounded single-use collector.

The additional `GU_RELEASE_MISMATCH_RESEARCH=1` models actual raw2/cache300 before
release, actual raw0/cache0 after NVIDIA release, and planned raw2/cache200 after
MEMORY-only restoration. Complete original observations stay separate from the
derived plan. `Full.Attributes` remains the actual300; `Full.TargetAttributes`
becomes200 only after the actual released observation passes the plan predicate.
The pair is rechecked before/after the claim and before Enable. A fresh restored
GPU/parent observation must match the frozen original with only cached IO removed.
Audit without this additional switch continues to refuse cache300 before any
console release. This prototype does not invoke Disable(IO) or enable IO/BME.

```powershell
python -I research/pci-decode/test-release-parent-audit.py --clang C:\TOOLS\LLVM20\bin\clang.exe --mismatch --mutations --output research/pci-decode/build/release-parent-check-1
```

With a configured host compiler environment, this replays the actual production
functions using synthetic LOCAL metadata, driver/PROM buffers and a parent PCI
interface. Tests inject parent drift at each read, changed effect dispatch,
claim loss, foreign graph edges, changed driver bindings and nested entry.
Observed data must remain unchanged by target derivation, and raw0 paired with
cache100/200/300 is refused. Deliberately broken guards must fail assertions.

This remains synthetic research: the non-aggregate model accepts EDID-driver
configurations with 1–2 display children and no-EDID-driver configurations with 1–4.
Broader parent/segment coverage and
a permitted invalid-target EFI link fixture remain outstanding. No uncorrected
physical Stop transition, new hardware support, ready
package or authorization to install/execute follows from these RAM results.

The host-only final verifier now collects a fresh typed GPU/parent observation
before the existing final display/config/BAR/attribute/graph checks. It compares
GPU identity, BDF, interface, Supported and planned attributes exactly. Only GPU
config uses the existing `VerifyConfigWord` status-clear policy: after the child,
the two already-recorded CED/URD status bits may clear only with its exact layout
condition; cold checks, new bits, control changes and other words remain exact.
Every parent metadata/config/attribute field stays exact. Neither the baseline
nor observed snapshots are normalized to make a comparison pass.

Recursive final verification is refused before diagnostic reset, capture budget
consumption or TPL changes. Repeated legitimate handoff checks consume distinct
observations up to the fixed budget; exhaustion refuses further callbacks. Tests
cover both corrected and mismatch histories, all GPU/parent config words, every
omitted parent byte, metadata/attribute drift, warnings/errors, foreign graph
changes, recursion, TPL balance and final dispatch-drift diagnostics. These remain
service-boundary observations, not atomicity or physical FLR qualification.

The same host-only bridge now distinguishes Open's raw return from an observed
claim. A frozen passive reference baseline must contain no existing reference
from this image, including GET_PROTOCOL. Writing requires raw Open SUCCESS,
the exact interface, unchanged passives and one fresh self-exclusive record
with null controller and count1. Final query buffers remain held through Open,
Enable and Close respectively, eliminating an intervening Free callback there.

Cleanup uses a fresh successful bounded query for attribution, even when Open
returned warning/error. It may close exactly our unambiguous record while leaving
foreign references intact. Multiple/ambiguous same-image references, malformed
or failed queries and unknown attribution are left untouched and reported with
`ClaimMayRemain`; `Full.Owned=false` alone is not proof of cleanup. Close is invoked
at most once. Its raw warning/error remains failure even if the reference
disappeared, and SUCCESS with a remaining reference also fails. Cleanup reentry
performs no further query or Close and preserves its first result.
An unsuccessful baseline cannot be reused to acquire later in the same transaction.

Observed flags distinguish an actual EFI_NOT_STARTED return from a phase that
never ran. The first Free failure cannot be erased by later successful calls.
Query pointers overlapping known private state, PCI interfaces, handle token
addresses or the prepared graph are rejected without freeing borrowed storage.
This is bounded defensive checking under the existing trusted pool/lifetime
contract; it is not general memory provenance authentication.

The actual-source RAM tests cover partial Open/Close effects, warnings/errors,
wrong interfaces, absent/ambiguous claims, foreign+self mixtures, preexisting
same-image passives,0/63/64 passive bounds, malformed/duplicate/borrowed query
buffers and Free failures. These observations do not lock firmware state or
prove absence after every subsequent callback. Wider display variants and
physical/EFI qualification remain separate outstanding work.

For EDID-driver replay, pass `--edid-driver --children 2` to the same runner; omit
the switch for no-EDID firmware and select `--children 1` through `--children 4`.
EDID counts above 2 are rejected before output creation. `--mismatch` exercises
both corrected and hypothetical mismatched histories in each selected topology.

The model loads separate synthetic EDID/NVIDIA images with exact length checks,
binds the EDID code range to its SHA pin and applies the actual release code's
normal driver-profile checks. Generated capture/header/driver/PROM/config hashes
are recorded. Truncated, extended and changed-code images must fail assertions.
EDID tests inject partial effects followed by error/warning, SUCCESS with a stale
child edge, parent/NVIDIA binding changes, and remaining-child path/EDID
binding/code drift. No NVIDIA Stop, claim or MEMORY restore may follow those
failures. Duplicate/foreign/malformed child topology is refused before EDID or
NVIDIA release. None of these synthetic inputs constitute hardware evidence or
LOCAL qualification.

For the default command2 aggregate GOP model, add `--aggregate --edid-driver --children 1`
or `--children 2`. It uses a separate adapter around the existing aggregate
production-path fixture. Preparation must make zero Disconnect calls; release
must stop exactly the selected EDID children and then NVIDIA, restore MEMORY
only, and preserve actual Before300 separately from planned target200. The
synthetic baseline explicitly uses command2 and does not qualify command3.

The aggregate adapter adds a real RAM parent PCI interface/path and consistent
handle/protocol inventory. Display-path lookups delegate to the legacy fixture
so its shortened/longer path and wrong-parent faults remain effective. Its Close
mock removes only the precise image/target/controller/GUID tuple, preserving
other references. All original24 aggregate modes remain checked, including
reviewed virtual GOP survival and rejection of unrecognized GOPs, stale NV edges,
lost protected edges and wrong code fingerprints. Additional tests inject
parent/effect-dispatch drift, per-child EDID partial effects, remaining-child
path/binding/code changes, late protected-graph changes before Enable, partial
Open/Close, borrowed buffers, recursion and post-child parent/status failures.
These are RAM models, not physical aggregate firmware evidence.

The separate `--iomem` run models a coherent raw command3/cache300 release
origin. It may be combined with `--mutations`, and supports aggregate EDID1–2,
nonaggregate EDID1–2 and nonaggregate no-EDID1–4 children. Do not combine it with
`--mismatch`: raw2/cache300 mismatch still derives a MEMORY-only target200;
coherent command3 retains the original IO+MEM target300 and never enters that
correction route. The ordinary correction validator/collector remains raw2-only.

`GuDsReleaseSnapshotValid` shares structural checks while separately requiring
raw3/cache300 and both IO/MEM capabilities for that origin. Opt-in release-origin
and IO+MEM post-Stop collectors retain the same frozen inputs, single-use private
workspace, reentry refusal, exact bindings and two complete matching scans.
`GuDsIoMemStopTransition` observes only coherent raw3→0/1/2/3 with corresponding
cache0/100/200/300; other GPU configuration/identity/support and every parent
remain exact. The bridge freezes its first post-Stop snapshot and rejects a later
different coherent subset. Existing restore-mask checks enable only originally
present missing bits; no Enable occurs for a zero missing mask. Original300 and
final target300 remain distinct fields even though their values agree.

The aggregate actual-source model exercises all four post-Stop subsets, exact
restore masks, the zero-mask path and later-subset drift before Enable. The
nonaggregate model retains its EDID/topology/ownership/final-observation fault
suites for command3. `test-post-stop-capture.py --mutations` also compiles the
IO+MEM pure predicate and read-only collector matrix over parent depths and
segments. These synthetic histories do not demonstrate an actual driver Stop
or authorize EFI activation. Default builders/admission and the hosted-only
release bridge restriction are unchanged.

For the fixed original B650M retained AMD frontend, add
`--amd-retained --edid-driver --children 1` or `--children 2`, with either
`--iomem` or the separate command2 `--mismatch` run. The audit-only command2
run still refuses cache300 before console release. This adapter keeps the fixed
B650M guard: it is not LOCAL admission for another motherboard or display GPU.

Its graph and full configuration are generated synthetic RAM inputs, with
separate AMD GOP/text/shared EDID relations and the fixed AMD bus12/RTX bus1
identities. Parent resolution/inventory is independent; AMD path resolution
delegates to the original fixture. One/two RTX child paths, precise claim cleanup,
typed parent observations and existing final GPU status policy remain checked.
AMD EDID owner/count, framebuffer, geometry or path changes after the first EDID
Stop must prevent further Stop/claim/restore. Late AMD input/display or final
graph-callback binding drift must block handoff. Nonheadless verification has no
outer RestoreTPL callback, so its final-binding fault is injected in the last
parent protocol inventory of the final graph scan rather than in that headless
callback. Two-child runs also replay the original retained-AMD fixture with the
research bridge disabled. No current hardware capture, physical support expansion
or automatic-boot qualification follows from these synthetic observations.
