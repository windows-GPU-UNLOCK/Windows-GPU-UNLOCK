"""Synthetic offline evidence tests. No CUDA, NVIDIA tools or EFI execution."""

import contextlib
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest

from compare_results import LEGACY_NAMES, NAMES, compare, load_run, main


def write_json(path, value):
    # Windows PowerShell 5.1 Set-Content -Encoding utf8 emits a BOM.
    path.write_text(json.dumps(value), encoding='utf-8-sig')


def seal(directory):
    names = ['comparison-context.json', 'trial-1.json', 'trial-2.json', 'trial-3.json']
    write_json(directory / 'comparison-complete.json', {
        'schema_version': 1, 'files': [
            {'Path': name, 'SHA256': hashlib.sha256((directory / name).read_bytes()).hexdigest()}
            for name in names]})


def fixture(directory, ratios=None, gpu='NVIDIA GeForce RTX 3090', card='3090',
            four_modes=False, bus='01'):
    names = NAMES if four_modes else LEGACY_NAMES
    ratios = (1,) * len(names) if ratios is None else ratios
    assert len(ratios) == len(names), 'Fixture must provide every benchmark mode'
    directory.mkdir()
    context = {
        'schema_version': 1,
        'artifacts': [{'Path': f'bin\\compute-benchmark-{card}.exe', 'SHA256': 'a' * 64},
                      {'Path': r'bin\cublas64_12.dll', 'SHA256': 'b' * 64}],
        'runtime': {'cuda_runtime': 12060, 'cublas_major': 12, 'cublas_minor': 6,
                    'cublas_patch': 0, 'gpu_workload_run': False},
        'gpu_settings': [gpu, f'00000000:{bus}:00.0',
                         '617.14', '350.00', '2100', '9751']}
    write_json(directory / 'comparison-context.json', context)
    if four_modes:
        context['schema_version'] = 2
        context['benchmark_names'] = list(NAMES)
        context['runtime'].update(benchmark_protocol=2, tf32_allowed=True)
        write_json(directory / 'comparison-context.json', context)
    for trial_index in range(1, 4):
        trial = {'gpu': gpu, 'pci': f'0000:{bus}:00.0',
                 'compute_capability': '8.6', 'cuda_runtime': 12060,
                 'cuda_driver_api': 13000, 'cublas': 120600, 'benchmarks': []}
        if four_modes:
            trial.update(benchmark_protocol=2, tf32_allowed=True)
        for name, base, ratio in zip(names, (20000, 60000, 62000, 30000), ratios):
            gflops = base * ratio * (1 + (trial_index - 2) * 0.01)
            ms = 2 * 4096 ** 3 / (gflops * 1e6)
            trial['benchmarks'].append({
                'name': name, 'n': 4096, 'samples': 30, 'warmup_seconds': 2,
                'reference_checked': True, 'median_ms': ms,
                'min_ms': ms * 0.95, 'max_ms': ms * 1.05, 'gflops': gflops})
        write_json(directory / f'trial-{trial_index}.json', trial)
    seal(directory)


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.before, self.after = root / 'before', root / 'after'
        fixture(self.before)
        fixture(self.after, (1.01, 1.65, 1.65))

    def compare(self):
        return compare(self.before, self.after, same_machine_confirmed=True)

    def mutate(self, name, operation):
        path = self.after / name
        value = json.loads(path.read_text(encoding='utf-8-sig'))
        operation(value)
        write_json(path, value)
        seal(self.after)

    def test_same_machine_medians_and_fp32_control(self):
        result = self.compare()
        self.assertAlmostEqual(result['benchmarks'][1]['ratio'], 1.65)
        self.assertAlmostEqual(result['fp32_control_change_percent'], 1)
        self.assertEqual(len(result['benchmarks'][0]['before_trials_tflops']), 3)

    def test_legacy_three_mode_reader_stays_supported(self):
        _, _, values = load_run(self.before)
        self.assertEqual(tuple(values), LEGACY_NAMES)
        self.assertEqual(len(self.compare()['benchmarks']), 3)

    def test_four_modes_for_every_supported_card(self):
        for card, gpu in [('3090', 'NVIDIA GeForce RTX 3090'),
                          ('3090ti', 'NVIDIA GeForce RTX 3090 Ti'),
                          ('3070ti', 'NVIDIA GeForce RTX 3070 Ti')]:
            with self.subTest(card=card):
                before = Path(self.temp.name) / f'new-{card}-before'
                after = Path(self.temp.name) / f'new-{card}-after'
                fixture(before, gpu=gpu, card=card, four_modes=True)
                fixture(after, (1, 1.8, 1.9, 2), gpu=gpu, card=card, four_modes=True)
                result = compare(before, after, same_machine_confirmed=True)
                self.assertEqual(tuple(b['name'] for b in result['benchmarks']), NAMES)
                self.assertAlmostEqual(result['benchmarks'][3]['ratio'], 2)
                self.assertEqual(result['fp32_control_change_percent'], 0)

    def test_legacy_and_four_mode_pair_refused(self):
        after = Path(self.temp.name) / 'four'
        fixture(after, four_modes=True)
        with self.assertRaisesRegex(ValueError, 'protocol'):
            compare(self.before, after, same_machine_confirmed=True)

    def test_four_mode_missing_duplicate_and_mixed_trials_refused(self):
        after = Path(self.temp.name) / 'four'
        fixture(after, four_modes=True)
        path = after / 'trial-2.json'
        original = path.read_bytes()
        for case in ('missing', 'duplicate', 'unknown', 'legacy-trial'):
            with self.subTest(case=case):
                trial = json.loads(original.decode('utf-8-sig'))
                if case == 'missing':
                    trial['benchmarks'].pop()
                elif case == 'duplicate':
                    trial['benchmarks'][-1] = trial['benchmarks'][0]
                elif case == 'unknown':
                    trial['benchmarks'][-1]['name'] = 'tf32'
                else:
                    trial.pop('benchmark_protocol')
                    trial.pop('tf32_allowed')
                    trial['benchmarks'].pop()
                write_json(path, trial)
                seal(after)
                with self.assertRaises(ValueError):
                    load_run(after)
        path.write_bytes(original)
        seal(after)
        load_run(after)

    def test_four_mode_strict_protocol_and_environment_flags(self):
        after = Path(self.temp.name) / 'four'
        fixture(after, four_modes=True)
        for filename in ('comparison-context.json', 'trial-1.json'):
            path = after / filename
            original = path.read_bytes()
            for key, values in [('benchmark_protocol', [None, True, '2', 1]),
                                ('tf32_allowed', [None, False, 'true', 1])]:
                for value in values:
                    with self.subTest(file=filename, key=key, value=value):
                        record = json.loads(original.decode('utf-8-sig'))
                        target = record['runtime'] if filename.startswith('comparison') else record
                        if value is None:
                            target.pop(key)
                        else:
                            target[key] = value
                        write_json(path, record)
                        seal(after)
                        with self.assertRaises(ValueError):
                            load_run(after)
            path.write_bytes(original)
            seal(after)
        load_run(after)

    def test_four_mode_context_names_required(self):
        after = Path(self.temp.name) / 'four'
        fixture(after, four_modes=True)
        path = after / 'comparison-context.json'
        context = json.loads(path.read_text(encoding='utf-8-sig'))
        context['benchmark_names'] = list(LEGACY_NAMES)
        write_json(path, context)
        seal(after)
        with self.assertRaisesRegex(ValueError, 'four-mode'):
            load_run(after)

    def test_new_runtime_cannot_masquerade_as_legacy(self):
        self.mutate('comparison-context.json',
                    lambda c: c['runtime'].update(benchmark_protocol=2, tf32_allowed=True))
        with self.assertRaisesRegex(ValueError, 'legacy'):
            self.compare()

    def test_each_supported_card_uses_its_own_executable(self):
        for card, gpu in [('3090', 'NVIDIA GeForce RTX 3090'),
                          ('3090ti', 'NVIDIA GeForce RTX 3090 Ti'),
                          ('3070ti', 'NVIDIA GeForce RTX 3070 Ti')]:
            with self.subTest(card=card):
                before = Path(self.temp.name) / f'{card}-before'
                after = Path(self.temp.name) / f'{card}-after'
                fixture(before, gpu=gpu, card=card)
                fixture(after, (1, 1.5, 1.5), gpu=gpu, card=card)
                result = compare(before, after, same_machine_confirmed=True)
                self.assertAlmostEqual(result['benchmarks'][1]['ratio'], 1.5)

    def test_different_gpu_models_cannot_be_compared(self):
        after = Path(self.temp.name) / 'other-card'
        fixture(after, gpu='NVIDIA GeForce RTX 3090 Ti', card='3090ti')
        with self.assertRaisesRegex(ValueError, 'differ'):
            compare(self.before, after, same_machine_confirmed=True)

    def test_gpu_and_executable_mismatch_is_refused(self):
        self.mutate('comparison-context.json',
                    lambda c: c['gpu_settings'].__setitem__(0, 'NVIDIA GeForce RTX 3090 Ti'))
        with self.assertRaisesRegex(ValueError, 'selected benchmark executable'):
            self.compare()

    def test_unknown_gpu_model_is_refused(self):
        self.mutate('comparison-context.json',
                    lambda c: c['gpu_settings'].__setitem__(0, 'NVIDIA GeForce RTX 4090'))
        with self.assertRaisesRegex(ValueError, 'Unsupported benchmark GPU'):
            self.compare()

    def test_confirmation_required(self):
        with self.assertRaisesRegex(ValueError, 'Confirm'):
            compare(self.before, self.after)

    def test_same_directory_refused(self):
        with self.assertRaisesRegex(ValueError, 'distinct'):
            compare(self.before, self.before, same_machine_confirmed=True)

    def test_changed_context_refused(self):
        for section, key, replacement in [
            ('gpu_settings', 2, 'different-driver'),
            ('gpu_settings', 3, '300.00'),
            ('gpu_settings', 4, '2000'),
            ('runtime', 'cublas_patch', 1)]:
            with self.subTest(section=section, key=key):
                path = self.after / 'comparison-context.json'
                original = path.read_bytes()
                self.mutate(path.name, lambda c: c[section].__setitem__(key, replacement))
                with self.assertRaises(ValueError):
                    self.compare()
                path.write_bytes(original)
                seal(self.after)

    def test_changed_executable_refused(self):
        self.mutate('comparison-context.json',
                    lambda c: c['artifacts'][0].__setitem__('SHA256', 'c' * 64))
        with self.assertRaisesRegex(ValueError, 'Build'):
            self.compare()

    def test_unavailable_power_refused(self):
        self.mutate('comparison-context.json',
                    lambda c: c['gpu_settings'].__setitem__(3, '[N/A]'))
        with self.assertRaisesRegex(ValueError, 'must be available'):
            self.compare()

    def test_artifact_order_and_hash_case_are_not_conditions(self):
        def reorder(context):
            context['artifacts'].reverse()
            for artifact in context['artifacts']:
                artifact['SHA256'] = artifact['SHA256'].upper()
        self.mutate('comparison-context.json', reorder)
        self.compare()

    def test_artifact_ambiguity_refused(self):
        self.mutate('comparison-context.json',
                    lambda c: c['artifacts'].append(dict(c['artifacts'][0])))
        with self.assertRaisesRegex(ValueError, 'Duplicate artifact'):
            self.compare()

    def test_missing_cublas_refused(self):
        self.mutate('comparison-context.json', lambda c: c['artifacts'].pop())
        with self.assertRaisesRegex(ValueError, 'cuBLAS'):
            self.compare()

    def test_invalid_measurements_refused(self):
        for key, value in [('gflops', float('nan')), ('median_ms', float('inf')),
                           ('gflops', 0), ('reference_checked', False),
                           ('samples', 5), ('n', 8192), ('warmup_seconds', True),
                           ('gflops', 1), ('min_ms', 10000)]:
            with self.subTest(key=key, value=value):
                path = self.after / 'trial-1.json'
                original = path.read_bytes()
                self.mutate(path.name,
                            lambda t: t['benchmarks'][0].__setitem__(key, value))
                with self.assertRaises(ValueError):
                    self.compare()
                path.write_bytes(original)
                seal(self.after)

    def test_duplicate_benchmark_refused(self):
        self.mutate('trial-1.json', lambda t: t['benchmarks'].__setitem__(1, t['benchmarks'][0]))
        with self.assertRaisesRegex(ValueError, 'duplicate benchmark'):
            self.compare()

    def test_non_01_bus_runs_compare(self):
        root = Path(self.temp.name)
        fixture(root / 'bus2-before', four_modes=True, bus='02')
        fixture(root / 'bus2-after', (1, 1.8, 1.8, 1.8), four_modes=True, bus='02')
        result = compare(root / 'bus2-before', root / 'bus2-after', same_machine_confirmed=True)
        self.assertAlmostEqual(result['benchmarks'][1]['ratio'], 1.8)

    def test_bus_change_between_runs_refused(self):
        root = Path(self.temp.name)
        fixture(root / 'bus2-after', (1.01, 1.65, 1.65), bus='02')
        with self.assertRaisesRegex(ValueError, 'GPU settings differ'):
            compare(self.before, root / 'bus2-after', same_machine_confirmed=True)

    def test_trial_pci_must_match_recorded_bus(self):
        self.mutate('trial-2.json', lambda t: t.__setitem__('pci', '0000:02:00.0'))
        with self.assertRaisesRegex(ValueError, 'changed between trials'):
            self.compare()

    def test_trial_metadata_change_refused(self):
        self.mutate('trial-2.json', lambda t: t.__setitem__('cuda_driver_api', 12000))
        with self.assertRaisesRegex(ValueError, 'changed between trials'):
            self.compare()

    def test_missing_extra_and_partial_trials_refused(self):
        (self.after / 'trial-4.json').write_text('{}', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'exactly'):
            self.compare()
        (self.after / 'trial-4.json').unlink()
        (self.after / 'trial-3.json').unlink()
        with self.assertRaises(OSError):
            self.compare()

    def test_partial_run_without_completion_refused(self):
        (self.after / 'comparison-complete.json').unlink()
        with self.assertRaises(OSError):
            self.compare()

    def test_post_completion_edit_refused(self):
        path = self.after / 'trial-1.json'
        path.write_bytes(path.read_bytes() + b' ')
        with self.assertRaisesRegex(ValueError, 'changed after run completion'):
            self.compare()

    def test_cli_refusal_has_no_result_on_stdout(self):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            status = main([str(self.before), str(self.after)])
        self.assertEqual(status, 2)
        self.assertEqual(out.getvalue(), '')
        self.assertIn('Comparison refused', err.getvalue())

    def test_cli_success_is_json(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = main([str(self.before), str(self.after), '--same-machine-confirmed'])
        self.assertEqual(status, 0)
        self.assertEqual(len(json.loads(out.getvalue())['benchmarks']), 3)


if __name__ == '__main__':
    unittest.main()
