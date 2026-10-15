$ErrorActionPreference = "Stop"

$root = Join-Path ([IO.Path]::GetTempPath()) "wtlaunch-smoke"
$launcher = Join-Path $PSScriptRoot ".." "wtlaunch.ps1"
$config = Join-Path $root "projects.json"

try {
    New-Item -ItemType Directory -Force (Join-Path $root "alpha"), (Join-Path $root "beta") | Out-Null
    @(
        @{ name = "alpha"; path = Join-Path $root "alpha" }
        @{
            name = "beta"
            path = Join-Path $root "beta"
            color = "#1E5A8A"
            panes = @(@{ split = "vertical" }, @{ split = "horizontal" })
        }
    ) | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $config

    & $launcher -WhatIf -ConfigPath $config -WarningVariable warnings
    if ($warnings) { throw "Unexpected warnings: $warnings" }
} finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}
