$config = New-PesterConfiguration
$config.Run.Path = $PSScriptRoot
$config.Run.Exit = $true
$config.Output.Verbosity = "Detailed"
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = "JUnitXml"
$config.TestResult.OutputPath = Join-Path $PSScriptRoot ".." "report.xml"

Invoke-Pester -Configuration $config
