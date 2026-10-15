BeforeAll {
    $script:launcher = Join-Path $PSScriptRoot ".." "wtlaunch.ps1"

    foreach ($name in "devwatch", "mediabox", "pilotage") {
        New-Item -ItemType Directory -Path (Join-Path $TestDrive $name) | Out-Null
    }

    $script:config = Join-Path $TestDrive "projects.json"
    @(
        @{ name = "devwatch"; path = Join-Path $TestDrive "devwatch" }
        @{ name = "mediabox"; path = Join-Path $TestDrive "mediabox"; color = "#1E5A8A" }
        @{ name = "pilotage"; path = Join-Path $TestDrive "pilotage" }
    ) | ConvertTo-Json | Set-Content -Encoding utf8 $script:config

    # The -WhatIf message goes straight to the host, so run a child pwsh to read its stdout
    function Invoke-Launcher {
        param([hashtable]$Params = @{}, [string]$Config = $script:config)
        $options = foreach ($key in $Params.Keys) {
            "-$key " + (($Params[$key] | ForEach-Object { "'$_'" }) -join ",")
        }
        $command = "& '$script:launcher' -WhatIf -ConfigPath '$Config' $($options -join ' ')"
        & (Get-Process -Id $PID).Path -NoProfile -Command $command 2>&1 | Out-String
    }
}

Describe "wtlaunch" {
    It "opens one tab per project from the config" {
        $out = Invoke-Launcher
        ([regex]::Matches($out, "new-tab")).Count | Should -Be 3
        $out | Should -Match '--title "DEVWATCH"'
    }

    It "uses the color declared in the config" {
        Invoke-Launcher | Should -Match '--title "MEDIABOX" --tabColor "#1E5A8A"'
    }

    It "keeps the same color for a project across runs" {
        $first = Invoke-Launcher -Params @{ Only = "devwatch" }
        $second = Invoke-Launcher -Params @{ Only = "devwatch" }
        $first | Should -Be $second
    }

    It "restricts the tabs with -Only" {
        $out = Invoke-Launcher -Params @{ Only = "devwatch", "pilotage" }
        $out | Should -Match "DEVWATCH"
        $out | Should -Not -Match "MEDIABOX"
    }

    It "removes tabs with -Exclude" {
        $out = Invoke-Launcher -Params @{ Exclude = "mediabox" }
        $out | Should -Match "PILOTAGE"
        $out | Should -Not -Match "MEDIABOX"
    }

    It "warns and opens nothing when no project matches" {
        $out = Invoke-Launcher -Params @{ Only = "unknown" }
        $out | Should -Match "Aucun projet"
        $out | Should -Not -Match "new-tab"
    }

    It "skips a project whose path does not exist" {
        $broken = Join-Path $TestDrive "broken.json"
        @(@{ name = "ghost"; path = Join-Path $TestDrive "missing" }) |
            ConvertTo-Json | Set-Content -Encoding utf8 $broken
        $out = Invoke-Launcher -Config $broken
        $out | Should -Match "Chemin introuvable pour ghost"
        $out | Should -Not -Match "new-tab"
    }

    It "falls back to the palette on an invalid color" {
        $bad = Join-Path $TestDrive "bad-color.json"
        @(@{ name = "devwatch"; path = Join-Path $TestDrive "devwatch"; color = "zzz" }) |
            ConvertTo-Json | Set-Content -Encoding utf8 $bad
        $out = Invoke-Launcher -Config $bad
        $out | Should -Match "Couleur invalide pour devwatch"
        $out | Should -Match '--tabColor "#[0-9A-F]{6}"'
    }

    It "warns when the text contrast falls below 4.5:1" {
        $pale = Join-Path $TestDrive "pale.json"
        @(@{ name = "devwatch"; path = Join-Path $TestDrive "devwatch"; color = "#808080" }) |
            ConvertTo-Json | Set-Content -Encoding utf8 $pale
        $out = Invoke-Launcher -Config $pale
        $out | Should -Match "Contraste du texte"
    }

    It "opens one split-pane per declared pane and refocuses the first one" {
        $paned = Join-Path $TestDrive "paned.json"
        @(@{
            name = "devwatch"
            path = Join-Path $TestDrive "devwatch"
            panes = @(@{ split = "vertical" }, @{ split = "horizontal" })
        }) | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $paned
        $out = Invoke-Launcher -Config $paned
        $out | Should -Match "split-pane -V"
        $out | Should -Match "split-pane -H"
        ([regex]::Matches($out, "split-pane")).Count | Should -Be 2
        ([regex]::Matches($out, "focus-pane -t 0")).Count | Should -Be 1
    }

    It "keeps a single shell when a project declares no panes" {
        $out = Invoke-Launcher
        $out | Should -Not -Match "split-pane"
        $out | Should -Not -Match "focus-pane"
    }

    It "ignores a pane with an invalid split" {
        $invalid = Join-Path $TestDrive "invalid-split.json"
        @(@{
            name = "devwatch"
            path = Join-Path $TestDrive "devwatch"
            panes = @(@{ split = "diagonal" })
        }) | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $invalid
        $out = Invoke-Launcher -Config $invalid
        $out | Should -Match "Split invalide pour un panneau de devwatch"
        $out | Should -Match "new-tab"
        $out | Should -Not -Match "split-pane"
        $out | Should -Not -Match "focus-pane"
    }

    It "stops on invalid JSON" {
        $invalid = Join-Path $TestDrive "invalid.json"
        Set-Content $invalid "[{"
        $out = Invoke-Launcher -Config $invalid
        $out | Should -Match "Conversion from JSON failed"
        $out | Should -Not -Match "new-tab"
    }
}
