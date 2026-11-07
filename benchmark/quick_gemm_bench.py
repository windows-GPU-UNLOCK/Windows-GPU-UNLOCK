"""Zero-dependency GEMM benchmark for Windows GPU unlock verification.

Uses system CUDA driver (nvcuda.dll) and cuBLAS (cublas64_*.dll) via ctypes.
Runs 4096 GEMM without requiring MSVC, nvcc compiler, or full CUDA Toolkit.
"""

import argparse
import ctypes
import os
from pathlib import Path
import sys
import time


def find_cuda_libraries():
    """Locate nvcuda and cublas libraries on Windows or Linux."""
    script_dir = Path(__file__).resolve().parent
    cuda_lib = None
    cublas_lib = None

    if sys.platform == "win32":
        search_dirs = [
            script_dir,
            script_dir.parent / "tools",
            Path(os.environ.get("CUDA_PATH", "")) / "bin",
            Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32",
        ]
        for d in search_dirs:
            if d.exists():
                try:
                    os.add_dll_directory(str(d))
                except Exception:
                    pass

        try:
            cuda_lib = ctypes.WinDLL("nvcuda.dll")
        except Exception:
            pass

        candidates = [
            "cublas64_12.dll",
            "cublas64_11.dll",
            str(script_dir / "cublas64_11.dll"),
            str(script_dir.parent / "tools" / "cublas64_11.dll"),
        ]
        for c in candidates:
            try:
                cublas_lib = ctypes.WinDLL(c)
                if cublas_lib:
                    break
            except Exception:
                continue
    else:
        for c_name in ("libcuda.so", "libcuda.so.1"):
            try:
                cuda_lib = ctypes.CDLL(c_name)
                break
            except Exception:
                pass
        for cb_name in ("libcublas.so", "libcublas.so.12", "libcublas.so.11"):
            try:
                cublas_lib = ctypes.CDLL(cb_name)
                break
            except Exception:
                pass

    return cuda_lib, cublas_lib


def run_gemm_benchmark(cuda, cublas, device_index=0, matrix_size=4096, runs=10):
    """Run GEMM benchmark on specified GPU device and return TFLOPS."""
    dev = ctypes.c_int()
    if cuda.cuDeviceGet(ctypes.byref(dev), device_index) != 0:
        raise RuntimeError(f"cuDeviceGet failed for index {device_index}")

    name_buf = ctypes.create_string_buffer(256)
    cuda.cuDeviceGetName(name_buf, 256, dev)
    device_name = name_buf.value.decode("utf-8", errors="replace")

    ctx = ctypes.c_void_p()
    if cuda.cuCtxCreate_v2(ctypes.byref(ctx), 0, dev) != 0:
        raise RuntimeError(f"cuCtxCreate failed on {device_name}")

    try:
        handle = ctypes.c_void_p()
        if cublas.cublasCreate_v2(ctypes.byref(handle)) != 0:
            raise RuntimeError(f"cublasCreate failed on {device_name}")

        try:
            cublas.cublasSetMathMode(handle, 1)  # CUBLAS_TENSOR_OP_MATH

            n = matrix_size
            elem_count = n * n
            bytes_f16 = elem_count * 2
            bytes_f32 = elem_count * 4
            flops = 2 * (n ** 3)

            cublas_compute_32f = 68
            cuda_r_16f = 2
            cuda_r_32f = 0
            alpha = ctypes.c_float(1.0)
            beta = ctypes.c_float(0.0)

            d_a = ctypes.c_uint64()
            d_b = ctypes.c_uint64()
            d_c = ctypes.c_uint64()

            cuda.cuMemAlloc_v2(ctypes.byref(d_a), bytes_f16)
            cuda.cuMemAlloc_v2(ctypes.byref(d_b), bytes_f16)
            cuda.cuMemAlloc_v2(ctypes.byref(d_c), bytes_f32)

            try:
                # Warmup
                for _ in range(3):
                    cublas.cublasGemmEx(
                        handle, 0, 0, n, n, n,
                        ctypes.byref(alpha),
                        d_a, cuda_r_16f, n,
                        d_b, cuda_r_16f, n,
                        ctypes.byref(beta),
                        d_c, cuda_r_32f, n,
                        cublas_compute_32f, -1
                    )
                cuda.cuCtxSynchronize()

                # Timed runs
                t0 = time.time()
                for _ in range(runs):
                    cublas.cublasGemmEx(
                        handle, 0, 0, n, n, n,
                        ctypes.byref(alpha),
                        d_a, cuda_r_16f, n,
                        d_b, cuda_r_16f, n,
                        ctypes.byref(beta),
                        d_c, cuda_r_32f, n,
                        cublas_compute_32f, -1
                    )
                cuda.cuCtxSynchronize()
                t1 = time.time()

                avg_sec = (t1 - t0) / runs
                tflops = (flops / avg_sec) / 1e12
                return {
                    "device_index": device_index,
                    "device_name": device_name,
                    "matrix_size": matrix_size,
                    "avg_ms": avg_sec * 1000.0,
                    "tflops": tflops,
                }
            finally:
                cuda.cuMemFree_v2(d_a)
                cuda.cuMemFree_v2(d_b)
                cuda.cuMemFree_v2(d_c)
        finally:
            cublas.cublasDestroy_v2(handle)
    finally:
        cuda.cuCtxDestroy_v2(ctx)


def main():
    parser = argparse.ArgumentParser(description="Zero-dependency GEMM benchmark")
    parser.add_argument("--device", type=int, default=-1, help="Device index (-1 for all)")
    parser.add_argument("--size", type=int, default=4096, help="Matrix dimension N")
    parser.add_argument("--runs", type=int, default=10, help="Benchmark iterations")
    args = parser.parse_args()

    cuda, cublas = find_cuda_libraries()
    if not cuda or not cublas:
        print("[ERROR] Could not load CUDA driver or cuBLAS library.")
        print("        Ensure NVIDIA drivers are installed.")
        return 1

    if cuda.cuInit(0) != 0:
        print("[ERROR] cuInit(0) failed.")
        return 1

    count = ctypes.c_int()
    cuda.cuDeviceGetCount(ctypes.byref(count))
    if count.value < 1:
        print("[ERROR] No NVIDIA devices found.")
        return 1

    devices_to_test = range(count.value) if args.device < 0 else [args.device]

    print(f"Running {args.size}x{args.size} GEMM on {len(devices_to_test)} GPU(s)...")
    for idx in devices_to_test:
        try:
            res = run_gemm_benchmark(cuda, cublas, device_index=idx, matrix_size=args.size, runs=args.runs)
            print(f"GPU {res['device_index']} [{res['device_name']}]: "
                  f"{res['avg_ms']:.2f} ms | {res['tflops']:.2f} TFLOPS")
        except Exception as e:
            print(f"GPU {idx} benchmark failed: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
