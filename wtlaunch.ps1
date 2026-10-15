[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Only,
    [string[]]$Exclude,
    [string[]]$Root,
    [switch]$NoBranch,
    [string]$ConfigPath = (Join-Path $PSScriptRoot "projects.json")
)

$ErrorActionPreference = "Stop"

# Dark tones only: each one gives at least 7:1 with the white text Windows Terminal picks
$palette = @("#7A2A3A", "#2E5A4A", "#6E3A1E", "#7A2A5A", "#1E5A8A", "#5A1E8A", "#8A1E5A", "#2E5A2E")

function Get-Luminance([string]$hex) {
    $channels = foreach ($offset in 1, 3, 5) {
        $c = [Convert]::ToInt32($hex.Substring($offset, 2), 16) / 255
        if ($c -le 0.03928) { $c / 12.92 } else { [math]::Pow(($c + 0.055) / 1.055, 2.4) }
    }
    0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2]
}

# Windows Terminal draws black text on "bright" tabs and white text otherwise, so measure that pair
function Get-TextContrast([string]$hex) {
    $r, $g, $b = foreach ($offset in 1, 3, 5) { [Convert]::ToInt32($hex.Substring($offset, 2), 16) }
    $l = Get-Luminance $hex
    if ((2 * $r + 5 * $g + $b) -gt 1024) { ($l + 0.05) / 0.05 } else { 1.05 / ($l + 0.05) }
}

# String.GetHashCode is randomized per process, so hash the name ourselves to keep colors stable
function Get-PaletteColor([string]$name) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($name.ToLower())
    $hash = [Security.Cryptography.SHA1]::HashData($bytes)
    $palette[$hash[0] % $palette.Length]
}

# wt splits its command line on ';' and the Windows parser treats quotes and backslashes specially
function Get-StartupCommand([string]$command) {
    if (-not $command) { return @() }
    $escaped = $command -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1' -replace ';', '\;'
    "pwsh", "-NoExit", "-Command", "`"$escaped`""
}

# Read HEAD directly so no git binary is needed; a worktree has a .git file pointing to its real folder
function Get-GitBranch([string]$path) {
    $git = Join-Path $path ".git"
    if (Test-Path $git -PathType Leaf) {
        $pointer = (Get-Content -Raw $git).Trim()
        if ($pointer -notmatch '^gitdir:\s*(.+)$') { return }
        $git = $Matches[1]
        if (-not [IO.Path]::IsPathRooted($git)) { $git = Join-Path $path $git }
    }
    $head = Join-Path $git "HEAD"
    if (-not (Test-Path $head -PathType Leaf)) { return }
    if ((Get-Content -Raw $head) -match '^ref:\s*refs/heads/(.+?)\s*$') { $Matches[1] }
}

# The protected-branch flag is text, not only color, so it stays readable whatever the tab color
function Get-TabTitle([string]$name, [string]$path, [bool]$hideBranch) {
    $title = $name.ToUpper()
    if ($hideBranch) { return $title }
    $branch = Get-GitBranch $path
    if (-not $branch) { return $title }
    $title += " ($branch)"
    if ($branch -in "develop", "staging", "main") { $title += " PROTEGEE" }
    $title
}

if (Test-Path $ConfigPath) {
    $projects = Get-Content -Raw -Encoding utf8 $ConfigPath | ConvertFrom-Json
} else {
    $roots = if ($Root) { $Root }
        elseif ($env:WTLAUNCH_ROOT) { $env:WTLAUNCH_ROOT -split ';' | Where-Object { $_ } }
        elseif (Test-Path "C:\laragon\www") { "C:\laragon\www" }
    if (-not $roots) {
        Write-Warning "Aucun dossier racine : utiliser -Root, la variable WTLAUNCH_ROOT ou un projects.json."
        return
    }
    $projects = foreach ($dir in $roots) {
        if (-not (Test-Path $dir)) {
            Write-Warning "Dossier racine introuvable : $dir"
            continue
        }
        Get-ChildItem -Path $dir -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName ".git") } |
            ForEach-Object { [pscustomobject]@{ name = $_.Name; path = $_.FullName } }
    }
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
    $wtArgs += "--title", "`"$(Get-TabTitle $proj.name $proj.path $NoBranch)`"", "--tabColor", "`"$color`""
    $wtArgs += "--suppressApplicationTitle", "-d", "`"$($proj.path)`""
    $wtArgs += Get-StartupCommand $proj.command

    $splits = 0
    foreach ($pane in $proj.panes) {
        $flag = switch ($pane.split) { "vertical" { "-V" } "horizontal" { "-H" } }
        if (-not $flag) {
            Write-Warning "Split invalide pour un panneau de $($proj.name) : $($pane.split)"
            continue
        }
        $wtArgs += ";", "split-pane", $flag, "-d", "`"$($proj.path)`""
        $wtArgs += Get-StartupCommand $pane.command
        $splits++
    }
    # Each split moves focus to the new pane, so go back to the first one
    if ($splits -gt 0) { $wtArgs += ";", "focus-pane", "-t", "0" }
}

if ($wtArgs.Count -eq 0) { return }
$wtArgs += ";", "focus-tab", "-t", "0"

if ($PSCmdlet.ShouldProcess("wt", $wtArgs -join " ")) {
    Start-Process wt -ArgumentList $wtArgs
}
