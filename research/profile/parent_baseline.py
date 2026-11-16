"""Bounded, privacy-limited PCI observations; never an admission/actuation gate."""
import re

MASK = 0x700
FIELDS = {'role', 'pci_id', 'class_revision', 'segment', 'bus', 'device', 'function',
          'command', 'decode_attributes', 'decode_supported', 'secondary_bus', 'subordinate_bus'}


def require(condition):
    if not condition:
        raise ValueError('Invalid parent observation')


def integer(value, maximum):
    return type(value) is int and 0 <= value <= maximum


def validate(value):
    """Validate the shareable schema, without accepting arbitrary/raw fields."""
    require(isinstance(value, dict) and set(value) == {'state', 'devices'})
    require(value['state'] in ('not_recorded', 'unavailable', 'invalid', 'recorded'))
    devices = value['devices']
    require(isinstance(devices, list))
    if value['state'] != 'recorded':
        require(not devices)
        return
    require(2 <= len(devices) <= 16)
    for index, row in enumerate(devices):
        require(isinstance(row, dict) and set(row) == FIELDS)
        require(row['role'] == ('gpu' if index == 0 else 'bridge'))
        for field in ('pci_id', 'class_revision'):
            require(isinstance(row[field], str) and re.fullmatch('[0-9a-f]{8}', row[field]) is not None)
        require(row['pci_id'] not in ('00000000', 'ffffffff'))
        for field, maximum in (('segment', 0xffff), ('bus', 255), ('device', 31),
                               ('function', 7), ('command', 0xffff)):
            require(integer(row[field], maximum))
        for field in ('decode_attributes', 'decode_supported'):
            require(integer(row[field], MASK) and not row[field] & ~MASK)
    gpu = devices[0]
    require(gpu['pci_id'].endswith('10de') and gpu['class_revision'] == '030000a1')
    require(gpu['command'] == 2 and gpu['bus'] > 0 and gpu['device'] == gpu['function'] == 0)
    require(gpu['decode_attributes'] in (0x200, 0x300) and gpu['decode_supported'] & 0x100)
    require(gpu['secondary_bus'] is None and gpu['subordinate_bus'] is None)
    seen = {gpu['bus']}
    previous = None
    for row in devices[1:]:
        require(row['segment'] == gpu['segment'] and row['bus'] not in seen)
        require(int(row['class_revision'], 16) & 0xffffff00 == 0x06040000 and row['command'] != 0xffff)
        secondary, subordinate = row['secondary_bus'], row['subordinate_bus']
        require(integer(secondary, 255) and integer(subordinate, 255))
        require(0 < secondary <= subordinate and secondary != row['bus'])
        require(secondary <= gpu['bus'] <= subordinate)
        decode = sum(flag for bit, flag in ((1, 0x100), (2, 0x200), (4, 0x400)) if row['command'] & bit)
        require(row['decode_attributes'] == decode)
        if previous:
            require(row['bus'] == previous['secondary_bus'] and subordinate <= previous['subordinate_bus'])
        seen.add(row['bus'])
        previous = row
    require(previous['secondary_bus'] == gpu['bus'])


def parse(text, controllers, primary_configs):
    """Auxiliary records cannot override the primary capture or reveal raw config."""
    lines = [line for line in text.splitlines() if line.lstrip().startswith('parent-baseline')]
    if not lines:
        return {'state': 'not_recorded', 'devices': []}
    invalid = {'state': 'invalid', 'devices': []}
    if len(lines) > 33 or any(len(line) > 1024 for line in lines):
        return invalid
    header = re.fullmatch(r'parent-baseline status=0x([0-9a-f]{16}) available=([01]) parents=0x([0-9a-f]{2})', lines[0])
    if not header:
        return invalid
    status, available, count = (int(v, 16) for v in header.groups())
    if not available:
        return {'state': 'unavailable', 'devices': []} if count == 0 and len(lines) == 1 else invalid
    if status or not 1 <= count <= 15 or len(lines) != 1 + 2 * (count + 1):
        return invalid
    devices, configs = [], []
    for index in range(count + 1):
        device = re.fullmatch(r'parent-baseline-device index=0x([0-9a-f]{2}) segment=0x([0-9a-f]{4}) bus=0x([0-9a-f]{2}) device=0x([0-9a-f]{2}) function=0x([0-9a-f]{2}) attributes=0x([0-9a-f]{16}) supported=0x([0-9a-f]{16})', lines[1 + 2 * index])
        config = re.fullmatch(r'parent-baseline-config index=0x([0-9a-f]{2}) words=((?:[0-9a-f]{8} ){63}[0-9a-f]{8}) ?', lines[2 + 2 * index])
        if not device or not config or int(device[1], 16) != index or int(config[1], 16) != index:
            return invalid
        _, segment, bus, dev, fun, attrs, supported = (int(v, 16) for v in device.groups())
        cfg = [int(word, 16) for word in config[2].split()]
        if supported == 0xffffffffffffffff or ((cfg[3] >> 16) & 0x7f) != (1 if index else 0):
            return invalid
        if index and cfg[6] & 255 != bus:
            return invalid
        configs.append(cfg)
        devices.append(dict(role='bridge' if index else 'gpu', pci_id=f'{cfg[0]:08x}',
            class_revision=f'{cfg[2]:08x}', segment=segment, bus=bus, device=dev, function=fun,
            command=cfg[1] & 0xffff, decode_attributes=attrs & MASK, decode_supported=supported & MASK,
            secondary_bus=(cfg[6] >> 8) & 255 if index else None,
            subordinate_bus=(cfg[6] >> 16) & 255 if index else None))
    value = {'state': 'recorded', 'devices': devices}
    try:
        validate(value)
        gpu, cfg = devices[0], configs[0]
        require(cfg[4] != 0 and not cfg[4] & 0xffffff and cfg[11] not in (0, 0xffffffff))
        primary = re.findall(r'^cfg dwords=.*$', text, re.M)
        expected = 'cfg dwords=' + ' '.join(f'{word:08x}' for word in cfg)
        require(len(primary) == 1 and primary[0] in (expected, expected + ' '))
        require(len(primary_configs) == 1 and primary_configs[0] == cfg[:16])
        nvidia = [row for row in controllers if row['pci_id'].endswith('10de')]
        require(len(nvidia) == 1)
        primary = nvidia[0]
        require(primary['pci_id'] == gpu['pci_id'] and primary['class_revision'] == gpu['class_revision']
                and primary['subsystem_id'] == f'{cfg[11]:08x}')
        require(primary['location'] == {key: gpu[key] for key in ('segment', 'bus', 'device', 'function')})
    except ValueError:
        return invalid
    return value
