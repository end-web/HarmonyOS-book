"""Adapt the pinned Cangjie runtime build to the public HarmonyOS application NDK.

Only build paths/link names and the ROM-only loader probe change. Generated
upstream sources remain under build/; this file is the reproducible adaptation.
"""
import argparse
from pathlib import Path
import subprocess

COMMIT = '52f9e08f985ba42e23581e725e1b11f956f941d6'
parser = argparse.ArgumentParser()
parser.add_argument('--source', required=True)
parser.add_argument('--native', required=True)
args = parser.parse_args()
root = Path(args.source).resolve()
native = Path(args.native).resolve().as_posix()
head = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD']).decode().strip()
if head != COMMIT:
    raise SystemExit('Expected Cangjie v1.2.0 commit ' + COMMIT)

files = ['runtime/config.cmake', 'runtime/build/cmake/toolchain/ohos_aarch64_cangjie.cmake',
         'runtime/build/cmake/toolchain/ohos_x86_64_cangjie.cmake', 'runtime/CMakeLists.txt',
         'runtime/src/LoaderManager.cpp', 'runtime/src/CJThread/src/CMakeLists.txt']
for relative in files:
    content = subprocess.check_output(['git', '-C', str(root), 'show', COMMIT + ':' + relative]).decode('utf-8')
    for prefix in ['${OHOS_ROOT}', '$ENV{OHOS_ROOT}']:
        content = content.replace(prefix + '/prebuilts/clang/ohos/${cmake_host_system_name}-${cmake_host_system_processor}/llvm', native + '/llvm')
        content = content.replace(prefix + '/out/sdk/obj/third_party/musl/sysroot', native + '/sysroot')
        content = content.replace(prefix + '/prebuilts/ohos-sdk/linux/11/native/sysroot', native + '/sysroot')
    for exe in ['clang', 'clang++', 'llvm-ranlib', 'llvm-ar']:
        content = content.replace('/bin/' + exe + '"', '/bin/' + exe + '.exe"')
    if relative == 'runtime/config.cmake':
        content = content.replace('set(DOPRA_LIBS ${OUTPUT_TEMP_PATH}/lib)',
                                  'set(DOPRA_LIBS ${OUTPUT_TEMP_PATH}/lib/${CMAKE_SYSTEM_PROCESSOR})')
    if relative == 'runtime/src/CJThread/src/CMakeLists.txt':
        # Keep incremental builds for both ABIs from sharing one archive output.
        content = content.replace('set(LIBRARY_OUTPUT_PATH ${PROJECT_SOURCE_DIR}/../../output/temp/lib)',
                                  'set(LIBRARY_OUTPUT_PATH ${PROJECT_SOURCE_DIR}/../../output/temp/lib/${CMAKE_SYSTEM_PROCESSOR})')
    if relative == 'runtime/CMakeLists.txt':
        # The NDK compiler supplies its own target builtins. Its public C++ ABI
        # is __n1/libc++_shared, unlike the system compiler's __h/libc++.so.
        content = content.replace('"-lstdc++" ${LINK_LIBS}', '"-lc++_shared" ${LINK_LIBS}')
        content = content.replace('-lunwind -lclang_rt.builtins -lhilog_ndk.z', '-lunwind -lhilog_ndk.z')
    if relative == 'runtime/src/LoaderManager.cpp':
        original = '    Dl_namespace dlns;\n    dlns_get(nullptr, &dlns);\n    return strcmp(dlns.name, "cj_rom_sdk") == 0;'
        replacement = ('#ifdef RULECORE_APP_RUNTIME\n'
                       '    // Application-packaged runtime: public dlopen in its own namespace.\n'
                       '    // No ROM SDK delegation or private namespace API is needed.\n'
                       '    return false;\n#else\n' + original + '\n#endif')
        if original not in content:
            raise SystemExit('Pinned ROM namespace probe did not match')
        content = content.replace(original, replacement)
    destination = root / relative
    if destination.read_text(encoding='utf-8') != content:
        destination.write_text(content, encoding='utf-8')
