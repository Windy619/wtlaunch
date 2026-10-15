[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Only,
    [string[]]$Exclude,
    [string]$ConfigPath = (Join-Path $PSScriptRoot "projects.json")
)

$ErrorActionPreference = "Stop"

$wwwPath = "C:\laragon\www"
# Dark tones only: each one gives at least 7:1 with the white text Windows Terminal picks
$palette = @("#7A2A3A", "#2E5A4A", "#6E3A1E", "#7A2A5A", "#1E5A8A", "#5A1E8A", "#8A1E5A", "#2E5A2E")

function Get-Luminance([string]$hex) {
    $channels = foreach ($offset in 1, 3, 5) {
        $c = [Convert]::ToInt32($hex.Substring($offset, 2), 16) / 255
        if ($c -le 0.03928) { $c / 12.92 } else { [math]::Pow(($c + 0.055) / 1.055, 2.4) }
    }
    0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2]
}

function Get-TextContrast([string]$hex) {
    $l = Get-Luminance $hex
    [math]::Max(1.05 / ($l + 0.05), ($l + 0.05) / 0.05)
}

# String.GetHashCode is randomized per process, so hash the name ourselves to keep colors stable
function Get-PaletteColor([string]$name) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($name.ToLower())
    $hash = [Security.Cryptography.SHA1]::HashData($bytes)
    $palette[$hash[0] % $palette.Length]
}

if (Test-Path $ConfigPath) {
    $projects = Get-Content -Raw -Encoding utf8 $ConfigPath | ConvertFrom-Json
} else {
    $projects = Get-ChildItem -Path $wwwPath -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName ".git") } |
        ForEach-Object { [pscustomobject]@{ name = $_.Name; path = $_.FullName } }
}

if ($Only) { $projects = $projects | Where-Object { $_.name -in $Only } }
if ($Exclude) { $projects = $projects | Where-Object { $_.name -notin $Exclude } }
$projects = @($projects)

if ($projects.Count -eq 0) {
    Write-Warning "Aucun projet a lancer."
    return
}

$wtArgs = @()
foreach ($proj in $projects) {
    if (-not (Test-Path $proj.path)) {
        Write-Warning "Chemin introuvable pour $($proj.name) : $($proj.path)"
        continue
    }

    $color = $proj.color
    if ($color -and $color -notmatch '^#[0-9A-Fa-f]{6}$') {
        Write-Warning "Couleur invalide pour $($proj.name) : $color"
        $color = $null
    }
    if ($color -and (Get-TextContrast $color) -lt 4.5) {
        Write-Warning "Contraste du texte sous 4,5:1 pour $($proj.name) ($color)"
    }
    if (-not $color) { $color = Get-PaletteColor $proj.name }

    if ($wtArgs.Count -gt 0) { $wtArgs += ";" }
    $wtArgs += "new-tab"
    $wtArgs += "--title", "`"$($proj.name.ToUpper())`"", "--tabColor", "`"$color`""
    $wtArgs += "--suppressApplicationTitle", "-d", "`"$($proj.path)`""
}

if ($wtArgs.Count -eq 0) { return }
$wtArgs += ";", "focus-tab", "-t", "0"

if ($PSCmdlet.ShouldProcess("wt", $wtArgs -join " ")) {
    Start-Process wt -ArgumentList $wtArgs
}
