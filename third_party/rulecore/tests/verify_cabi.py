"""Execute the actual Cangjie DLL through its public runtime and C ABI."""
import ctypes as c
import json
import os
import sys
from pathlib import Path

sdk = Path(sys.argv[1])
library = Path(sys.argv[2]).resolve()
library_directories = [p for p in [sdk / 'runtime/lib/windows_x86_64_cjnative',
    sdk / 'lib/windows_x86_64_cjnative', sdk / 'tools/lib', library.parent] if p.exists()]
handles = [os.add_dll_directory(str(p)) for p in library_directories]
# Cangjie's own LoadLibrary call uses PATH in addition to Python's DLL directories.
os.environ['PATH'] = os.pathsep.join(map(str, library_directories)) + os.pathsep + os.environ['PATH']
runtime = c.CDLL(str(sdk / 'runtime/lib/windows_x86_64_cjnative/libcangjie-runtime.dll'))

class Heap(c.Structure):
    _fields_ = [('region', c.c_size_t), ('heap', c.c_size_t), ('exemption', c.c_double),
        ('utilization', c.c_double), ('growth', c.c_double), ('rate', c.c_double), ('wait', c.c_size_t)]
class GC(c.Structure):
    _fields_ = [('threshold', c.c_size_t), ('garbage', c.c_double), ('interval', c.c_uint64),
        ('backup', c.c_uint64), ('threads', c.c_int32)]
class Log(c.Structure):
    _fields_ = [('level', c.c_int)]
class Concurrency(c.Structure):
    _fields_ = [('threadStack', c.c_size_t), ('coroutineStack', c.c_size_t), ('processors', c.c_uint32)]
class Config(c.Structure):
    _fields_ = [('heap', Heap), ('gc', GC), ('log', Log), ('concurrency', Concurrency)]

runtime.InitCJRuntime.argtypes = [c.POINTER(Config)]
runtime.InitCJRuntime.restype = c.c_int
runtime.LoadCJLibraryWithInit.argtypes = [c.c_char_p]
runtime.LoadCJLibraryWithInit.restype = c.c_int
runtime.FindCJSymbol.argtypes = [c.c_char_p, c.c_char_p]
runtime.FindCJSymbol.restype = c.c_void_p
runtime.RunCJTask.argtypes = [c.c_void_p, c.c_void_p]
runtime.RunCJTask.restype = c.c_void_p
runtime.GetTaskRet.argtypes = [c.c_void_p, c.POINTER(c.c_void_p)]
runtime.GetTaskRet.restype = c.c_int
runtime.ReleaseHandle.argtypes = [c.c_void_p]
runtime.ReleaseHandle.restype = None
runtime.FiniCJRuntime.restype = c.c_int

config = Config()
config.heap.heap = 192 * 1024
config.log.level = 5
config.concurrency.processors = 2
assert runtime.InitCJRuntime(c.byref(config)) == 0
encoded = str(library).encode()
assert runtime.LoadCJLibraryWithInit(encoded) == 0
tokenize = runtime.FindCJSymbol(encoded, b'rulecore_tokenize')
release = runtime.FindCJSymbol(encoded, b'rulecore_free')
assert tokenize and release

def invoke(function, value):
    task = runtime.RunCJTask(function, value)
    assert task
    result = c.c_void_p()
    try:
        assert runtime.GetTaskRet(task, c.byref(result)) == 0
        return result.value
    finally:
        runtime.ReleaseHandle(task)

def parse(html):
    source = c.create_string_buffer(html.encode('utf-8'))
    pointer = invoke(tokenize, source)
    assert pointer
    try:
        return json.loads(c.string_at(pointer).decode('utf-8'))
    finally:
        invoke(release, pointer)

samples = [
    '<div><a href="/1?q=a&amp;b" TITLE="😀">书😀音 &amp; FM</a></div>',
    '<!--ignore--><!DOCTYPE html><p>one<br/>two</p>',
    '<script>if(a < b){x="<div>"}</script><style>.a>b{}</style><p>ok</p>',
    '<title>A &lt; B</title><textarea><b>literal</b></textarea>',
    'plain < invalid <p data-x=abc data-y="q>z">tail',
    '<SCRIPT>abc</ScRiPt/><p>x</p>',
    '<a empty data-x=foo>中</a>',
]
try:
    for source in samples:
        result = parse(source)
        assert not result['error'], result
        utf16 = source.encode('utf-16-le')
        end = 0
        for token in result['tokens']:
            assert end <= token['start'] < token['end'] <= len(utf16) // 2, token
            if token['type'] == 'text':
                assert utf16[token['start']*2:token['end']*2].decode('utf-16-le') == token['text'], token
            end = token['end']
    first = parse(samples[0])['tokens']
    assert first[1]['attributes'][0]['value'] == '/1?q=a&amp;b'
    assert any(t.get('text') == '书😀音 &amp; FM' for t in first)
    assert len(parse(samples[2])['tokens']) == 9
    assert parse('x' * (4 * 1024 * 1024 + 1))['error']
    assert parse('<b></b>' * 25001)['error']
    assert parse('<a ' + ' '.join(f'x{i}=a' for i in range(257)) + '>')['error']
    if len(sys.argv) > 3:
        Path(sys.argv[3]).write_text(json.dumps([
            {'html': source, 'result': parse(source)} for source in samples
        ], ensure_ascii=False), encoding='utf-8')
    print('Cangjie C ABI: 7 HTML/UTF-16 fixtures and 3 budget checks passed')
finally:
    runtime.FiniCJRuntime()
