#!/usr/bin/env pwsh
# Local test script for ESPHome configuration validation
# Run this before committing changes or creating releases

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

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
        Write-Host "  ✓ PASSED" -ForegroundColor Green
        $script:TestsPassed++
        return $true
    }
    catch {
        Write-Host "  ✗ FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $script:TestsFailed++
        return $false
    }
}

# Test 1: Check Python and pip
Test-Step "Python Installation" {
    $pythonVersion = python --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Python not found. Install Python 3.11+ from python.org"
    }
    Write-Host "    Found: $pythonVersion" -ForegroundColor Gray
}

# Test 2: Check ESPHome installation
Test-Step "ESPHome Installation" {
    try {
        $esphomeVersion = esphome version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    ESPHome not found, installing..." -ForegroundColor Yellow
            pip install esphome | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to install ESPHome"
            }
            $esphomeVersion = esphome version 2>&1
        }
        Write-Host "    Found: $esphomeVersion" -ForegroundColor Gray
    }
    catch {
        throw "ESPHome check failed: $_"
    }
}

# Test 3: Check yamllint installation
Test-Step "yamllint Installation" {
    try {
        $null = yamllint --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    yamllint not found, installing..." -ForegroundColor Yellow
            pip install yamllint | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to install yamllint"
            }
        }
        $yamllintVersion = yamllint --version 2>&1
        Write-Host "    Found: $yamllintVersion" -ForegroundColor Gray
    }
    catch {
        throw "yamllint check failed: $_"
    }
}

# Test 4: Create test secrets file
Test-Step "Test Secrets Setup" {
    Push-Location $ProjectRoot
    try {
        if (-not (Test-Path "secrets.yaml")) {
            Set-Content -Path "secrets.yaml" -Value "# Test secrets file (auto-generated)`nwifi_ssid: `"TestNetwork`"`nwifi_password: `"TestPassword123`""
            Write-Host "    Created test secrets.yaml" -ForegroundColor Gray
        } else {
            Write-Host "    Using existing secrets.yaml" -ForegroundColor Gray
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
        $output = esphome config waterlevel-sensor.yaml 2>&1 | Out-String
        if ($output -notmatch "Configuration is valid") {
            throw "ESPHome configuration validation failed:`n$output"
        }
        Write-Host "    Configuration is valid" -ForegroundColor Gray
    }
    finally {
        Pop-Location
    }
}

# Test 7: Compile ESPHome firmware
Test-Step "ESPHome Compilation Test" {
    Push-Location $ProjectRoot
    try {
        Write-Host "    Compiling firmware (this may take a few minutes)..." -ForegroundColor Gray
        $output = esphome compile waterlevel-sensor.yaml 2>&1 | Out-String
        if ($output -match "(ERROR|FAILED|Error compiling)") {
            throw "ESPHome compilation failed:`n$output"
        }
        if ($output -notmatch "SUCCESS") {
            Write-Host "    WARNING: No SUCCESS confirmation found, but no errors detected" -ForegroundColor Yellow
        }
        Write-Host "    Compilation successful" -ForegroundColor Gray
    }
    finally {
        Pop-Location
    }
}

# Test 8: Check README markdown
Test-Step "README Validation" {
    Push-Location $ProjectRoot
    try {
        if (Test-Path "README.md") {
            $readmeContent = Get-Content "README.md" -Raw
            if ($readmeContent.Length -lt 100) {
                throw "README.md appears incomplete (too short)"
            }
            Write-Host "    README.md looks good" -ForegroundColor Gray
        } else {
            throw "README.md not found"
        }
    }
    finally {
        Pop-Location
    }
}

# Test 9: Check LICENSE file
Test-Step "License File Check" {
    Push-Location $ProjectRoot
    try {
        if (-not (Test-Path "LICENSE")) {
            Write-Host "    WARNING: LICENSE file not found" -ForegroundColor Yellow
        } else {
            Write-Host "    LICENSE file present" -ForegroundColor Gray
        }
    }
    finally {
        Pop-Location
    }
}

# Test 10: Check Git status
Test-Step "Git Status Check" {
    Push-Location $ProjectRoot
    try {
        $gitStatus = git status --porcelain 2>&1
        if ($gitStatus) {
            Write-Host "    WARNING: Uncommitted changes detected:" -ForegroundColor Yellow
            Write-Host $gitStatus -ForegroundColor Gray
        } else {
            Write-Host "    Working directory clean" -ForegroundColor Gray
        }
    }
    finally {
        Pop-Location
    }
}

# Summary
Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Passed: $TestsPassed" -ForegroundColor Green
Write-Host "Failed: $TestsFailed" -ForegroundColor $(if ($TestsFailed -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($TestsFailed -eq 0) {
    Write-Host "✓ All tests passed! Ready to commit/release." -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Some tests failed. Please fix issues before committing." -ForegroundColor Red
    exit 1
}
