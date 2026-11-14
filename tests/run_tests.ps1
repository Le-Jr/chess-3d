# Runs the headless test suite.
#
#   .\tests\run_tests.ps1                       # uses `godot` from PATH or $env:GODOT
#   .\tests\run_tests.ps1 -Godot "C:\path\to\Godot_v4.x_console.exe"
#   .\tests\run_tests.ps1 -Full                 # also run the slow, deep perft counts
#   .\tests\run_tests.ps1 -Filter perft         # only suites whose file name matches
param(
	[string]$Godot = $(if ($env:GODOT) { $env:GODOT } else { "godot" }),
	[switch]$Full,
	[string]$Filter = ""
)

$project = Split-Path -Parent $PSScriptRoot

# Build the global class cache (class_name lookups) on a fresh checkout.
if (-not (Test-Path (Join-Path $project ".godot\global_script_class_cache.cfg"))) {
	& $Godot --headless --path $project --import | Out-Null
}

$userArgs = @()
if ($Full) { $userArgs += "--full" }
if ($Filter) { $userArgs += $Filter }

$output = & $Godot --headless --path $project -s tests/run_tests.gd -- @userArgs 2>&1 | ForEach-Object { "$_" }
$code = $LASTEXITCODE
$output | ForEach-Object { Write-Host $_ }

# A GDScript runtime error aborts a function without failing the process,
# so treat any reported script error as a test failure too.
if ($output -match "SCRIPT ERROR|Parse Error") {
	Write-Host "Script errors were reported - treating the run as failed."
	exit 1
}
exit $code
