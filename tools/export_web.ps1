# Exports the game for the web into build/web (preset "Web" in export_presets.cfg).
#
#   .\tools\export_web.ps1                      # uses `godot` from PATH or $env:GODOT
#   .\tools\export_web.ps1 -Godot "C:\path\to\Godot_v4.x_console.exe"
#   .\tools\export_web.ps1 -Serve               # ...and serve it at http://localhost:8060
#
# Needs Godot's web export templates (Editor -> Manage Export Templates).
param(
	[string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "godot" }),
	[switch]$Serve
)

$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $project "build\web"
New-Item -ItemType Directory -Force $out | Out-Null

& $Godot --headless --path $project --import | Out-Null
& $Godot --headless --path $project --export-release "Web" (Join-Path $out "index.html")
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $out "index.wasm"))) {
	Write-Host "Export failed." -ForegroundColor Red
	exit 1
}

$total = 0
Get-ChildItem $out -File | Sort-Object Length -Descending | ForEach-Object {
	$total += $_.Length
	"{0,10:N0} KB  {1}" -f ($_.Length / 1KB), $_.Name
}
"{0,10:N0} KB  total (uncompressed; hosts that gzip / brotli send about a quarter)" -f ($total / 1KB)

if ($Serve) {
	python (Join-Path $PSScriptRoot "serve_web.py") $out
}
