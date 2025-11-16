#!/usr/bin/env pwsh
# Local test script for ESPHome configuration validation
# Run this before committing changes or creating releases

$ErrorActionPreference = "Stop"
# Determine project root – handle script located in scripts/ and stdin pipe scenarios
$ProjectRoot = $null
if ($MyInvocation.MyCommand.Path) {
	$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
	if (Test-Path (Join-Path $ScriptDir 'waterlevel-sensor.yaml')) {
		$ProjectRoot = $ScriptDir
	} elseif (Test-Path (Join-Path $ScriptDir '..\waterlevel-sensor.yaml')) {
		$ProjectRoot = Resolve-Path (Join-Path $ScriptDir '..')
	} else {
		$ProjectRoot = $ScriptDir
	}
} else {
	$Cwd = Get-Location
	if (Test-Path (Join-Path $Cwd 'waterlevel-sensor.yaml')) {
		$ProjectRoot = $Cwd
	} elseif (Test-Path (Join-Path $Cwd '..\waterlevel-sensor.yaml')) {
		$ProjectRoot = Resolve-Path (Join-Path $Cwd '..')
	} else {
		$ProjectRoot = $Cwd
	}
}

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "ESPHome Local Test Suite" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Track test results
$TestsPassed = 0
$TestsFailed = 0

function Test-Step {
	param(
		[string]$Name,
		[scriptblock]$Action
	)
	
	Write-Host "[$Name]" -ForegroundColor Yellow -NoNewline
	Write-Host " Running..." -ForegroundColor Gray
	
	try {
		& $Action
		Write-Host "  PASSED" -ForegroundColor Green
		$script:TestsPassed++
		return $true
	}
	catch {
		Write-Host "  FAILED: $_" -ForegroundColor Red
		$script:TestsFailed++
		return $false
	}
	finally {
		Write-Host ""
	}
}

# Test 1: Check Python installation
Test-Step "Python Installation" {
	$pythonVersion = python --version 2>&1
	if ($LASTEXITCODE -ne 0) {
		throw "Python not found. Please install Python 3.8 or higher."
	}
	Write-Host "    Found: $pythonVersion" -ForegroundColor Gray
}

# Test 2: Check ESPHome installation
Test-Step "ESPHome Installation" {
	$esphomeVersion = esphome version 2>&1
	if ($LASTEXITCODE -ne 0) {
		throw "ESPHome not found. Install with: pip install esphome"
	}
	Write-Host "    Found: $esphomeVersion" -ForegroundColor Gray
}

# Test 3: Check yamllint installation
Test-Step "yamllint Installation" {
	Push-Location $ProjectRoot
	try {
		$yamllintVersion = yamllint --version 2>&1
		if ($LASTEXITCODE -ne 0) {
			Write-Host "    yamllint not found, installing..." -ForegroundColor Yellow
			pip install yamllint
			$yamllintVersion = yamllint --version 2>&1
		}
		Write-Host "    Found: $yamllintVersion" -ForegroundColor Gray
	}
	catch {
		throw "yamllint check failed: $_"
	}
	finally {
		Pop-Location
	}
}

# Test 4: Create test secrets file
Test-Step "Test Secrets Setup" {
	Push-Location $ProjectRoot
	try {
		if (-not (Test-Path "secrets.yaml")) {
			$content = @'
# Test secrets file (auto-generated)
wifi_ssid: "TestNetwork"
wifi_password: "TestPassword123"
ap_password: "TestApPassword123"
'@
			$content | Set-Content -Path "secrets.yaml" -Encoding UTF8
			Write-Host "    Created test secrets.yaml" -ForegroundColor Gray
		} else {
			# Ensure ap_password exists for fallback AP
			$existing = Get-Content -Path "secrets.yaml" -ErrorAction SilentlyContinue | Out-String
			if ($existing -notmatch "(?m)^\s*ap_password:\s*") {
				Add-Content -Path "secrets.yaml" -Value ""
				Add-Content -Path "secrets.yaml" -Value 'ap_password: "TestApPassword123"'
				Write-Host "    Added ap_password to existing secrets.yaml" -ForegroundColor Gray
			} else {
				Write-Host "    Using existing secrets.yaml" -ForegroundColor Gray
			}
		}
	}
	finally {
		Pop-Location
	}
}

# Test 5: Validate YAML syntax
Test-Step "YAML Linting" {
	Push-Location $ProjectRoot
	try {
		$output = yamllint -d "{extends: relaxed, rules: {line-length: {max: 120}, new-lines: disable}}" waterlevel-sensor.yaml 2>&1
		if ($LASTEXITCODE -ne 0) {
			throw "YAML linting failed:`n$output"
		}
		Write-Host "    No YAML syntax errors found" -ForegroundColor Gray
	}
	finally {
		Pop-Location
	}
}

# Test 6: Validate ESPHome configuration
Test-Step "ESPHome Config Validation" {
	Push-Location $ProjectRoot
	try {
		Write-Host "    Validating configuration..." -ForegroundColor Gray
		$null = esphome config waterlevel-sensor.yaml
		$exit = $LASTEXITCODE
		if ($exit -eq 0) {
			Write-Host "    Configuration validated successfully" -ForegroundColor Gray
		} else {
			# Re-run to capture output for diagnostics
			$output = esphome config waterlevel-sensor.yaml 2>&1 | Out-String
			throw "ESPHome configuration failed (exit code $exit):`n$output"
		}
	}
	finally {
		Pop-Location
	}
}

# Test 7: Compile ESPHome firmware (skipped by default for speed)
Test-Step "ESPHome Compilation Test" {
	Push-Location $ProjectRoot
	try {
		Write-Host "    Compiling firmware (this may take a few minutes)..." -ForegroundColor Gray
		Write-Host "    (Skipping compilation - takes several minutes and is validated in CI)" -ForegroundColor Gray
		Write-Host "    To run full compilation locally, use: esphome compile waterlevel-sensor.yaml" -ForegroundColor Yellow
	}
	finally {
		Pop-Location
	}
}

# Test 8: Check README exists and is not empty
Test-Step "README Validation" {
	Push-Location $ProjectRoot
	try {
		if (-not (Test-Path "README.md")) {
			throw "README.md not found"
		}
		$readmeSize = (Get-Item "README.md").Length
		if ($readmeSize -lt 100) {
			throw "README.md is too small (less than 100 bytes)"
		}
		Write-Host "    README.md looks good" -ForegroundColor Gray
	}
	finally {
		Pop-Location
	}
}

# Test 9: Check LICENSE file exists
Test-Step "License File Check" {
	Push-Location $ProjectRoot
	try {
		if (-not (Test-Path "LICENSE")) {
			throw "LICENSE file not found"
		}
		Write-Host "    LICENSE file present" -ForegroundColor Gray
	}
	finally {
		Pop-Location
	}
}

# Test 10: Check for uncommitted changes
Test-Step "Git Status Check" {
	Push-Location $ProjectRoot
	try {
		$gitStatus = git status --porcelain 2>&1
		if ($gitStatus) {
			Write-Host "    WARNING: Uncommitted changes detected:" -ForegroundColor Yellow
			Write-Host "$gitStatus" -ForegroundColor Yellow
		} else {
			Write-Host "    Git working directory is clean" -ForegroundColor Gray
		}
	}
	finally {
		Pop-Location
	}
}

# Print summary
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Passed: $TestsPassed" -ForegroundColor Green
Write-Host "Failed: $TestsFailed" -ForegroundColor Red

if ($TestsFailed -gt 0) {
	exit 1
} else {
	exit 0
}
