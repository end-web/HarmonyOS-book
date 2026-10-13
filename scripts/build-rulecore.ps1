param(
  [string]$DevEcoRoot = $env:DEVECO_HOME,
  [string]$CangjieRoot = 'D:\soft\cangjie-1.2.0-ohos',
  [switch]$VerifyHost
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourceRoot = Join-Path $projectRoot 'third_party\rulecore'
$nativeRoot = Join-Path $DevEcoRoot 'sdk\default\openharmony\native'
$sysroot = Join-Path $nativeRoot 'sysroot'
$sdkMetadata = Get-Content -LiteralPath (Join-Path $DevEcoRoot 'sdk\default\sdk-pkg.json') -Raw | ConvertFrom-Json
if ($sdkMetadata.data.releaseType -ne 'Release') { throw 'Rulecore must be built against a Release HarmonyOS SDK' }
$cjc = Join-Path $CangjieRoot 'bin\cjc.exe'
$clang = Join-Path $nativeRoot 'llvm\bin\clang++.exe'
$readelf = Join-Path $nativeRoot 'llvm\bin\llvm-readelf.exe'
foreach ($tool in @($cjc, $clang, $readelf)) {
  if (-not (Test-Path -LiteralPath $tool)) { throw "Missing build tool: $tool" }
}
# The downloadable OHOS runtime targets system C++ (__h/libc++.so), which is
# unavailable in an application namespace. Always build/verify the same-version
# application runtime before packaging; never silently restore the PC binary.
& (Join-Path $PSScriptRoot 'build-cangjie-app-runtime.ps1') -DevEcoRoot $DevEcoRoot
$oldPath = $env:Path
$oldCangjie = $env:CANGJIE_HOME
try {
  . (Join-Path $CangjieRoot 'envsetup.ps1')
  $version = (& $cjc --version | Out-String).Trim()
  if ($version -notmatch 'Cangjie Compiler: 1\.2\.0 ') { throw "Expected audited Cangjie 1.2.0 toolchain, got $version" }
  $records = @()
  foreach ($target in @(
    @{ Abi = 'arm64-v8a'; Triple = 'aarch64-linux-ohos'; Runtime = 'linux_ohos_aarch64_cjnative'; Machine = 'AArch64' },
    @{ Abi = 'x86_64'; Triple = 'x86_64-linux-ohos'; Runtime = 'linux_ohos_x86_64_cjnative'; Machine = 'Advanced Micro Devices X86-64' }
  )) {
    $buildDir = Join-Path $sourceRoot ('build\' + $target.Abi)
    $outputDir = Join-Path $projectRoot ('entry\libs\' + $target.Abi)
    $syslib = Join-Path $nativeRoot ('sysroot\usr\lib\' + $target.Triple)
    $runtimeDir = Join-Path $CangjieRoot ('runtime\lib\' + $target.Runtime)
    New-Item -ItemType Directory -Force $buildDir, $outputDir | Out-Null
    $core = Join-Path $buildDir 'librulecore_cj.so'
    & $cjc (Join-Path $sourceRoot 'src\tokenizer.cj') --output-type=dylib `
      --target=$($target.Triple) --sysroot (Join-Path $nativeRoot 'sysroot') `
      -B $syslib -L $syslib --link-option '-soname=librulecore_cj.so' -o $core
    if ($LASTEXITCODE -ne 0) { throw "Cangjie compilation failed for $($target.Abi)" }
    $binding = Join-Path $buildDir 'libnative_rulecore.so'
    & $clang --target=$($target.Triple) --sysroot=$sysroot `
      -std=c++17 -O2 -shared -fPIC -fstack-protector-strong -fvisibility=hidden `
      '-Wl,-z,relro,-z,now,-z,noexecstack' '-Wl,-soname,libnative_rulecore.so' '-Wl,-rpath,$ORIGIN' `
      -I (Join-Path $sourceRoot 'include') (Join-Path $sourceRoot 'src\native_rulecore.cpp') `
      -L $runtimeDir '-l:libcangjie-runtime.so' '-lace_napi.z' '-lhilog_ndk.z' -ldl -o $binding
    if ($LASTEXITCODE -ne 0) { throw "NAPI compilation failed for $($target.Abi)" }

    # Include only runtime dependencies reachable from our two libraries. Platform libraries stay on-device.
    $pending = [System.Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($core)
    $pending.Enqueue($binding)
    $copied = [System.Collections.Generic.HashSet[string]]::new()
    while ($pending.Count -gt 0) {
      $library = $pending.Dequeue()
      $name = Split-Path -Leaf $library
      if (-not $copied.Add($name)) { continue }
      $headers = (& $readelf -h $library | Out-String)
      if ($headers -notmatch [regex]::Escape($target.Machine)) { throw "Wrong ELF architecture: $library" }
      Copy-Item -LiteralPath $library -Destination (Join-Path $outputDir $name) -Force
      $records += [pscustomobject]@{ abi=$target.Abi; file=$name; sha256=(Get-FileHash -LiteralPath $library -Algorithm SHA256).Hash.ToLowerInvariant() }
      $dynamic = (& $readelf -d $library | Out-String)
      foreach ($match in [regex]::Matches($dynamic, 'Shared library: \[([^\]]+)\]')) {
        $dependency = Join-Path $runtimeDir $match.Groups[1].Value
        if ($match.Groups[1].Value -eq 'libcangjie-runtime.so') {
          $appRuntime = Join-Path $sourceRoot ('build\app-runtime\' + $target.Abi + '\libcangjie-runtime.so')
          if (-not (Test-Path -LiteralPath $appRuntime)) { throw "Missing verified application runtime: $appRuntime" }
          $pending.Enqueue($appRuntime)
        }
        elseif ($match.Groups[1].Value -eq 'libc++.so') {
          throw 'System libc++.so must not be packaged into the application runtime'
        }
        elseif (Test-Path -LiteralPath $dependency) { $pending.Enqueue($dependency) }
        elseif ($match.Groups[1].Value -eq 'libc++_shared.so') {
          $cxxRuntime = Join-Path $nativeRoot ('llvm\lib\' + $target.Triple + '\libc++_shared.so')
          if (-not (Test-Path -LiteralPath $cxxRuntime)) { throw "Missing application C++ runtime: $cxxRuntime" }
          $pending.Enqueue($cxxRuntime)
        }
      }
    }
    Write-Host "Built $($target.Abi): $($copied.Count) native libraries"
  }
  $manifest = [pscustomobject]@{
    cangjieVersion='1.2.0'; cangjieChannel='STS'; harmonySdkVersion=$sdkMetadata.data.version;
    harmonySdkChannel=$sdkMetadata.data.releaseType; minimumRuntimeApiValidated=$null;
    deviceValidation='pending'; appRuntimeVersionCompatibilityCheck=$true;
    appRuntimeSourceCommit='52f9e08f985ba42e23581e725e1b11f956f941d6';
    appRuntimeBoundsCommit='2ae82839ecaaa7d031e66ccbd2076d671acfd615';
    appRuntimeAbi=@('arm64-v8a','x86_64'); artifacts=$records
  }
  $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $projectRoot 'entry\libs\rulecore-build.json') -Encoding utf8
  if ($VerifyHost) {
    $hostBuild = Join-Path $sourceRoot 'build\host'
    New-Item -ItemType Directory -Force $hostBuild | Out-Null
    $hostLibrary = Join-Path $hostBuild 'rulecore.dll'
    & $cjc (Join-Path $sourceRoot 'src\tokenizer.cj') --output-type=dylib -o $hostLibrary
    if ($LASTEXITCODE -ne 0) { throw 'Host Cangjie compilation failed' }
    & python (Join-Path $sourceRoot 'tests\verify_cabi.py') $CangjieRoot $hostLibrary
    if ($LASTEXITCODE -ne 0) { throw 'Host C ABI verification failed' }
  }
} finally {
  $env:Path = $oldPath
  $env:CANGJIE_HOME = $oldCangjie
}
