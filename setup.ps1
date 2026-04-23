#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Workstation As Code
    Description: Automated environment provisioning using a data-driven approach.
    Author: Ulrich Steve Noumsi
#>

# Force working directory to script location
Set-Location $PSScriptRoot

$DATA_DIR = "data"
$LOG_DIR  = "logs"
$LOG_FILE = "$LOG_DIR/setup_$(Get-Date -Format 'yyyyMMdd_HHmm').log"

if (!(Test-Path $LOG_DIR)) { New-Item -ItemType Directory -Path $LOG_DIR | Out-Null }

function Write-Log([string]$Msg, [string]$Color = "White") {
    $Timestamp = Get-Date -Format "HH:mm:ss"
    $Line = "[$Timestamp] $Msg"
    Write-Host $Line -ForegroundColor $Color
    $Line | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
}

# Refresh environment variables without restarting the shell
function Refresh-Session {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Explicitly add VS Code bin dir in case it was just installed by Winget
    $VsCodeBin = "$env:LocalAppData\Programs\Microsoft VS Code\bin"
    if ((Test-Path $VsCodeBin) -and ($env:Path -notlike "*$VsCodeBin*")) {
        $env:Path += ";$VsCodeBin"
    }
}

# Resolve the winget executable path
function Get-WingetPath {
    $WingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($WingetCmd) { return $WingetCmd.Source }

    $Candidates = @(
        "$env:LocalAppData\Microsoft\WindowsApps\winget.exe",
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    )
    foreach ($Path in $Candidates) {
        $Resolved = Resolve-Path $Path -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty Path -First 1
        if ($Resolved) { return $Resolved }
    }

    Write-Log "winget executable not found." "Red"
    return $null
}

# Resolve the VS Code CLI path
function Get-VsCodePath {
    $CodeCmd = Get-Command code -ErrorAction SilentlyContinue
    if ($CodeCmd) { return $CodeCmd.Source }

    $Candidates = @(
        "$env:LocalAppData\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:ProgramFiles\Microsoft VS Code\bin\code.cmd"
    )
    foreach ($Path in $Candidates) {
        if (Test-Path $Path) { return $Path }
    }

    return $null
}

Write-Log "=== STARTING INFRASTRUCTURE SETUP ===" "Cyan"

# Chocolatey bootstrap
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Log "Chocolatey not detected. Installing..." "Yellow"
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
        'https://community.chocolatey.org/install.ps1'))
    Refresh-Session
}

# Core installation engine
function Start-InstallationEngine([string]$FileName, [string]$ManagerType) {
    $FilePath = "$DATA_DIR/$FileName"
    if (-not (Test-Path $FilePath)) {
        Write-Log "Data file not found: $FilePath" "Yellow"
        return
    }

    Write-Log "--- Module: $ManagerType ---" "Cyan"
    $Lines = Get-Content $FilePath | Where-Object { $_ -and -not $_.StartsWith("#") }

    foreach ($Line in $Lines) {
        $Parts = $Line -split ":"

        $Id = $Parts[0].Trim()

        # Treat empty or whitespace-only version as "latest"
        $Ver = if ($Parts.Count -gt 1 -and $Parts[1].Trim() -ne "") {
            $Parts[1].Trim()
        } else {
            "latest"
        }

        if ([string]::IsNullOrWhiteSpace($Id)) { continue }

        Write-Log "Processing: $Id (Target Version: $Ver)" "Gray"

        try {
            switch ($ManagerType) {

                "Choco" {
                    if ($Ver -eq "latest") {
                        choco upgrade $Id -y --no-progress
                    } else {
                        choco upgrade $Id --version $Ver -y --no-progress
                    }
                }

                "Winget" {
                    $WingetExe = Get-WingetPath
                    if (-not $WingetExe) {
                        Write-Log "winget not available -- skipping: $Id" "Red"
                        continue
                    }

                    $BaseArgs = @(
                        "install", "--id", $Id,
                        "-e", "--silent",
                        "--accept-package-agreements",
                        "--accept-source-agreements"
                    )

                    if ($Ver -ne "latest") {
                        $BaseArgs += @("--version", $Ver)
                    }

                    & $WingetExe @BaseArgs
                }

                "VSCode" {
                    $CodeExe = Get-VsCodePath
                    if ($CodeExe) {
                        & $CodeExe --install-extension $Id --force
                    } else {
                        Write-Log "VS Code not found -- skipping extension: $Id" "Red"
                    }
                }
            }

            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                Write-Log "Warning: $Id exited with code $LASTEXITCODE" "Yellow"
            }

        } catch {
            Write-Log "Error installing: $Id -- $($_.Exception.Message)" "Red"
        }
    }
}

# Run modules
Start-InstallationEngine -FileName "choco_tools.txt" -ManagerType "Choco"
Refresh-Session

Start-InstallationEngine -FileName "winget_tools.txt" -ManagerType "Winget"
Refresh-Session

Start-InstallationEngine -FileName "vscode_ext.txt"  -ManagerType "VSCode"

Write-Log "=== SETUP COMPLETED SUCCESSFULLY ===" "Green"
pause