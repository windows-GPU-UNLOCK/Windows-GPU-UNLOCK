# SPDX-License-Identifier: GPL-2.0-only
"""Build and run the real splash player against synthetic UEFI and LZ4 data."""
import argparse
import hashlib
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


def frame(color):
    """Two literals, an overlapping match, then the five trailing literals."""
    pixel = struct.pack('<H', color)
    extension = 1920 * 1080 * 2 - 2 - 5 - 4 - 15
    count, remainder = divmod(extension, 255)
    return b'\x2f' + pixel + b'\x02\x00' + b'\xff' * count + bytes([remainder]) + b'\x50' + (pixel * 3)[1:]


def asset():
    frames = [frame(0xf800 if index % 2 == 0 else 0x001f) for index in range(112)]
    offsets = [0]
    for data in frames:
        offsets.append(offsets[-1] + len(data))
    return struct.pack('<8sIII113I', b'GUMATX01', 1920, 1080, 112, *offsets) + b''.join(frames)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--clang', default='clang')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    build = repo / 'research/headless/build'
    build.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='splash-', dir=build) as temporary:
        work = Path(temporary)
        boot = work / 'boot'
        unlock = work / 'unlock'
        contract = boot / 'build/headless'
        contract.mkdir(parents=True)
        unlock.mkdir()
        for name in ('boot-splash.c', 'boot-splash.h', 'test_boot_splash.c'):
            shutil.copyfile(repo / 'internal-boot/boot' / name, boot / name)
        for name in ('sha256.c', 'sha256.h'):
            shutil.copyfile(repo / 'internal-boot/unlock' / name, unlock / name)
        include = repo / 'deps/edk2/MdePkg/Include'
        executable = work / 'test-splash.exe'
        for bad_frame in (None, 0, 10):
            data = bytearray(asset())
            arguments = []
            if bad_frame is not None:
                offset = struct.unpack_from('<I', data, 20 + 4 * bad_frame)[0]
                data[472 + offset] = 0
                arguments = ['--bad-frame', str(bad_frame)]
            fixture = work / 'SPLASH.BIN'
            fixture.write_bytes(data)
            digest = hashlib.sha256(data).hexdigest()
            (contract / 'splash-contract.h').write_text(
                f'#define GU_SPLASH_BYTES {len(data)}U\n#define GU_SPLASH_SHA256 "{digest}"\n', encoding='ascii')
            subprocess.run([
                args.clang, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
                '-D_CRT_SECURE_NO_WARNINGS', '-fshort-wchar',
                '-I', str(include), '-I', str(include / 'X64'),
                str(boot / 'test_boot_splash.c'), str(unlock / 'sha256.c'),
                '-o', str(executable),
            ], check=True)
            subprocess.run([str(executable), str(fixture), *arguments], check=True)


if __name__ == '__main__':
    main()
