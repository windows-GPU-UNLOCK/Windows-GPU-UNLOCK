"""Compare two reviewed format-2 compatibility reports; never assess unlock safety."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import stat
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('comparison_parent', Path(__file__).resolve().parent / 'parent_baseline.py')
parent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parent)
LIMIT = 1024 * 1024
COUNTS = ('display_controller_count', 'nvidia_display_count', 'other_display_count',
          'gop_handle_count', 'edid_by_driver_open_count', 'edid_active_open_count')
BASE_FIELDS = COUNTS + ('display_controllers', 'display_controllers_truncated', 'chip_id',
                   'device_memory_size_mib', 'register_snapshot', 'firmware_bindings',
                   'firmware_bindings_truncated')
FIELDS = BASE_FIELDS + ('parent_baseline',)
STATES = {'candidate', 'needs_data', 'outside_scope', 'invalid_data', 'error'}


def require(condition):
    if not condition:
        raise ValueError('Invalid compatibility report')


def integer(value, maximum):
    return type(value) is int and 0 <= value <= maximum


def hex_string(value, length):
    return isinstance(value, str) and re.fullmatch(r'[0-9a-f]{' + str(length) + '}', value) is not None


def validate(report):
    require(isinstance(report, dict))
    require(set(report) <= {'format', 'checker_version', 'envelope_sha256', 'route', 'status',
                           'hardware_tested', 'write_eligible', 'capture_count', 'observations',
                           'checks', 'summary', 'scope', 'limitations', 'next_step'})
    require(type(report['format']) is int and report['format'] == 2)
    require(integer(report['checker_version'], 0xffff) and report['checker_version'] > 0)
    require(report['envelope_sha256'] is None or hex_string(report['envelope_sha256'], 64))
    require(report['route'] == 'automatic_local_profile' and report['status'] in STATES)
    require(report['hardware_tested'] is False and report['write_eligible'] is False)
    require(integer(report['capture_count'], 32))
    require(isinstance(report['checks'], list) and len(report['checks']) <= 100)
    for check in report['checks']:
        require(isinstance(check, dict) and set(check) <= {'state', 'code', 'capture', 'message'})
        require(check['state'] in STATES and isinstance(check['code'], str)
                and re.fullmatch(r'[a-z_]{1,64}', check['code']) is not None)
        if 'capture' in check:
            require(re.fullmatch(r'DIAG[0-9]{2}\.TXT', check['capture']) is not None)
    observations = report['observations']
    require(isinstance(observations, list) and len(observations) <= report['capture_count'])
    seen = set()
    for observation in observations:
        require(isinstance(observation, dict) and type(observation['available']) is bool)
        name = observation['capture']
        require(isinstance(name, str) and re.fullmatch(r'DIAG[0-9]{2}\.TXT', name) is not None and name not in seen)
        seen.add(name)
        if not observation['available']:
            require(set(observation) == {'capture', 'available'})
            continue
        require(set(observation) == {'capture', 'available'} | set(BASE_FIELDS) |
                ({'parent_baseline'} if 'parent_baseline' in observation else set()))
        if 'parent_baseline' in observation:
            parent.validate(observation['parent_baseline'])
        for field in COUNTS:
            require(integer(observation[field], 2097152 if field.startswith('edid_') else 4096))
        require(observation['display_controller_count'] == observation['nvidia_display_count'] + observation['other_display_count'])
        require(observation['edid_by_driver_open_count'] <= observation['edid_active_open_count'])
        require(observation['chip_id'] is None or hex_string(observation['chip_id'], 8))
        require(observation['device_memory_size_mib'] is None or integer(observation['device_memory_size_mib'], 0xffffffff))
        require(observation['register_snapshot'] in {'complete', 'partial', 'not_recorded', 'invalid'})
        controllers = observation['display_controllers']
        require(isinstance(controllers, list) and len(controllers) == min(16, observation['display_controller_count']))
        require(type(observation['display_controllers_truncated']) is bool
                and observation['display_controllers_truncated'] == (observation['display_controller_count'] > 16))
        for controller in controllers:
            require(isinstance(controller, dict) and set(controller) == {'pci_id', 'subsystem_id', 'class_revision', 'location'})
            require(all(hex_string(controller[key], 8) for key in ('pci_id', 'subsystem_id', 'class_revision')))
            location = controller['location']
            if location is not None:
                require(isinstance(location, dict) and set(location) == {'segment', 'bus', 'device', 'function'})
                require(all(integer(location[key], limit) for key, limit in
                            [('segment', 0xffff), ('bus', 255), ('device', 31), ('function', 7)]))
        bindings = observation['firmware_bindings']
        if bindings is None:
            require(observation['firmware_bindings_truncated'] is None)
        else:
            require(isinstance(bindings, list) and len(bindings) <= 16)
            require(type(observation['firmware_bindings_truncated']) is bool)
            require(not observation['firmware_bindings_truncated'] or len(bindings) == 16)
            for binding in bindings:
                require(isinstance(binding, dict) and set(binding) == {'role', 'version', 'image_bytes'})
                require(binding['role'] in {'console_text', 'console_gfx', 'edid', 'nvgop'})
                require(binding['version'] is None or hex_string(binding['version'], 8))
                require(binding['image_bytes'] is None or integer(binding['image_bytes'], 4 * 1024 * 1024))


def read_report(path):
    def unique_keys(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result)
            result[key] = value
        return result

    require(stat.S_ISREG(path.stat().st_mode))
    with path.open('rb') as stream:
        require(stat.S_ISREG(os.fstat(stream.fileno()).st_mode))
        raw = stream.read(LIMIT + 1)
    require(len(raw) <= LIMIT)
    text = raw.decode('utf-16') if raw.startswith((b'\xff\xfe', b'\xfe\xff')) else raw.decode('utf-8-sig')
    report = json.loads(text, object_pairs_hook=unique_keys,
                        parse_constant=lambda _: require(False))
    validate(report)
    return report


def unknown(value):
    if value is None:
        return True
    if isinstance(value, list):
        return any(unknown(item) for item in value)
    if isinstance(value, dict):
        return any(unknown(item) for item in value.values())
    return False


def compare(left, right):
    validate(left)
    validate(right)
    result = {'format': 1, 'status': 'compared', 'hardware_tested': False,
              'write_eligible': False, 'fields': []}
    if (left['checker_version'] != right['checker_version'] or
            left['envelope_sha256'] != right['envelope_sha256'] or
            left['envelope_sha256'] is None):
        result['status'] = 'different_checker_or_envelope'
        return result
    for field in FIELDS:
        sides, unavailable = [], False
        for report in (left, right):
            records = report['observations']
            values = [record.get(field) if record['available'] else None for record in records]
            unavailable |= (not values or len(records) != report['capture_count'] or
                            (field != 'parent_baseline' and any(unknown(v) for v in values)))
            if field == 'display_controllers':
                unavailable |= any(record.get('display_controllers_truncated', False) for record in records)
            if field == 'firmware_bindings':
                unavailable |= any(record.get('firmware_bindings_truncated', False) for record in records)
            if field == 'parent_baseline':
                unavailable |= any(not isinstance(value, dict) or value.get('state') != 'recorded' for value in values)
            # Distinct observations per side: capture numbers/boot counts are not machine identity.
            sides.append([json.loads(value) for value in sorted({json.dumps(v, sort_keys=True) for v in values})])
        state = 'unavailable' if unavailable else 'same' if sides[0] == sides[1] else 'different'
        result['fields'].append({'field': field, 'state': state, 'left': sides[0], 'right': sides[1]})
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('left', type=Path)
    parser.add_argument('right', type=Path)
    parser.add_argument('--json', action='store_true')
    parser.add_argument('--lang', choices=('en', 'ko'), default='en')
    args = parser.parse_args(argv)
    try:
        result = compare(read_report(args.left), read_report(args.right))
    except (OSError, ValueError, KeyError, TypeError, RecursionError):
        result = {'format': 1, 'status': 'invalid_report', 'hardware_tested': False,
                  'write_eligible': False, 'fields': []}
    result['limitations'] = (
        '사용자 제공 보고서의 관측값만 비교합니다. 자료 출처·장비 호환성·언락 안전성을 증명하지 않습니다.'
        if args.lang == 'ko' else
        'Compares user-supplied observations only. Does not verify provenance, hardware compatibility or unlock safety.')
    if args.json:
        print(json.dumps(result, ensure_ascii=True, indent=2))
    else:
        print(result['status'])
        for field in result['fields']:
            if field['state'] != 'same':
                print(f"{field['field']}: {field['state']}")
                print('  left: ' + json.dumps(field['left'], sort_keys=True))
                print('  right: ' + json.dumps(field['right'], sort_keys=True))
        print(result['limitations'])
    return 0 if result['status'] == 'compared' else 2


if __name__ == '__main__':
    sys.exit(main())
