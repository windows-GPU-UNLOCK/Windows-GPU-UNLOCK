# Optional boot animation

The research USB and internal headless wrappers can play a prerendered 1920×1080 animation before
attempting the unlock. Esc is available during the three-second countdown.
The final burst plays immediately before driver release. Existing machine
profiles, preflight checks and Windows handoff rules still apply.

Generate and pack the generic GPU artwork locally:

```powershell
python -m pip install numpy "pillow>=10.1" opencv-python imageio-ffmpeg lz4
python .\research\headless\render-splash.py
python .\research\headless\pack-splash.py .\splash-preview.mp4 .\SPLASH.BIN
```

Add `-SplashAsset .\SPLASH.BIN` to the existing build invocation:

- **USB:** use `research/headless/build-usb.ps1` and stage with
  `research/headless/stage-usb.ps1`.
- **Dedicated internal ESP:** use `research/headless/build-unlock.ps1` and
  stage with `internal-boot/Headless.ps1`. Use its existing manual registration
  and confirmation workflow. The installer refuses to replace a different
  installed file, including an older wrapper or splash asset.

The wrapper pins the asset length and SHA-256 at build time. The default
build retains the existing text prompt.

The player decodes independent RGB565 frames. On a compatible linear surface,
it compares an initial centered Full HD GOP copy with streaming writes to
the framebuffer reported by GOP. When direct writes are faster, it can fill
the largest centered 16:9 viewport up to 3840×2160 if the initial decode and
copy fit within 24 ms. Otherwise it keeps the centered Full HD viewport.
Playback skips unchanged pixel groups and follows elapsed time, so slower
firmware may present fewer frames. Graphics activity and allocations end
before driver release.

Missing or invalid assets, unsupported displays and an unavailable timestamp
protocol fall back to the existing prompt. This is an experimental option
for the firmware's manual boot menu. The log reports the selected copy path,
viewport width and number of countdown frames presented.
