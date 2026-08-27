param(
	[Parameter(Position = 0)]
	[ValidateSet("evaluate", "validate", "bench", "rpc", "optimize", "generate", "regress", "ui")]
	[string]$Command = "evaluate",

	[string]$Class = "Witch",
	[string]$Ascendancy = "Elementalist",
	[int]$Level = 90,
	[string]$Skill = "Winter Orb",
	[int]$BenchCount = 100,
	[int]$BeamSize = 100,
	[string]$Definition,
	[switch]$DryRun,
	[string]$LuaJit
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$pobSrc = Join-Path $root "vendor\PathOfBuilding\src"
$worker = Join-Path $root "core\pob-engine\worker.lua"

if (-not (Test-Path $pobSrc)) {
	throw "Path of Building source not found at $pobSrc"
}
if (-not (Test-Path $worker)) {
	throw "Worker not found at $worker"
}

function Find-LuaJit {
	if ($LuaJit -and (Test-Path $LuaJit)) {
		return (Resolve-Path $LuaJit).Path
	}
	if ($env:LUAJIT -and (Test-Path $env:LUAJIT)) {
		return $env:LUAJIT
	}
	$local = Join-Path $root "tools\luajit\luajit.exe"
	if (Test-Path $local) {
		return $local
	}
	$cmd = Get-Command luajit -ErrorAction SilentlyContinue
	if ($cmd) {
		return $cmd.Source
	}
	$cmd = Get-Command luajit.exe -ErrorAction SilentlyContinue
	if ($cmd) {
		return $cmd.Source
	}
	return $null
}

$luajitPath = Find-LuaJit
if (-not $luajitPath) {
	Write-Host "LuaJIT introuvable."
	Write-Host "Installe LuaJIT puis relance, ou pose luajit.exe dans tools\luajit\"
	Write-Host "PoB CI utilise l'image ghcr.io/pathofbuildingcommunity/pathofbuilding-tests"
	exit 1
}

$runtimeLua = Join-Path $root "vendor\PathOfBuilding\runtime\lua"
$shims = Join-Path $root "core\pob-engine\shims"
$env:LUA_PATH = "$runtimeLua\?.lua;$runtimeLua\?\init.lua;$shims\?.lua;;"
$env:LUA_CPATH = ";;"

Push-Location $pobSrc
try {
	$workerAbs = (Resolve-Path $worker).Path
	switch ($Command) {
		"evaluate" {
			& $luajitPath $workerAbs evaluate $Class $Ascendancy $Level $Skill
			if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
		}
		"validate" {
			& $luajitPath $workerAbs validate
			if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
		}
		"bench" {
			& $luajitPath $workerAbs bench $BenchCount
			if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
		}
		"rpc" {
			& $luajitPath $workerAbs rpc
			if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
		}
		"optimize" {
			& $luajitPath $workerAbs optimize $Class $Ascendancy $Level $BeamSize
			if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
		}
		"generate" {
			$defPath = $Definition
			if (-not $defPath) {
				$defPath = Join-Path $root "examples\winter-orb.json"
			}
			$defAbs = (Resolve-Path $defPath).Path
			if ($DryRun) {
				& $luajitPath $workerAbs generate $defAbs dry
			} else {
				& $luajitPath $workerAbs generate $defAbs
			}
			if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
		}
		"regress" {
			& $luajitPath $workerAbs regress
			if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
		}
		"ui" {
			$uiServer = Join-Path $root "scripts\ui-server.py"
			$python = Get-Command python -ErrorAction SilentlyContinue
			if (-not $python) {
				throw "Python introuvable. Installe Python 3 pour lancer l'interface."
			}
			& $python.Source $uiServer --luajit $luajitPath --root $root
			if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
		}
	}
}
finally {
	Pop-Location
}
