#!/usr/bin/env python3
"""Compile the real helper and check shrinking a reused channel map."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile

source = Path(sys.argv[1])
text = source.read_text()
start = text.index('void audioreach_set_default_channel_mapping(')
end = text.index('EXPORT_SYMBOL_GPL(audioreach_set_default_channel_mapping)', start)
helper = text[start:end]
headers = source.parent
defines = []
for name in ['AR_PCM_MAX_NUM_CHANNEL', 'PCM_CHANNEL_FL', 'PCM_CHANNEL_FR',
             'PCM_CHANNEL_LS', 'PCM_CHANNEL_RS']:
    files = ['audioreach.h', 'q6dsp-common.h']
    matches = [match for file in files for match in re.findall(
        rf'^#define\s+{name}\s+(\d+)\b', (headers / file).read_text(), re.M)]
    assert len(matches) == 1, name
    defines.append(f'#define {name} {matches[0]}')
test = '''
int main(void) {
    u8 map[AR_PCM_MAX_NUM_CHANNEL];
    memset(map, 0xa5, sizeof(map));
    audioreach_set_default_channel_mapping(map, 4);
    assert(map[0] == PCM_CHANNEL_FL && map[1] == PCM_CHANNEL_FR);
    assert(map[2] == PCM_CHANNEL_LS && map[3] == PCM_CHANNEL_RS);
    for (int i = 4; i < AR_PCM_MAX_NUM_CHANNEL; i++) assert(map[i] == 0);
    audioreach_set_default_channel_mapping(map, 2);
    assert(map[0] == PCM_CHANNEL_FL && map[1] == PCM_CHANNEL_FR);
    for (int i = 2; i < AR_PCM_MAX_NUM_CHANNEL; i++) assert(map[i] == 0);
    audioreach_set_default_channel_mapping(map, 1);
    assert(map[0] == PCM_CHANNEL_FL);
    for (int i = 1; i < AR_PCM_MAX_NUM_CHANNEL; i++) assert(map[i] == 0);
}
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'test.c'
    path.write_text('#include <assert.h>\n#include <string.h>\ntypedef unsigned char u8;\n'
                    + '\n'.join(defines) + '\n' + helper + test)
    binary = path.with_suffix('')
    subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', str(path),
                    '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('PASS: real default-map helper clears unused channels across 4 -> 2 -> 1')
