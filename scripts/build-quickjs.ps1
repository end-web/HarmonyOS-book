param(
  [string]$DevEcoRoot = $env:DEVECO_HOME
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DevEcoRoot)) {
  throw 'DEVECO_HOME 未配置，请通过 -DevEcoRoot 指定 DevEco Studio 安装目录'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$quickJsRoot = Join-Path $projectRoot 'third_party\quickjs'
$nodeExecutable = Join-Path $DevEcoRoot 'tools\node\node.exe'
$ohpmCli = Join-Path $DevEcoRoot 'tools\ohpm\bin\pm-cli.js'
$hvigorCli = Join-Path $DevEcoRoot 'tools\hvigor\bin\hvigorw.js'
$builtHar = Join-Path $quickJsRoot 'quickjs\build\default\outputs\default\quickjs.har'
$targetHar = Join-Path $projectRoot 'entry\libs\quickjs.har'
$targetHash = Join-Path $projectRoot 'entry\libs\quickjs.har.sha256'

foreach ($requiredPath in @($nodeExecutable, $ohpmCli, $hvigorCli)) {
  if (-not (Test-Path -LiteralPath $requiredPath)) {
    throw "缺少构建工具：$requiredPath"
  }
}

Push-Location $quickJsRoot
try {
  & $nodeExecutable $ohpmCli install
  if ($LASTEXITCODE -ne 0) { throw "ohpm install 失败：$LASTEXITCODE" }

  & $nodeExecutable --max-old-space-size=8192 --expose-gc $hvigorCli clean
  if ($LASTEXITCODE -ne 0) { throw "QuickJS clean 失败：$LASTEXITCODE" }

  & $nodeExecutable --max-old-space-size=8192 --expose-gc $hvigorCli `
    assembleHar --mode module -p product=default -p module=quickjs@default
  if ($LASTEXITCODE -ne 0) { throw "QuickJS HAR 构建失败：$LASTEXITCODE" }
} finally {
  Pop-Location
}

if (-not (Test-Path -LiteralPath $builtHar)) {
  throw "未找到 HAR 产物：$builtHar"
}

New-Item -ItemType Directory -Force (Split-Path -Parent $targetHar) | Out-Null
Copy-Item -LiteralPath $builtHar -Destination $targetHar -Force
$hash = Get-FileHash -LiteralPath $targetHar -Algorithm SHA256
Set-Content -LiteralPath $targetHash -Value "$($hash.Hash)  quickjs.har" -Encoding ascii
Write-Host "QuickJS HAR: $targetHar"
Write-Host "SHA256: $($hash.Hash)"
