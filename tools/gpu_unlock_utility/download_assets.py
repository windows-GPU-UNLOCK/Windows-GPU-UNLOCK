"""Automated firmware asset downloader and extractor for Windows GPU UNLOCK.

Downloads the official pinned NVIDIA open kernel module source and nvidia-utils package,
synthesizes and extracts the 5 required GA102 firmware assets, and places them into assets/.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
import zlib

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]
ASSETS_JSON = REPO_ROOT / 'unlock' / 'assets.json'
DEFAULT_TARGET = REPO_ROOT / 'assets'

SRC_URL = "https://download.nvidia.com/XFree86/NVIDIA-kernel-module-source/NVIDIA-kernel-module-source-610.43.03.tar.xz"
SRC_SHA256 = "7e118923c7a23edc36114d63273a46e3e04e9af98695a42203e7ac2dfe9fc1dc"

UTILS_URL = "https://archive.cachyos.org/archive/cachyos-v3/nvidia-utils-610.43.03-1-x86_64_v3.pkg.tar.zst"
UTILS_SHA256 = "e17e7c92eeffa178b0fe1f40eb17a47095f8fc3ce4a77bf115cf5bd5a4df86e9"

# V67 Payload Parameters
PAYLOAD_SIZE = 0xFA00
FILL_DWORD = 0x0000019C
PATCHED_WORDS = {
    0x1100: 0x00000007,
    0xF948: 0xFFFFFFFF,
    0xF950: 0x00000D44,
    0xF960: 0x00823804,
    0xF968: 0x00001FCE,
    0xF974: 0x00000000,
    0xF97C: 0x00001101,
    0xF980: 0x000084C8,
    0xF984: 0x00008E18,
    0xF98C: 0x000084C8,
    0xF990: 0x00000000,
    0xF998: 0x00001FCE,
    0xF9A4: 0x0000FFBC,
    0xF9AC: 0x00005789,
    0xF9BC: 0x00000D44,
    0xF9CC: 0x00000003,
    0xF9D4: 0x00001FCE,
    0xF9E8: 0x00000D52,
    0xF9EC: 0x000081EE,
}

BOOTER_MAGIC = 0x314C5442
PINNED_SOURCES = {
    'g_bindata_kgspGetBinArchiveBooterLoadUcode_GA102.c': '04cd3db7f670adc4efd79d2e76217bb809fffddfbd6f1af884cde2af26dd39af',
    'g_bindata_kgspGetBinArchiveGspRmBoot_GA102.c': '35e5aa9075ad3898b6022ffd5820c953d809caa7dabd530cfc1a83dc2a67c5bd',
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest().lower()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().lower()


def download_with_progress(url: str, dest: Path, expected_hash: str = None) -> Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_symlink():
        raise ValueError('Refusing a symlinked cache file; choose a new cache directory.')
    if dest.exists():
        if expected_hash and sha256_file(dest) == expected_hash.lower():
            print(f"[*] Found verified cached: {dest.name}")
            return dest
        else:
            raise ValueError('Existing cache file does not match the pinned archive; choose a new cache directory.')

    print(f"[+] Downloading {url} -> {dest.name}...")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
    tmp = None
    try:
        with tempfile.NamedTemporaryFile(mode='wb', prefix=dest.name + '.', suffix='.download',
                                         dir=dest.parent, delete=False) as out:
            tmp = Path(out.name)
            with urllib.request.urlopen(req, timeout=120) as resp:
                total = int(resp.headers.get('Content-Length', 0))
                downloaded = 0
                while chunk := resp.read(1024 * 1024):
                    downloaded += len(chunk)
                    out.write(chunk)
                    if total > 0:
                        pct = downloaded * 100 // total
                        print(f"\r    Progress: {downloaded / 1024 / 1024:.1f} MB / {total / 1024 / 1024:.1f} MB ({pct}%)", end="", flush=True)
                    else:
                        print(f"\r    Progress: {downloaded / 1024 / 1024:.1f} MB downloaded", end="", flush=True)
        print()
        if expected_hash:
            h = sha256_file(tmp)
            if h != expected_hash.lower():
                raise ValueError(f"Checksum mismatch for {dest.name}: expected {expected_hash}, got {h}")
        # Exclusive creation also refuses a destination created while downloading.
        # The final path is never opened with truncation or replace semantics.
        created = False
        try:
            with dest.open('xb') as target:
                created = True
                with tmp.open('rb') as verified:
                    shutil.copyfileobj(verified, target)
        except BaseException:
            if created:
                dest.unlink(missing_ok=True)
            raise
        return dest
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)


def build_v67_payload() -> bytes:
    word = FILL_DWORD.to_bytes(4, "little")
    payload = bytearray(word * (PAYLOAD_SIZE // len(word)))
    for offset, value in PATCHED_WORDS.items():
        payload[offset : offset + 4] = value.to_bytes(4, "little")
    return bytes(payload)


def _array_bytes(text: str, label: str) -> tuple[bytes, bool, int]:
    marker = f'BINDATA_LABEL_{label}_data[]'
    if text.count(marker) != 1:
        raise ValueError(f"missing or duplicate {label}")
    start = text.index(marker)
    window = text[max(0, start - 400):start]
    compression = re.findall(r"COMPRESSION: (YES|NO)", window)
    sizes = re.findall(r"DATA SIZE \(bytes\): (\d+)", window)
    if not compression or not sizes:
        raise ValueError(f"missing storage declaration for {label}")
    expected = int(sizes[-1])
    compressed = compression[-1] == 'YES'
    if not 0 < expected <= 16 * 1024 * 1024:
        raise ValueError('asset exceeds extraction limit')
    declaration = re.match(re.escape(marker) + r"\s*=\s*\{([^}]*)\};", text[start:], re.S)
    if not declaration:
        raise ValueError('malformed byte-array declaration')
    tokens = declaration[1].strip().rstrip(',').split(',')
    if any(not re.fullmatch(r"\s*0x[0-9a-fA-F]{2}\s*", x) for x in tokens):
        raise ValueError('non-byte token in generated array')
    raw = bytes(int(item, 16) for item in tokens)
    if compressed:
        stored = re.findall(r"COMPRESSED SIZE \(bytes\): (\d+)", window)
        if not stored or len(raw) != int(stored[-1]):
            raise ValueError('compressed storage size mismatch')
        inflater = zlib.decompressobj(-15)
        data = inflater.decompress(raw, expected + 1)
        if not inflater.eof or len(inflater.unused_data) != 8 or inflater.unconsumed_tail:
            raise ValueError('truncated, trailing or oversized compressed stream')
        crc, size = struct.unpack('<II', inflater.unused_data)
        if size != expected or crc != zlib.crc32(data):
            raise ValueError('compressed checksum or size mismatch')
    else:
        data = raw
    if len(data) != expected:
        raise ValueError(f"{label}: inflated {len(data)} bytes, header says {expected}")
    return data, compressed, expected


def build_booter_bundle(source_text: str) -> bytes:
    image, _, _ = _array_bytes(source_text, "IMAGE_PROD")
    header, _, _ = _array_bytes(source_text, "HEADER_PROD")
    signatures, _, _ = _array_bytes(source_text, "SIG_PROD")
    patch_loc, _, _ = _array_bytes(source_text, "PATCH_LOC")
    patch_meta, _, _ = _array_bytes(source_text, "PATCH_META")
    num_sigs, _, _ = _array_bytes(source_text, "NUM_SIGS")
    if len(header) != 36 or len(patch_loc) != 4 or len(patch_meta) != 12 or len(num_sigs) != 4:
        raise ValueError("unexpected BooterLoad record size")
    fields = struct.unpack("<9I", header)
    loc = struct.unpack("<I", patch_loc)[0]
    _fuse, engine, ucode = struct.unpack("<3I", patch_meta)
    count = struct.unpack("<I", num_sigs)[0]
    if not count or len(signatures) != count * 384 or fields[4] != 1 or not ucode:
        raise ValueError('unsupported production Booter signature/application table')
    if loc < fields[2] or loc + 384 > fields[2] + fields[3] or fields[2] + fields[3] > len(image):
        raise ValueError('signature patch is outside DMEM image')
    for offset, size in ((fields[0], fields[1]), (fields[2], fields[3]), (fields[5], fields[6])):
        if offset + size > len(image) or offset % 256 or size % 256:
            raise ValueError('invalid Falcon transfer range')
    hdr = struct.pack(
        "<14I",
        fields[0], fields[1], fields[2], fields[3], fields[4], fields[5], fields[6],
        fields[7], fields[8], loc, ucode, engine, count, len(signatures),
    )
    prefix = struct.pack("<II", BOOTER_MAGIC, 1) + hdr + struct.pack("<II", len(image), len(signatures))
    return prefix + image + signatures


def extract_kernel_module_assets(tar_path: Path) -> dict[str, bytes]:
    print(f"[+] Inspecting {tar_path.name} for Falcon/GSP boot assets...")
    found_sources = {}
    with tarfile.open(tar_path, mode='r:xz') as tar:
        for member in tar:
            base = Path(member.name).name
            if base in PINNED_SOURCES:
                f = tar.extractfile(member)
                if f:
                    content = f.read()
                    h = sha256_bytes(content)
                    if h != PINNED_SOURCES[base]:
                        raise ValueError(f"Source file {base} hash mismatch: {h}")
                    found_sources[base] = content.decode('ascii', errors='replace')
                    print(f"    Found & verified {base}")
            if len(found_sources) == len(PINNED_SOURCES):
                break

    if len(found_sources) != len(PINNED_SOURCES):
        raise ValueError(f"Could not find all required generated sources in {tar_path.name}")

    booter_data = build_booter_bundle(found_sources['g_bindata_kgspGetBinArchiveBooterLoadUcode_GA102.c'])
    boot_src = found_sources['g_bindata_kgspGetBinArchiveGspRmBoot_GA102.c']
    gsp_boot_img = _array_bytes(boot_src, 'UCODE_IMAGE_PROD')[0]
    gsp_boot_desc = _array_bytes(boot_src, 'UCODE_DESC_PROD')[0]

    return {
        'booter_load_ga102.bin': booter_data,
        'gsp_boot_ga102.bin': gsp_boot_img,
        'gsp_boot_desc_ga102.bin': gsp_boot_desc,
    }


def extract_gsp_from_pkg(pkg_path: Path, temp_dir: Path) -> bytes:
    print(f"[+] Extracting gsp_ga10x.bin from {pkg_path.name}...")
    member_path = "usr/lib/firmware/nvidia/610.43.03/gsp_ga10x.bin"
    # Use native tar.exe (Windows 10/11 bsdtar supports .zst out of the box)
    cmd = ["tar", "-xf", str(pkg_path), "-C", str(temp_dir), member_path]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"tar extraction failed: {res.stderr}")

    extracted_file = temp_dir / member_path
    if not extracted_file.exists():
        raise FileNotFoundError(f"Extracted gsp_ga10x.bin not found at {extracted_file}")
    data = extracted_file.read_bytes()
    expected_gsp_hash = "572373620a37418f24dc16b5031c39338778c3257e48e8408de9a57291b24f3a"
    if sha256_bytes(data) != expected_gsp_hash:
        raise ValueError("gsp_ga10x.bin hash mismatch")
    print(f"    Verified gsp_ga10x.bin (Size: {len(data)} bytes)")
    return data


def acquire_all_assets(target_dir: Path, cache_dir: Path = None, keep_cache: bool = False):
    target_dir.mkdir(parents=True, exist_ok=True)
    if cache_dir is None:
        cache_dir = REPO_ROOT / '.cache' / 'gpu_unlock_downloads'
    cache_created = not cache_dir.exists()
    cache_dir.mkdir(parents=True, exist_ok=True)
    owned_downloads = []

    # Fast path: if all target assets are already present and verified, avoid redundant downloads
    if ASSETS_JSON.exists():
        try:
            specs = json.loads(ASSETS_JSON.read_text())
            if specs and all(
                (target_dir / s['Name']).is_file()
                and (target_dir / s['Name']).stat().st_size == s['Bytes']
                and sha256_file(target_dir / s['Name']) == s['Sha256'].lower()
                for s in specs
            ):
                print(f"[+] All {len(specs)} required firmware assets are already present and verified in {target_dir}.")
                return True
        except Exception:
            pass

    def acquire_archive(url, path, digest):
        existed = path.exists() or path.is_symlink()
        download_with_progress(url, path, digest)
        if not existed:
            owned_downloads.append(path)

    print("==========================================================")
    print(" Windows GPU UNLOCK - Automated Asset Acquisition")
    print(f" Target Directory: {target_dir}")
    print(f" Cache Directory:  {cache_dir}")
    print("==========================================================")

    # 1. Synthesize v67
    print("\n[1/4] Generating V67 signature payload...")
    v67_data = build_v67_payload()
    v67_file = target_dir / "v67-ga102-610.43.03.bin"
    v67_file.write_bytes(v67_data)
    print(f"    Generated {v67_file.name} ({len(v67_data)} bytes)")

    # 2. Download and extract NVIDIA kernel module source
    print("\n[2/4] Acquiring NVIDIA open kernel module source archive...")
    src_archive = cache_dir / "NVIDIA-kernel-module-source-610.43.03.tar.xz"
    acquire_archive(SRC_URL, src_archive, SRC_SHA256)
    boot_assets = extract_kernel_module_assets(src_archive)
    for name, data in boot_assets.items():
        (target_dir / name).write_bytes(data)
        print(f"    Wrote {name} ({len(data)} bytes)")

    # 3. Download and extract nvidia-utils (skip if gsp_ga10x.bin is already verified)
    gsp_file = target_dir / "gsp_ga10x.bin"
    gsp_spec = None
    if ASSETS_JSON.exists():
        try:
            specs = json.loads(ASSETS_JSON.read_text())
            gsp_spec = next((s for s in specs if s['Name'] == 'gsp_ga10x.bin'), None)
        except Exception:
            pass
    gsp_valid = (
        gsp_file.is_file()
        and gsp_spec
        and gsp_file.stat().st_size == gsp_spec['Bytes']
        and sha256_file(gsp_file) == gsp_spec['Sha256'].lower()
    )

    if gsp_valid:
        print("\n[3/4] gsp_ga10x.bin is already present and verified in target; skipping package download.")
    else:
        print("\n[3/4] Acquiring nvidia-utils package for GSP firmware...")
        utils_pkg = cache_dir / "nvidia-utils-610.43.03-1-x86_64_v3.pkg.tar.zst"
        acquire_archive(UTILS_URL, utils_pkg, UTILS_SHA256)
        # Never reuse/delete a caller's fixed temp_extract directory.
        with tempfile.TemporaryDirectory(prefix='gpu-unlock-extract-', dir=cache_dir) as temporary:
            gsp_data = extract_gsp_from_pkg(utils_pkg, Path(temporary))
            gsp_file.write_bytes(gsp_data)
            print("    Wrote gsp_ga10x.bin")

    # 4. Final Verification against assets.json
    print("\n[4/4] Verifying all assets against unlock/assets.json specification...")
    specs = json.loads(ASSETS_JSON.read_text())
    all_ok = True
    for spec in specs:
        f = target_dir / spec['Name']
        if not f.exists():
            print(f"    [FAIL] Missing {spec['Name']}")
            all_ok = False
            continue
        h = sha256_file(f)
        sz = f.stat().st_size
        if h == spec['Sha256'].lower() and sz == spec['Bytes']:
            print(f"    [PASS] {spec['Name']} ({sz} bytes, SHA256 matched)")
        else:
            print(f"    [FAIL] {spec['Name']} (Size: {sz}/{spec['Bytes']}, Hash: {h})")
            all_ok = False

    if not keep_cache:
        print("\n[*] Removing only source archives created by this run...")
        for path in owned_downloads:
            path.unlink(missing_ok=True)
        if cache_created:
            try:
                cache_dir.rmdir()  # Remove only our directory, and only if empty.
            except OSError:
                pass

    if all_ok:
        print("\n==========================================================")
        print(" [SUCCESS] All 5 required GA102 firmware assets ready in assets/!")
        print("==========================================================")
        return True
    else:
        raise RuntimeError("Asset verification failed after download.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_TARGET, help="Destination directory (default: assets/)")
    parser.add_argument("--cache", type=Path, default=None, help="Cache directory for source downloads")
    parser.add_argument("--keep-cache", action="store_true", help="Preserve downloaded source archives")
    args = parser.parse_args()

    success = acquire_all_assets(args.output, args.cache, args.keep_cache)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()

