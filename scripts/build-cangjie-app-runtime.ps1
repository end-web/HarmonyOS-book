param(
  [string]$DevEcoRoot = $env:DEVECO_HOME,
  [ValidateSet('arm64-v8a', 'x86_64')][string[]]$Abi = @('arm64-v8a', 'x86_64'),
  [int]$Jobs = 4
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$ruleRoot = Join-Path $projectRoot 'third_party\rulecore'
$upstreamRoot = Join-Path $ruleRoot 'build\upstream-runtime'
$runtimeRoot = Join-Path $upstreamRoot 'runtime'
$boundsRoot = Join-Path $runtimeRoot 'third_party\third_party_bounds_checking_function'
$nativeRoot = Join-Path $DevEcoRoot 'sdk\default\openharmony\native'
$cmake = Join-Path $nativeRoot 'build-tools\cmake\bin\cmake.exe'
$ninja = Join-Path $nativeRoot 'build-tools\cmake\bin\ninja.exe'
$strip = Join-Path $nativeRoot 'llvm\bin\llvm-strip.exe'
$runtimeCommit = '52f9e08f985ba42e23581e725e1b11f956f941d6'
$boundsCommit = '2ae82839ecaaa7d031e66ccbd2076d671acfd615'
$sdk = Get-Content (Join-Path $DevEcoRoot 'sdk\default\sdk-pkg.json') -Raw | ConvertFrom-Json
if ($sdk.data.releaseType -ne 'Release') { throw 'A Release SDK is required' }
if ($Jobs -lt 1 -or $Jobs -gt 16) { throw 'Jobs must be between 1 and 16' }
foreach ($tool in @($cmake, $ninja, $strip)) {
  if (-not (Test-Path -LiteralPath $tool)) { throw "Missing tool: $tool" }
}
function Invoke-RuleBuild([string]$Executable, [string[]]$Arguments) {
  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed: $Executable ($LASTEXITCODE)" }
}
if (-not (Test-Path -LiteralPath (Join-Path $upstreamRoot '.git'))) {
  Invoke-RuleBuild 'git' @('clone', '--depth', '1', '--branch', 'v1.2.0',
    'https://gitcode.com/Cangjie/cangjie_runtime.git', $upstreamRoot)
}
if ((& git -C $upstreamRoot rev-parse HEAD).Trim() -ne $runtimeCommit) { throw 'Unexpected runtime source revision' }
if (-not (Test-Path -LiteralPath (Join-Path $boundsRoot '.git'))) {
  Invoke-RuleBuild 'git' @('clone', '--depth', '1', '--branch', 'OpenHarmony-v6.0-Release',
    'https://gitcode.com/openharmony/third_party_bounds_checking_function.git', $boundsRoot)
}
if ((& git -C $boundsRoot rev-parse HEAD).Trim() -ne $boundsCommit) { throw 'Unexpected bounds-checking revision' }
Invoke-RuleBuild 'python' @((Join-Path $ruleRoot 'tools\prepare_app_runtime.py'), '--source', $upstreamRoot, '--native', $nativeRoot)

foreach ($targetAbi in $Abi) {
  $arch = if ($targetAbi -eq 'arm64-v8a') { 'aarch64' } else { 'x86_64' }
  $ohosFlag = if ($targetAbi -eq 'arm64-v8a') { '1' } else { '2' }
  $buildName = if ($targetAbi -eq 'arm64-v8a') { 'arm64' } else { 'x86_64' }
  $threadBuild = Join-Path $ruleRoot ('build\runtime-' + $buildName + '-thread')
  $mainBuild = Join-Path $ruleRoot ('build\runtime-' + $buildName + '-main')
  $common = @('-G', 'Ninja', "-DCMAKE_TOOLCHAIN_FILE=$nativeRoot/build/cmake/ohos.toolchain.cmake",
    "-DCMAKE_MAKE_PROGRAM=$ninja", "-DOHOS_ARCH=$targetAbi", '-DOHOS_PLATFORM=OHOS',
    '-DOHOS_STL=c++_shared', '-DCMAKE_BUILD_TYPE=Release')
  $protection = if ($targetAbi -eq 'arm64-v8a') { @('-DRUNTIME_BACKWARD_PTRAUTH_CFI=1') } else { @() }
  Invoke-RuleBuild $cmake ($common + @('-S', "$runtimeRoot/src/CJThread", '-B', $threadBuild,
    "-DTARGET=ohos_${arch}_cangjie", '-DLIBTYPE=STATIC', '-DBUILDING_STAGE=publish') + $protection)
  Invoke-RuleBuild $cmake @('--build', $threadBuild, '--target', 'cangjie-thread', '-j', "$Jobs")
  Invoke-RuleBuild $cmake ($common + @('-S', $runtimeRoot, '-B', $mainBuild,
    "-DOHOS_FLAG=$ohosFlag", '-DBUILD_CJTHREAD=OFF', '-DCOPYGC_FLAG=1', '-DDOPRA_FLAG=1',
    '-DCJ_SDK_VERSION=1.2.0', '-DCMAKE_CXX_FLAGS=-DRULECORE_APP_RUNTIME', '-DDISABLE_VERSION_CHECK=0') + $protection)
  Invoke-RuleBuild $cmake @('--build', $mainBuild, '--target', 'cangjie-runtime', '-j', "$Jobs")
  $built = Join-Path $runtimeRoot "output/temp/lib/${arch}_Release/libcangjie-runtime.so"
  $destination = Join-Path $ruleRoot "build/app-runtime/$targetAbi"
  New-Item -ItemType Directory -Force $destination | Out-Null
  $library = Join-Path $destination 'libcangjie-runtime.so'
  Copy-Item -LiteralPath $built -Destination $library -Force
  Invoke-RuleBuild $strip @('--strip-debug', $library)
  Invoke-RuleBuild 'python' @((Join-Path $ruleRoot 'tools\verify_app_runtime.py'), '--native', $nativeRoot,
    '--runtime', $library, '--app-libs', (Join-Path $projectRoot 'entry\libs'), '--abi', $targetAbi)
  [pscustomobject]@{ sourceCommit=$runtimeCommit; boundsCommit=$boundsCommit; abi=$targetAbi;
    sdkVersion=$sdk.data.version; sdkChannel=$sdk.data.releaseType; versionCompatibilityCheck=$true;
    sha256=(Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant() } |
    ConvertTo-Json | Set-Content (Join-Path $destination 'runtime-build.json') -Encoding utf8
}
