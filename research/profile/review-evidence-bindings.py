"""Compare existing reported audit/profile/host-receipt bindings. No code execution."""
import hashlib
import json
from pathlib import Path
import re
import sys


def compare(audit, profile, receipt, profile_bytes):
    if audit.get('Test') != 'existing-profile-evidence-review-v1' or audit.get('HostEvidenceBindingsMatch') is not True:
        raise ValueError('Audit scope/binding assertion missing')
    if receipt.get('Format') != 2 or receipt.get('AllPassed') is not True or receipt.get('HardwareAccess') is not False:
        raise ValueError('Unexpected host receipt scope')
    for key in ['ExistingRepoCodeExecuted', 'HostTestsRerun', 'CaptureFilesChanged', 'HardwareIndependentlyVerified', 'RecoveryVerified', 'WriteEligible']:
        if audit.get(key) is not False:
            raise ValueError('Unexpected audit scope')
    for key in ['HeaderSha256', 'PromSha256', 'ProfileReportSha256']:
        value = audit.get(key)
        if not isinstance(value, str) or not re.fullmatch('[0-9a-f]{64}', value) or receipt.get(key) != value:
            raise ValueError('Hash binding mismatch')
    if hashlib.sha256(profile_bytes).hexdigest() != audit['ProfileReportSha256']:
        raise ValueError('Profile bytes mismatch')
    if profile.get('HeaderSha256') != audit['HeaderSha256'] or profile.get('PromSha256') != audit['PromSha256']:
        raise ValueError('Profile/header/PROM mismatch')
    if audit.get('ProfileName') != profile.get('ProfileName') or audit['ProfileName'] != receipt.get('ProfileName'):
        raise ValueError('Profile identity mismatch')
    inputs = receipt.get('Inputs'); results = receipt.get('Results')
    if not isinstance(inputs, list) or not 1 <= len(inputs) <= 10000 or not isinstance(results, dict) or not 1 <= len(results) <= 256:
        raise ValueError('Receipt bounds')
    seen = set(); rows = []
    for row in inputs:
        path = row.get('Path', ''); digest = row.get('Sha256', '')
        if (not isinstance(path, str) or not re.fullmatch('[A-Za-z0-9_./-]{1,512}', path) or
                path.startswith('/') or '..' in path or path.casefold() in seen or
                not isinstance(digest, str) or not re.fullmatch('[0-9a-f]{64}', digest)):
            raise ValueError('Invalid source row')
        seen.add(path.casefold()); rows.append(path + ' ' + digest + '\n')
    if hashlib.sha256(''.join(rows).encode()).hexdigest() != receipt.get('TreeSha256'):
        raise ValueError('Input tree digest mismatch')
    if any(not isinstance(r, dict) or type(r.get('Exit')) is not int or type(r.get('Expected')) is not int or r['Exit'] != r['Expected'] for r in results.values()):
        raise ValueError('Host outcome mismatch')
    if audit.get('SourceInputCount') != len(inputs) or audit.get('ExpectedHostJobCount') != len(results) or audit.get('SourceTreeSha256') != receipt.get('TreeSha256'):
        raise ValueError('Receipt count/tree mismatch')
    replay = profile.get('Replay', {})
    for a, p in [('TargetPci', 'RtxId'), ('Segment', 'Segment'), ('NoEdidDriver', 'NoEdidDriver'), ('ConsoleAggregate', 'Aggregate'), ('ChildCount', 'ChildCount')]:
        if audit.get(a) != replay.get(p):
            raise ValueError('Replay identity mismatch')
    pins = audit.get('NumericHeaderPins', {})
    for key, base, maximum in [('TargetBus', 16, 255), ('RootPortDevice', 10, 31), ('RootPortFunction', 10, 7), ('Bar0Base', 16, 2**64-1), ('Bar0End', 16, 2**64-1)]:
        v = pins.get(key)
        if not isinstance(v, str) or not re.fullmatch('[0-9a-f]{1,16}', v) or not 0 <= int(v, base) <= maximum:
            raise ValueError('Invalid numeric header pin')
    if int(pins['Bar0Base'], 16) > int(pins['Bar0End'], 16):
        raise ValueError('Reversed BAR bounds')
    return {'test': 'reported-evidence-bindings-v1', 'status': 'consistent',
            'header_sha256': audit['HeaderSha256'], 'profile_report_sha256': audit['ProfileReportSha256'],
            'source_input_count': len(inputs), 'host_job_count': len(results),
            'original_source_independently_read': False, 'hardware_independently_verified': False,
            'profile_admitted': False, 'write_eligible': False}


def main():
    root = Path(sys.argv[1]); data = []
    for name in ['profile-review.json', 'profile.json', 'host-test-receipt-Format2.json']:
        path = root / name
        if not path.is_file() or path.is_symlink() or path.stat().st_size > 2 * 1024 * 1024:
            raise ValueError('Input bounds')
        data.append(path.read_bytes())
    print(json.dumps(compare(*(json.loads(b.decode('utf-8-sig')) for b in data), data[1])))


if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('Reported evidence bindings stopped; preserve files. No hardware action requested.', file=sys.stderr)
        sys.exit(1)
