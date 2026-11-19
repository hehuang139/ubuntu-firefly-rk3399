#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Check and, if needed, correct the original Firefly-RK3399 DDR3 boot DTB."""
import argparse
import os
from pathlib import Path
import stat
import struct
import tempfile

SELECTOR = 'fcs,suspend-voltage-selector'
CPU = '/i2c@ff3c0000/regulator@40'
GPU = '/i2c@ff3c0000/regulator@41'


def require(condition, message):
    if not condition:
        raise ValueError(message)


class Tree:
    def __init__(self, data):
        self.nodes = {}
        self.data = data
        require(len(data) >= 40, 'truncated DTB header')
        magic, total, start, strings, _, version, _, _, strings_len, struct_len = struct.unpack_from('>10I', data)
        require(magic == 0xd00dfeed and version == 17 and 40 <= total <= len(data), 'invalid DTB header')
        end = start + struct_len
        string_end = strings + strings_len
        require(40 <= start < end <= strings <= string_end <= total, 'invalid DTB block bounds')
        cursor, stack = start, []
        while cursor + 4 <= end:
            token, = struct.unpack_from('>I', data, cursor)
            cursor += 4
            if token == 1:
                stop = data.find(b'\0', cursor, end)
                require(stop >= 0, 'unterminated DT node')
                name = data[cursor:stop].decode('ascii')
                require((not stack and not name and not self.nodes) or
                        (stack and name and '/' not in name), 'invalid DT node name')
                stack.append(name)
                path = '/'.join(stack) or '/'
                require(path not in self.nodes, 'duplicate node ' + path)
                self.nodes[path] = {}
                cursor = (stop + 4) & ~3
            elif token == 2:
                require(stack, 'unbalanced DT node')
                stack.pop()
            elif token == 3:
                require(stack and cursor + 8 <= end, 'unexpected DT property')
                size, offset = struct.unpack_from('>II', data, cursor)
                cursor += 8
                loc = strings + offset
                require(loc < string_end and cursor + size <= end, 'invalid DT property bounds')
                stop = data.find(b'\0', loc, string_end)
                require(stop >= 0, 'unterminated DT property name')
                name = data[loc:stop].decode('ascii')
                props = self.nodes['/'.join(stack) or '/']
                require(name not in props, 'duplicate DT property ' + name)
                props[name] = (cursor, size)
                cursor = (cursor + size + 3) & ~3
            elif token == 4:
                continue
            elif token == 9:
                require(not stack and '/' in self.nodes, 'incomplete DT structure')
                return
            else:
                raise ValueError(f'unexpected DT token {token}')
        raise ValueError('missing DT end marker')

    def prop(self, node, prop):
        try:
            offset, size = self.nodes[node][prop]
        except KeyError:
            raise ValueError(f'missing {node}:{prop}') from None
        return self.data[offset:offset + size]

    def cell(self, node, prop):
        value = self.prop(node, prop)
        require(len(value) == 4, f'{node}:{prop} is not one 32-bit cell')
        return struct.unpack('>I', value)[0]


def corrected(data, allow_old=False):
    tree = Tree(data)
    require(tree.prop('/', 'compatible').split(b'\0')[:2] ==
            [b'firefly,firefly-rk3399', b'rockchip,rk3399'], 'not the original Firefly-RK3399 board')
    for node, address, regulator, name in ((CPU, 0x40, b'silergy,syr827\0', b'vdd_cpu_b\0'),
                                            (GPU, 0x41, b'silergy,syr828\0', b'vdd_gpu\0')):
        require(tree.prop(node, 'compatible') == regulator and tree.cell(node, 'reg') == address
                and tree.prop(node, 'regulator-name') == name, f'unexpected regulator at {node}')
        mem = node + '/regulator-state-mem'
        require(tree.prop(mem, 'regulator-off-in-suspend') == b'' and
                'regulator-on-in-suspend' not in tree.nodes[mem], f'unexpected suspend constraints at {node}')
    for node, prop, regulator in (('/cpus/cpu@100', 'cpu-supply', CPU),
                                  ('/cpus/cpu@101', 'cpu-supply', CPU),
                                  ('/gpu@ff9a0000', 'mali-supply', GPU)):
        require(tree.cell(node, prop) == tree.cell(regulator, 'phandle') != 0, f'unexpected supply for {node}')
    require(tree.cell(GPU, SELECTOR) == 1, 'GPU 0x41 suspend bank must be 1')
    cpu = tree.cell(CPU, SELECTOR)
    require(cpu == 1 or (allow_old and cpu == 0), f'CPU 0x40 suspend bank is {cpu}; expected 1')
    if cpu == 1:
        return data
    offset, _ = tree.nodes[CPU][SELECTOR]
    result = data[:offset] + struct.pack('>I', 1) + data[offset + 4:]
    return corrected(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('check', 'fix'))
    parser.add_argument('path', type=Path)
    parser.add_argument('output', type=Path, nargs='?')
    args = parser.parse_args()
    if (args.mode == 'fix') != (args.output is not None):
        parser.error('fix takes a source and output; check only takes a source')
    try:
        data = args.path.read_bytes()
        result = corrected(data, allow_old=args.mode == 'fix')
        if args.output is None:
            return
        out = args.output
        if not out.is_symlink() and out.is_file() and out.read_bytes() == result:
            return
        with tempfile.NamedTemporaryFile(dir=out.parent, prefix='.dtb-', delete=False) as stage:
            staged = Path(stage.name)
            try:
                stage.write(result)
                os.fchmod(stage.fileno(), stat.S_IMODE(args.path.stat().st_mode) & 0o666)
                stage.flush()
                os.fsync(stage.fileno())
                os.replace(staged, out)
            finally:
                staged.unlink(missing_ok=True)
    except (OSError, ValueError, struct.error) as e:
        parser.exit(1, f'{args.path.name}: {e}\n')


if __name__ == '__main__':
    main()
