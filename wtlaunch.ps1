$wwwPath = "C:\laragon\www"
$colors = @("#7A2A3A", "#00FF22", "#2E5A4A", "#8A5A1E", "#7A2A5A", "#1E5A8A", "#5A1E8A", "#8A1E5A")

$projects = Get-ChildItem -Path $wwwPath -Directory

$args = @()
$i = 0
foreach ($proj in $projects) {
    $color = $colors[$i % $colors.Length]
    $title = $proj.Name.ToUpper()
    $path = $proj.FullName

    if ($i -eq 0) {
        $args += "new-tab"
    } else {
        $args += ";"
        $args += "new-tab"
    }
    $args += "--title", "`"$title`"", "--tabColor", "`"$color`"", "--suppressApplicationTitle", "-d", "`"$path`""
    $i++
}
$args += ";", "focus-tab", "-t", "1"

Start-Process wt -ArgumentList $args