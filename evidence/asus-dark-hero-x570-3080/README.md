# RTX 3080 10GB LHR / ASUS ROG CROSSHAIR VIII DARK HERO: successful experimental USB unlock

One supervised Windows USB unlock and handoff succeeded. This is an experimental report, not a claim of general compatibility or repeated-boot stability.

- ASUS ROG CROSSHAIR VIII DARK HERO, BIOS 5601; Ryzen 9 5950X without integrated graphics (single-adapter aggregate console, cf. #12/#121/#131).
- RTX 3080 10GB LHR, GA102 chip `0xb72000a1`, PCI ID `10de:2216`, subsystem `1043:8823`, VBIOS `94.02.71.40.ae`, memory strap `0x1183a4` value `0x2800`, bus `0A:00.0`.
- One NVIDIA display controller; observed NVIDIA GOP version `0x6000a` with `.text` sha256 `8924ba488419e5d82b524d10e8dd63bfe886f077026fae1a9cc03e25b920b276`, byte-identical to the existing GA102 `6000a` pin (#102/#138 evidence set) — no new GOP pin is introduced.
- Windows 11 build 26100; driver 621.01 at capture/unlock time; Secure Boot disabled.

Two captures from separate full shutdowns were coherent (PROM sha256 `96e72d6d590fe26d6fd318542665f893cb752e9a169ef833f19e8046aeed14d6` stable across boots). A local profile `LOCAL-221610de-88231043-96e72d6d` was generated from this machine's captures with the envelope/gate extension added in this PR, and all local-profile host jobs passed against that source. The generated headless USB build was then booted once: the report recorded transaction status 0, clean containment and FLR, with `SS0=0x88888888 SS1=0x8` verified before and after FLR from cold state `SS0=0x15701070 SS1=0x3`, and the payload completed its checks before starting Windows; display and NVIDIA driver returned normally.

The upstream screening benchmark (device selection patched to the 0A-bus single GPU; 4096³, median of 30 samples, two runs) measured FP16 60.90 / BF16 61.04 TFLOPS locked — the locked signature reported by #139 and #28 — and FP16 97.0-97.4 / BF16 96.3-96.9 TFLOPS after, approximately +59%, sustained at 1635 MHz SM, 203 W of a 320 W cap, no throttle-reason flags. The gap to other reports' 107-113 TFLOPS reflects this card's voltage/boost ceiling, not the transaction state. FP32 unchanged.

Limits: one supervised USB boot so far. Repeated cold boots, suspend/resume re-lock behavior, default automatic boot, long-term numerical correctness and real workloads remain to be fully characterized. No raw captures, PROM/image dumps, serials, device UUIDs or partition IDs are included. Asset provenance: the pinned CachyOS 610.43.03 input container was purged from its mirror on 2026-11-08; assets were generated from the permanent Arch Linux Archive container `c3367ff68632ac7daf6ca50ef7cbdd1cb5d09f7fe0b26125b312c73e52a34cf4`, whose inner `gsp_ga10x.bin` is bit-identical to the manifest pin, with all five generated assets hashing byte-exact to `assets.json`.
