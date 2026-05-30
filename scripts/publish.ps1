# --- Colors (ANSI Escape Codes) ---
$E      = [char]27
$Bold   = "$E[1m"
$Reset  = "$E[0m"
$Cyan   = "$E[36m"
$Green  = "$E[32m"
$Red    = "$E[31m"
$Gray   = "$E[90m"

$Width = 41

# --- Helpers ---
function Write-Box
{
	param([string]$Text, [string]$Color = $Cyan)
	$inner = $Width - 2
	$pad   = $inner - $Text.Length
	$left  = [math]::Floor($pad / 2)
	$right = $pad - $left
	Write-Host "${Bold}${Color}╭$('─' * $inner)╮${Reset}"
	Write-Host "${Bold}${Color}│$(' ' * $left)$Text$(' ' * $right)│${Reset}"
	Write-Host "${Bold}${Color}╰$('─' * $inner)╯${Reset}"
}

function Invoke-Step
{
	param(
		[int]$Index,
		[int]$Total,
		[string]$Title,
		[scriptblock]$Action
	)
	Write-Host ""
	Write-Host "${Gray}┌─[${Reset}${Bold}${Cyan}$Index/$Total${Reset}${Gray}]─${Reset} ${Bold}$Title${Reset}"
	$sw = [System.Diagnostics.Stopwatch]::StartNew()
	& $Action
	$sw.Stop()
	$t = "$($sw.Elapsed.TotalSeconds.ToString('0.0'))s"
	if ($LASTEXITCODE -ne 0)
	{
		Write-Host "${Gray}└─${Reset} ${Bold}${Red}✖ failed${Reset} ${Gray}($t)${Reset}`n"
		exit 1
	}
	Write-Host "${Gray}└─${Reset} ${Green}✔ ok${Reset} ${Gray}($t)${Reset}"
}

# --- Header ---
Clear-Host
Write-Box "CHRONO PUBLISH PIPELINE"

# --- Environment setup ---
if (Test-Path .env)
{
	Write-Host "`n${Gray}·· loading environment variables from .env${Reset}"
	Get-Content .env | ForEach-Object {
		if ($_ -match "^\s*([^#][^=]+)=(.+)$")
		{
			[Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), "Process")
		}
	}
}

$total = [System.Diagnostics.Stopwatch]::StartNew()

# --- Pipeline ---
Invoke-Step 1 4 "Luau static analysis" {
	& "$PSScriptRoot\analyze.ps1"
}

Invoke-Step 2 4 "lute build" {
	lute build
}

Invoke-Step 3 4 "Wally registry" {
	wally publish
}

Invoke-Step 4 4 "pesde registry" {
	pesde install
	if ($LASTEXITCODE -ne 0)
	{ return
	}
	pesde publish -y
}

$total.Stop()

# --- Final ---
Write-Host ""
Write-Box "PUBLISH COMPLETE" $Green
Write-Host "${Gray}  all registries updated in $($total.Elapsed.TotalSeconds.ToString('0.0'))s${Reset}`n"
