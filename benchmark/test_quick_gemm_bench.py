"""Unit tests for quick_gemm_bench.py."""

import unittest
from unittest.mock import MagicMock, patch
import sys
from pathlib import Path

# Add benchmark directory to path
BENCHMARK_DIR = Path(__file__).resolve().parent
if str(BENCHMARK_DIR) not in sys.path:
    sys.path.insert(0, str(BENCHMARK_DIR))

import quick_gemm_bench


class TestQuickGemmBench(unittest.TestCase):

    def test_find_cuda_libraries_returns_tuple(self):
        cuda, cublas = quick_gemm_bench.find_cuda_libraries()
        self.assertIsInstance((cuda, cublas), tuple)

    @patch("quick_gemm_bench.ctypes")
    @patch("quick_gemm_bench.time")
    def test_run_gemm_benchmark_mocked(self, mock_time, mock_ctypes):
        mock_cuda = MagicMock()
        mock_cublas = MagicMock()

        # Set up mock returns
        mock_cuda.cuDeviceGet.return_value = 0
        mock_cuda.cuCtxCreate_v2.return_value = 0
        mock_cublas.cublasCreate_v2.return_value = 0

        # Simulate time duration
        mock_time.time.side_effect = [100.0, 101.0]

        res = quick_gemm_bench.run_gemm_benchmark(
            mock_cuda, mock_cublas, device_index=0, matrix_size=1024, runs=5
        )

        self.assertEqual(res["device_index"], 0)
        self.assertEqual(res["matrix_size"], 1024)
        self.assertGreater(res["tflops"], 0.0)
        mock_cuda.cuMemFree_v2.assert_called()
        mock_cublas.cublasDestroy_v2.assert_called()
        mock_cuda.cuCtxDestroy_v2.assert_called()


if __name__ == "__main__":
    unittest.main()
