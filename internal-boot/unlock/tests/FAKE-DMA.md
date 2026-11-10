# Fake DMA allocator regression (#368)

From the repository root, with an existing GCC-compatible compiler:

```sh
python internal-boot/unlock/tests/test_fake_dma.py --cc gcc
python internal-boot/unlock/tests/test_fake_dma.py --cc gcc --sanitize
```

This compiles the actual `map` / `map_buffer` callback bodies from both test
copies with the repository's EFI type headers and minimal RAM-only state. It
checks ordinary and forced identity-collision inputs, three successive mappings,
page alignment, monotonic disjoint device ranges and their complete 32-bit ends.
The synthetic CPU pointer values are never dereferenced. No host address is
reserved, no ASLR setting is changed, and no PROM or firmware asset is needed.
The source extraction intentionally fails if the callback is renamed/removed.

The fixtures now skip one page if the next device address equals that mapping's
CPU pointer. Transaction range and non-identity assertions remain in place;
port high/partial/unaligned mapping injection and production validation are
unchanged. The port's first allocation checks either the normal base or the
single-page skip, according to the actual CPU pointer.

To compare with an existing baseline checkout, run the new script with
`--source-root /path/to/baseline`. At main commit
`dc19de9204df9b58d6eaa5b0e4697e0657b617de`, all four ordinary cases pass and all
four forced-collision cases fail. With the fix all eight cases pass.

This narrow callback regression does not execute the whole transaction or
establish hardware compatibility, DMA coherency, firmware safety or write
eligibility. Run the existing complete port suites separately. Full transaction
qualification still requires its independently verified assets and prerequisites.
ASan/UBSan are optional; LeakSanitizer may be unavailable under traced runners.
Disabling leak detection for such a runner is not a leak-check pass.

PR #193 separately extends the internal port suite's 32-bit boundary and retained
cleanup tests. This change does not duplicate that coverage or alter those cases.

The callback script exercises ordinary-base ranges, not exhaustive boundary
behavior. Combined with PR #193, a synthetic CPU pointer equal to its exact
`0xfffff000` boundary address would make this fixture skip beyond 32 bits. That
combined exact-boundary collision remains to be resolved and tested before
combined qualification; this change does not alter PR #193.
