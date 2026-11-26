"""Prerequisites for tools/usb-stick on Windows, without WSL. GPL-2.0-only.
Vibecoded with love by Claude.

  llvm      --dest DIR [--cache DIR] [--archive FILE]
            Fetch the official clang+llvm 20.1.8 Windows tarball (SHA-256 pinned) and
            extract only bin/clang.exe, bin/lld-link.exe and lib/clang/20/include.
  firmware  --repo REPO --out DIR [--cache DIR]
            Generate the five firmware assets with the pinned upstream generator
            (Zagitta/gpu-unlock 0ebdb1c), then check them against
            internal-boot/unlock/assets.json. nvidia-utils 610.43.03-1 comes from the
            pinned CachyOS v3 URL, or from the official Arch archive if that URL no longer
            serves the package. Either package is pinned by SHA-256, and the generated files
            must still match every upstream content pin.
  diff      --repo REPO --captures DIR
            Explain why probe captures disagree (which profile value / PCI config dword).

Needs Python 3.14+ (tarfile reads .tar.zst natively). Run with -I. Downloads go only to
the cache directory; nothing is installed or executed from them except the three
hash-pinned upstream generator files, which are imported as Python modules.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path, PurePosixPath

if sys.version_info < (3, 14):
    sys.exit("prereqs.py needs Python 3.14 or newer (for .tar.zst support); run it with py -3.14 -I")

USER_AGENT = "gpu-unlock-usb-stick/1"

LLVM_VERSION = "20.1.8"
LLVM_NAME = "clang+llvm-20.1.8-x86_64-pc-windows-msvc.tar.xz"
LLVM_URL = "https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.8/" + LLVM_NAME
LLVM_SHA256 = "f229769f11d6a6edc8ada599c0cda964b7dee6ab1a08c6cf9dd7f513e85b107f"
LLVM_PREFIX = "clang+llvm-20.1.8-x86_64-pc-windows-msvc/"
LLVM_FILES = ("bin/clang.exe", "bin/lld-link.exe")
LLVM_DIRS = ("lib/clang/20/include/",)

UPSTREAM = "https://raw.githubusercontent.com/Zagitta/gpu-unlock/0ebdb1c6308b6a2072be5bf04513472942541956/firmware/"
# Git blob content at the pinned commit (LF line endings, as raw.githubusercontent.com serves it).
UPSTREAM_FILES = {
    "generate_v67.py": "4b41e5199c6b9968d134c43a5a42d8127d094eebfe9dca78204be4d7c8237fd0",
    "extract_boot_assets.py": "7acc5f488cd35700c499bc942a07e7d0d9b0822b1e2ad040cd34bacf99fa5986",
    "artifacts-610.43.03.json": "766be4acb90a9ce2448adc3eb4cead81ea142e96b614f30bde1600b74fe5a4bc",
}
NV_SOURCE_ROOT = "NVIDIA-kernel-module-source-610.43.03"
NV_GENERATED = (
    "src/nvidia/generated/g_bindata_kgspGetBinArchiveBooterLoadUcode_GA102.c",
    "src/nvidia/generated/g_bindata_kgspGetBinArchiveGspRmBoot_GA102.c",
)
ARCH_UTILS = {
    "filename": "nvidia-utils-610.43.03-1-x86_64.pkg.tar.zst",
    "url": "https://archive.archlinux.org/packages/n/nvidia-utils/nvidia-utils-610.43.03-1-x86_64.pkg.tar.zst",
    "sha256": "c3367ff68632ac7daf6ca50ef7cbdd1cb5d09f7fe0b26125b312c73e52a34cf4",
}


def say(text: str) -> None:
    print(text, flush=True)


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download(url: str, destination: Path, expected: str, limit: int = 1 << 30) -> bool:
    """Download to destination if its SHA-256 is not already `expected`. False on mismatch."""
    if destination.exists() and not destination.is_symlink() and sha256(destination) == expected:
        say(f"  cached  {destination.name}")
        return True
    if not url.startswith("https://"):
        raise ValueError("downloads require HTTPS")
    destination.parent.mkdir(parents=True, exist_ok=True)
    say(f"  fetch   {url}")
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    temporary = None
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            if not response.url.startswith("https://"):
                raise ValueError("refusing a non-HTTPS redirect")
            with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=".download-", delete=False) as out:
                temporary = Path(out.name)
                total, mark = 0, 0
                while block := response.read(1 << 20):
                    total += len(block)
                    if total > limit:
                        raise ValueError("download exceeds its size limit")
                    out.write(block)
                    if total - mark >= 100 << 20:
                        mark = total
                        say(f"          {total >> 20} MiB")
        actual = sha256(temporary)
        if actual != expected:
            say(f"  SHA-256 mismatch for {destination.name}: got {actual} ({total} bytes); not used")
            return False
        temporary.replace(destination)
        temporary = None
        say(f"  ok      {destination.name} ({total >> 20} MiB)")
        return True
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def safe_relative(name: str, prefix: str) -> PurePosixPath | None:
    if not name.startswith(prefix):
        return None
    relative = PurePosixPath(name[len(prefix):])
    if relative.is_absolute() or ".." in relative.parts or not relative.parts:
        raise ValueError(f"unsafe archive member: {name}")
    return relative


# ---------------------------------------------------------------- llvm
def cmd_llvm(args: argparse.Namespace) -> int:
    dest = args.dest.resolve()
    clang = dest / "bin" / "clang.exe"
    if clang.exists() and (dest / "bin" / "lld-link.exe").exists():
        version = subprocess.run([str(clang), "--version"], capture_output=True, text=True).stdout
        if f"clang version {LLVM_VERSION}" in version:
            say(f"LLVM {LLVM_VERSION} already present in {dest}")
            return 0
        sys.exit(f"{dest} holds a different clang; choose an empty --dest")
    if args.archive:
        archive = args.archive.resolve()
        if sha256(archive) != LLVM_SHA256:
            sys.exit(f"{archive} is not the pinned {LLVM_NAME}")
    else:
        archive = args.cache.resolve() / LLVM_NAME
        say(f"Downloading LLVM {LLVM_VERSION} (896 MiB, SHA-256 pinned)")
        if not download(LLVM_URL, archive, LLVM_SHA256, limit=1 << 31):
            sys.exit("LLVM download did not match its pinned SHA-256")
    say(f"Extracting clang, lld-link and clang headers to {dest} (reads the whole archive, a few minutes)")
    wanted, count = set(LLVM_FILES), 0
    with tarfile.open(archive, mode="r|xz") as tar:
        for member in tar:
            relative = safe_relative(member.name, LLVM_PREFIX)
            if relative is None:
                continue
            text = relative.as_posix()
            if text not in wanted and not any(text.startswith(d) for d in LLVM_DIRS):
                continue
            if member.isdir():
                continue
            if not member.isfile():
                raise ValueError(f"unexpected link in LLVM archive: {member.name}")
            target = dest.joinpath(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(member) as source, target.open("wb") as out:
                shutil.copyfileobj(source, out, 1 << 20)
            wanted.discard(text)
            count += 1
    if wanted:
        sys.exit(f"LLVM archive lacked: {sorted(wanted)}")
    version = subprocess.run([str(clang), "--version"], capture_output=True, text=True).stdout
    if f"clang version {LLVM_VERSION}" not in version:
        sys.exit("extracted clang does not report the expected version")
    say(f"LLVM {LLVM_VERSION}: {count} files in {dest}")
    return 0


# ---------------------------------------------------------------- firmware
def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check_assets(repo: Path, out: Path) -> list[str]:
    problems = []
    for asset in json.loads((repo / "internal-boot/unlock/assets.json").read_text(encoding="utf-8-sig")):
        path = out / asset["Name"]
        if not path.is_file():
            problems.append(f"missing {asset['Name']}")
        elif path.stat().st_size != asset["Bytes"] or sha256(path) != asset["Sha256"].lower():
            problems.append(f"wrong {asset['Name']}")
    return problems


def cmd_firmware(args: argparse.Namespace) -> int:
    repo, out, cache = args.repo.resolve(), args.out.resolve(), args.cache.resolve()
    if not check_assets(repo, out):
        say(f"All five firmware assets in {out} already match assets.json")
        return 0
    upstream = cache / "upstream-0ebdb1c"
    say("Upstream generator (Zagitta/gpu-unlock 0ebdb1c, files SHA-256 pinned)")
    for name, digest in UPSTREAM_FILES.items():
        if not download(UPSTREAM + name, upstream / name, digest, limit=1 << 20):
            sys.exit(f"upstream file {name} did not match its pin")
    manifest = json.loads((upstream / "artifacts-610.43.03.json").read_text())
    source, _reference, package = manifest["source_artifacts"]

    say("NVIDIA open kernel module source 610.43.03 (26 MiB)")
    nv_archive = cache / source["filename"]
    if not download(source["url"], nv_archive, source["sha256"]):
        sys.exit("NVIDIA source archive did not match its pin")

    say("nvidia-utils 610.43.03-1 (about 300 MiB)")
    utils = cache / package["filename"]
    package_sha = package["sha256"]
    if not download(package["url"], utils, package_sha):
        say("  the pinned CachyOS package is not available; using the official Arch build of the same release")
        utils = cache / ARCH_UTILS["filename"]
        package_sha = ARCH_UTILS["sha256"]
        if not download(ARCH_UTILS["url"], utils, package_sha):
            sys.exit("no nvidia-utils 610.43.03-1 package matched a pinned SHA-256")

    with tempfile.TemporaryDirectory(prefix="gpu-unlock-fw-") as scratch:
        root = Path(scratch) / NV_SOURCE_ROOT
        wanted = {f"{NV_SOURCE_ROOT}/{name}" for name in NV_GENERATED}
        with tarfile.open(nv_archive, mode="r|xz") as tar:
            for member in tar:
                if member.name in wanted and member.isfile():
                    target = Path(scratch) / Path(*PurePosixPath(member.name).parts)
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with tar.extractfile(member) as stream:
                        target.write_bytes(stream.read())
                    wanted.discard(member.name)
        if wanted:
            sys.exit(f"NVIDIA source archive lacked: {sorted(wanted)}")

        gen = load_module(upstream / "generate_v67.py", "generate_v67")
        ext = load_module(upstream / "extract_boot_assets.py", "extract_boot_assets")

        def extract_member(path: Path, name: str) -> bytes:
            with tarfile.open(path, mode="r|zst") as archive:
                return gen.read_member(archive, name)

        gen.extract_member = extract_member          # native zstd instead of an external zstd.exe
        gen.PACKAGE_SHA256 = package_sha              # CachyOS pin, or the Arch pin above
        out.mkdir(parents=True, exist_ok=True)
        saved = sys.argv
        try:
            sys.argv = ["generate_v67.py", str(utils), str(out)]
            if gen.main() != 0:
                sys.exit("generate_v67 failed")
        finally:
            sys.argv = saved
        ext.extract_assets(root, out)

    problems = check_assets(repo, out)
    if problems:
        sys.exit("generated assets do not match assets.json: " + ", ".join(problems))
    say(f"All five firmware assets generated in {out} and match assets.json (personal use only; never share them)")
    return 0


# ---------------------------------------------------------------- diff
def pcie_labels(words: list[str]) -> dict[int, str]:
    config = [int(w, 16) for w in words]

    def byte(offset: int) -> int:
        return (config[offset // 4] >> (8 * (offset % 4))) & 0xFF

    labels, pointer, seen = {}, byte(0x34), 0
    while pointer and seen < 48:
        seen += 1
        if byte(pointer) == 0x10:
            labels.update({pointer + 0x10: "PCIe Link Control / Link Status (link training state)",
                           pointer + 0x30: "PCIe Link Control 2 / Link Status 2 (link equalization status)"})
        pointer = byte(pointer + 1)
    return labels


def cmd_diff(args: argparse.Namespace) -> int:
    profile_dir = args.repo.resolve() / "research" / "profile"
    mp = load_module(profile_dir / "make-profile.py", "make_profile")
    envelope = json.loads((profile_dir / "proven.json").read_text(encoding="utf-8"))
    diags = sorted(args.captures.glob("DIAG[0-9][0-9].TXT"))
    if len(diags) < 2:
        say("Fewer than two captures; nothing to compare.")
        return 0
    results = []
    for diag in diags:
        try:
            results.append((diag.name, mp.analyze(diag, None, envelope)))
        except mp.Refused as error:
            say(f"{diag.name}: refused by the generator: {error}")
    if len(results) < 2:
        return 1
    latest_name, latest = results[-1]
    labels = pcie_labels(latest["config"])
    differences = 0
    for name, other in results[:-1]:
        for key in ("defines", "igpu_id", "no_edid_driver", "child_paths"):
            if other[key] != latest[key]:
                differences += 1
                say(f"{name} vs {latest_name}: {key} differs")
        for index, (a, b) in enumerate(zip(other["config"], latest["config"])):
            if a != b:
                differences += 1
                offset = index * 4
                say(f"{name} vs {latest_name}: PCI config 0x{offset:02x}: {a} -> {b}  {labels.get(offset, '')}")
    if not differences:
        say("All captures agree on the values the generator compares.")
    elif any("Link Status" in label for label in labels.values()):
        say("Link status bits are set by PCIe link training. A capture taken on a warm reset (for example right after\n"
            "saving BIOS settings) can differ from cold boots. Archive these captures (make-stick.ps1 -ArchiveCaptures)\n"
            "and take two fresh ones, each after a full shutdown. Never edit captures or the generator to make them agree.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("llvm")
    p.add_argument("--dest", type=Path, required=True)
    p.add_argument("--cache", type=Path, default=Path.cwd() / "downloads")
    p.add_argument("--archive", type=Path)
    p = sub.add_parser("firmware")
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--cache", type=Path, default=Path.cwd() / "downloads")
    p = sub.add_parser("diff")
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--captures", type=Path, required=True)
    args = parser.parse_args()
    try:
        return {"llvm": cmd_llvm, "firmware": cmd_firmware, "diff": cmd_diff}[args.command](args)
    except (OSError, ValueError, tarfile.TarError) as error:
        say(f"error: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
