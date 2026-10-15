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
    foreach ($name in "alpha", "beta") {
        New-Item -ItemType Directory -Path (Join-Path $TestDrive "rootA" $name ".git") -Force | Out-Null
    }
    New-Item -ItemType Directory -Path (Join-Path $TestDrive "rootB" "gamma" ".git") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $TestDrive "rootA" "plain") | Out-Null
    $script:noConfig = Join-Path $TestDrive "absent.json"

    function Invoke-Launcher {
        param([hashtable]$Params = @{}, [string]$Config = $script:config, [string]$Extra = "")
        $options = foreach ($key in $Params.Keys) {
            "-$key " + (($Params[$key] | ForEach-Object { "'$_'" }) -join ",")
        }
        $command = "& '$script:launcher' -WhatIf -ConfigPath '$Config' $($options -join ' ') $Extra"
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

    It "runs the project command in the tab and keeps the shell open" {
        $cmd = Join-Path $TestDrive "command.json"
        @(@{ name = "devwatch"; path = Join-Path $TestDrive "devwatch"; command = "php artisan serve" }) |
            ConvertTo-Json | Set-Content -Encoding utf8 $cmd
        $out = Invoke-Launcher -Config $cmd
        $out.Contains('new-tab --title "DEVWATCH"') | Should -BeTrue
        $out.Contains('pwsh -NoExit -Command "php artisan serve" ; focus-tab') | Should -BeTrue
    }

    It "runs a command in a pane without touching the tab shell" {
        $cmd = Join-Path $TestDrive "pane-command.json"
        @(@{
            name = "devwatch"
            path = Join-Path $TestDrive "devwatch"
            panes = @(@{ split = "vertical"; command = "npm run dev" }, @{ split = "horizontal" })
        }) | ConvertTo-Json -Depth 4 | Set-Content -Encoding utf8 $cmd
        $out = Invoke-Launcher -Config $cmd
        ([regex]::Matches($out, "-NoExit")).Count | Should -Be 1
        $out | Should -Match 'split-pane -V -d "[^"]+" pwsh -NoExit -Command "npm run dev" ;'
        $out | Should -Match 'split-pane -H -d "[^"]+" ; focus-pane'
    }

    It "escapes semicolons and quotes so wt passes the command through intact" {
        $cmd = Join-Path $TestDrive "escape.json"
        @(@{ name = "devwatch"; path = Join-Path $TestDrive "devwatch"; command = 'echo "hi"; echo bye' }) |
            ConvertTo-Json | Set-Content -Encoding utf8 $cmd
        $out = Invoke-Launcher -Config $cmd
        $out.Contains('pwsh -NoExit -Command "echo \"hi\"\; echo bye"') | Should -BeTrue
    }

    It "starts no extra shell when no command is declared" {
        Invoke-Launcher | Should -Not -Match "-NoExit"
    }

    It "stops on invalid JSON" {
        $invalid = Join-Path $TestDrive "invalid.json"
        Set-Content $invalid "[{"
        $out = Invoke-Launcher -Config $invalid
        $out | Should -Match "Conversion from JSON failed"
        $out | Should -Not -Match "new-tab"
    }

    It "scans the folders given with -Root and keeps only git projects" {
        $out = Invoke-Launcher -Config $script:noConfig -Params @{ Root = (Join-Path $TestDrive "rootA"), (Join-Path $TestDrive "rootB") }
        $out | Should -Match "ALPHA"
        $out | Should -Match "GAMMA"
        $out | Should -Not -Match "PLAIN"
    }

    It "reads the roots from WTLAUNCH_ROOT when -Root is absent" {
        $env:WTLAUNCH_ROOT = (Join-Path $TestDrive "rootA") + ";" + (Join-Path $TestDrive "rootB")
        try { $out = Invoke-Launcher -Config $script:noConfig } finally { $env:WTLAUNCH_ROOT = $null }
        $out | Should -Match "BETA"
        $out | Should -Match "GAMMA"
    }

    It "prefers -Root over WTLAUNCH_ROOT" {
        $env:WTLAUNCH_ROOT = Join-Path $TestDrive "rootB"
        try { $out = Invoke-Launcher -Config $script:noConfig -Params @{ Root = (Join-Path $TestDrive "rootA") } } finally { $env:WTLAUNCH_ROOT = $null }
        $out | Should -Match "ALPHA"
        $out | Should -Not -Match "GAMMA"
    }

    It "warns about a missing root without blocking the others" {
        $out = Invoke-Launcher -Config $script:noConfig -Params @{ Root = (Join-Path $TestDrive "nowhere"), (Join-Path $TestDrive "rootB") }
        $out | Should -Match "Dossier racine introuvable"
        $out | Should -Match "GAMMA"
    }

    It "ignores -Root when a config file exists" {
        $out = Invoke-Launcher -Params @{ Root = (Join-Path $TestDrive "rootB") }
        $out | Should -Match "DEVWATCH"
        $out | Should -Not -Match "GAMMA"
    }

    Context "branch in the tab title" {
        BeforeAll {
            function Initialize-TestRepo([string]$name, [string]$head) {
                $dir = Join-Path $TestDrive $name
                New-Item -ItemType Directory -Path (Join-Path $dir ".git") -Force | Out-Null
                Set-Content (Join-Path $dir ".git" "HEAD") $head
                $cfg = Join-Path $TestDrive "$name.json"
                @(@{ name = $name; path = $dir }) | ConvertTo-Json | Set-Content -Encoding utf8 $cfg
                $cfg
            }
        }

        It "shows the current branch" {
            $out = Invoke-Launcher -Config (Initialize-TestRepo "feature" "ref: refs/heads/feat/6-demo")
            $out | Should -Match '--title "FEATURE \(feat/6-demo\)"'
        }

        It "flags a protected branch with text" {
            $out = Invoke-Launcher -Config (Initialize-TestRepo "guarded" "ref: refs/heads/develop")
            $out | Should -Match '--title "GUARDED \(develop\) PROTEGEE"'
        }

        It "keeps the plain title without a git folder or on a detached HEAD" {
            $detached = Initialize-TestRepo "loose" "0123456789abcdef0123456789abcdef01234567"
            Invoke-Launcher -Config $detached | Should -Match '--title "LOOSE" '
            Invoke-Launcher | Should -Match '--title "DEVWATCH" '
        }

        It "follows the gitdir pointer of a worktree" {
            $real = Join-Path $TestDrive "real-git"
            New-Item -ItemType Directory -Path $real | Out-Null
            Set-Content (Join-Path $real "HEAD") "ref: refs/heads/fix/7-linked"
            $dir = Join-Path $TestDrive "linked"
            New-Item -ItemType Directory -Path $dir | Out-Null
            Set-Content (Join-Path $dir ".git") "gitdir: $real"
            $cfg = Join-Path $TestDrive "linked.json"
            @(@{ name = "linked"; path = $dir }) | ConvertTo-Json | Set-Content -Encoding utf8 $cfg
            Invoke-Launcher -Config $cfg | Should -Match 'LINKED \(fix/7-linked\)'
        }

        It "hides the branch with -NoBranch" {
            $cfg = Initialize-TestRepo "quiet" "ref: refs/heads/main"
            Invoke-Launcher -Config $cfg -Extra "-NoBranch" | Should -Match '--title "QUIET" '
        }
    }
}
