"""Check the rebuilt runtime against packaged libraries and public SDK exports."""
import argparse
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--native', required=True)
parser.add_argument('--runtime', required=True)
parser.add_argument('--app-libs', required=True)
parser.add_argument('--abi', choices=['arm64-v8a', 'x86_64'], required=True)
args = parser.parse_args()
native = Path(args.native)
runtime = Path(args.runtime)
app = Path(args.app_libs) / args.abi
arch = 'aarch64' if args.abi == 'arm64-v8a' else 'x86_64'
nm = str(native / 'llvm/bin/llvm-nm.exe')
elf = str(native / 'llvm/bin/llvm-readelf.exe')
roots = [app, native / ('llvm/lib/' + arch + '-linux-ohos'), native / ('sysroot/usr/lib/' + arch + '-linux-ohos')]

def symbols(path, option):
    text = subprocess.check_output([nm, '-D', option, str(path)]).decode()
    return {parts[-1].split('@')[0] for line in text.splitlines() if (parts := line.split()) and
            (option != '--undefined-only' or parts[-2] == 'U')}

pending = [runtime, app / 'librulecore_cj.so', app / 'libcangjie-std-core.so', app / 'libnative_rulecore.so']
seen = set()
providers = set()
consumers = {}
while pending:
    path = pending.pop()
    if path.name in seen:
        continue
    seen.add(path.name)
    dynamic = subprocess.check_output([elf, '-d', str(path)]).decode()
    needed = re.findall(r'Shared library: \[([^\]]+)\]', dynamic)
    print(path.name, 'needs', ', '.join(needed))
    providers.update(symbols(path, '--defined-only'))
    consumers[path.name] = symbols(path, '--undefined-only')
    if path.name == 'libcangjie-runtime.so':
        if 'libc++.so' in needed or any('St3__h' in symbol for symbol in consumers[path.name]):
            raise SystemExit('System C++ dependency/ABI remains')
    for name in needed:
        found = runtime if name == runtime.name else next((folder / name for folder in roots if (folder / name).is_file()), None)
        if found is None:
            raise SystemExit('Unresolved library: ' + name)
        pending.append(found)
missing = {name: sorted(required - providers) for name, required in consumers.items() if required - providers}
if missing:
    raise SystemExit('Unresolved strong symbols: ' + str(missing))
print('Public SDK dependency/symbol closure verified for', args.abi)
