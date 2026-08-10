"""GENERATED FILE - DO NOT EDIT.
Source : spec/spcu_regs.yaml (sha256 74a2a23e23212dc9)
Tool   : tools/genregs.py
Edit the YAML and re-run the tool. Hand edits are lost and are a defect."""

REGISTERS = {
    'ID': {
        'offset': 0x00,
        'access': 'RO',
        'priv_write': False,
        'reset': 0x53504355,
        'fields': {
            'IDCODE': {'msb': 31, 'lsb': 0, 'access': 'RO'},
        },
    },
    'CTRL': {
        'offset': 0x04,
        'access': 'RW',
        'priv_write': False,
        'reset': 0x00000000,
        'fields': {
            'TARGET': {'msb': 1, 'lsb': 0, 'access': 'RW'},
            'GO': {'msb': 8, 'lsb': 8, 'access': 'W1P'},
        },
    },
    'STATUS': {
        'offset': 0x08,
        'access': 'RO',
        'priv_write': False,
        'reset': 0x00000100,
        'fields': {
            'CUR_PSTATE': {'msb': 1, 'lsb': 0, 'access': 'RO'},
            'BUSY': {'msb': 4, 'lsb': 4, 'access': 'RO'},
            'DONE': {'msb': 5, 'lsb': 5, 'access': 'RO'},
            'ERROR': {'msb': 6, 'lsb': 6, 'access': 'RO'},
            'PD_ON': {'msb': 8, 'lsb': 8, 'access': 'RO'},
            'VOLT': {'msb': 11, 'lsb': 10, 'access': 'RO'},
            'FREQ': {'msb': 13, 'lsb': 12, 'access': 'RO'},
        },
    },
    'LOCK': {
        'offset': 0x0C,
        'access': 'RW',
        'priv_write': True,
        'reset': 0x00000000,
        'fields': {
            'LOCKED': {'msb': 0, 'lsb': 0, 'access': 'RW'},
        },
    },
    'PRIV_CFG': {
        'offset': 0x10,
        'access': 'RW',
        'priv_write': True,
        'reset': 0x00000001,
        'fields': {
            'REQUIRE_PRIV': {'msb': 0, 'lsb': 0, 'access': 'RW'},
        },
    },
}


def field(regname, fieldname, value):
    """Extract a field from a full register value."""
    f = REGISTERS[regname]['fields'][fieldname]
    return (value >> f['lsb']) & ((1 << (f['msb'] - f['lsb'] + 1)) - 1)


def place(regname, fieldname, value):
    """Position a field value within a register word."""
    f = REGISTERS[regname]['fields'][fieldname]
    return (value & ((1 << (f['msb'] - f['lsb'] + 1)) - 1)) << f['lsb']
