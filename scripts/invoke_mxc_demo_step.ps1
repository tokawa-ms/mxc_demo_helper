[CmdletBinding(DefaultParameterSetName = "Run")]
param(
    [Parameter(ParameterSetName = "Run")]
    [ValidateSet(
        "preflight",
        "baseline-network",
        "network-open",
        "network-block",
        "filesystem-setup",
        "filesystem-readwrite",
        "filesystem-readonly"
    )]
    [string]$Demo,

    [Parameter(ParameterSetName = "Status")]
    [switch]$StatusJson,

    [string]$RepoPath = "C:\mxc-demo\mxc",
    [string]$ConfigDirectory = "",
    [string]$VcVarsPath = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)

if (-not $ConfigDirectory) {
    $ConfigDirectory = Join-Path (Split-Path -Parent $PSScriptRoot) "mxc-profiles"
}

$demoRoot = "C:\mxc-demo-fs"
$networkHost = "www.msftconnecttest.com"
$networkPort = 80
$wxcExec = Join-Path $RepoPath "sdk\bin\x64\wxc-exec.exe"

function Write-Step {
    param([string]$Message)

    Write-Host ""
    Write-Host "==> $Message"
}

function Format-WindowsExitCode {
    param([int]$ExitCode)

    $unsigned = [int64]$ExitCode
    if ($unsigned -lt 0) {
        $unsigned += 0x100000000
    }

    return "0x{0:X8}" -f $unsigned
}

function Resolve-VcVarsPath {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath)) {
            throw "The specified vcvars64.bat was not found: $ExplicitPath"
        }

        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $candidates = New-Object System.Collections.Generic.List[string]
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        $installPaths = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        foreach ($installPath in $installPaths) {
            if ($installPath) {
                $candidates.Add((Join-Path $installPath "VC\Auxiliary\Build\vcvars64.bat"))
            }
        }
    }

    foreach ($candidate in @(
            "C:\Program Files\Microsoft Visual Studio\18\Enterprise\VC\Auxiliary\Build\vcvars64.bat",
            "C:\Program Files\Microsoft Visual Studio\18\Preview\VC\Auxiliary\Build\vcvars64.bat",
            "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat",
            "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat",
            "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat",
            "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
        )) {
        $candidates.Add($candidate)
    }

    $vcvars = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $vcvars) {
        throw "vcvars64.bat was not found. Install Visual Studio C++ x64 tools, or specify -VcVarsPath."
    }

    return $vcvars
}

function Test-IsAdministrator {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-ProfilePath {
    param([string]$Name)

    $path = Join-Path $ConfigDirectory $Name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "MXC profile was not found: $path"
    }

    return $path
}

function Test-WxcExecLaunch {
    param([string]$VcVars)

    if (-not (Test-Path -LiteralPath $wxcExec)) {
        throw "wxc-exec.exe was not found. Build MXC first: $wxcExec"
    }

    Write-Step "Verifying that wxc-exec.exe can start"
    $sdkBin = Split-Path -Parent $wxcExec
    $cmd = "call `"$VcVars`" >nul && set PATH=$sdkBin;%PATH% && cd /d `"$RepoPath`" && `"$wxcExec`" --help >nul"
    & $env:ComSpec /d /c $cmd
    if ($LASTEXITCODE -ne 0) {
        throw "wxc-exec.exe --help failed. ExitCode=$LASTEXITCODE ($(Format-WindowsExitCode -ExitCode $LASTEXITCODE))"
    }

    Write-Host "OK: wxc-exec.exe launched successfully."
}

function Test-TcpConnectivity {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutMilliseconds = 10000
    )

    $client = [Net.Sockets.TcpClient]::new()
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        if ((-not $task.Wait($TimeoutMilliseconds)) -or (-not $client.Connected)) {
            throw "TCP connect timed out: ${HostName}:$Port"
        }

        Write-Host "OK: TCP ${HostName}:$Port connected"
    }
    finally {
        $client.Dispose()
    }
}

function Initialize-FilesystemDemo {
    $allowed = Join-Path $demoRoot "allowed"
    $readonly = Join-Path $demoRoot "readonly"

    New-Item -ItemType Directory -Force -Path $allowed, $readonly | Out-Null
    "allowed input from VM" | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $allowed "input.txt")
    "readonly input from VM" | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $readonly "input.txt")

    foreach ($path in @(
            (Join-Path $allowed "output-from-mxc.txt"),
            (Join-Path $readonly "write-should-fail.txt")
        )) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }

    Get-ChildItem -LiteralPath $demoRoot -Recurse | Select-Object FullName, Length | Format-Table -AutoSize
}

function Invoke-WxcProfile {
    param(
        [string]$ProfilePath,
        [string]$Description,
        [string]$VcVars
    )

    if (-not (Test-Path -LiteralPath $wxcExec)) {
        throw "wxc-exec.exe was not found. Build MXC first: $wxcExec"
    }

    Write-Step $Description
    $sdkBin = Split-Path -Parent $wxcExec
    $profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    Write-Host "MXC command:"
    Write-Host "  `"$wxcExec`" `"$ProfilePath`""
    Write-Host "Profile process.commandLine:"
    Write-Host "  $($profile.process.commandLine)"

    $cmd = "call `"$VcVars`" >nul && set PATH=$sdkBin;%PATH% && cd /d `"$RepoPath`" && `"$wxcExec`" `"$ProfilePath`""
    & $env:ComSpec /d /c $cmd
    if ($LASTEXITCODE -ne 0) {
        throw "MXC profile failed with exit code $LASTEXITCODE ($(Format-WindowsExitCode -ExitCode $LASTEXITCODE)): $ProfilePath"
    }
}

function Write-DemoHeader {
    param(
        [string]$Title,
        [string]$Summary
    )

    Write-Host ""
    Write-Host "======================================================================"
    Write-Host "DEMO: $Title"
    Write-Host $Summary
    Write-Host "======================================================================"
}

function Get-StatusObject {
    $profileNames = @(
        "network-open-microsoft.json",
        "network-block-microsoft.json",
        "filesystem-readwrite-allowed.json",
        "filesystem-readonly-deny-write.json"
    )

    $vcvars = $null
    $vcvarsError = $null
    try {
        $vcvars = Resolve-VcVarsPath -ExplicitPath $VcVarsPath
    }
    catch {
        $vcvarsError = $_.Exception.Message
    }

    return [ordered]@{
        repoPath        = $RepoPath
        configDirectory = $ConfigDirectory
        demoRoot        = $demoRoot
        wxcExec         = [ordered]@{
            path   = $wxcExec
            exists = Test-Path -LiteralPath $wxcExec
        }
        vcvars          = [ordered]@{
            path  = $vcvars
            found = [bool]$vcvars
            error = $vcvarsError
        }
        administrator   = Test-IsAdministrator
        profiles        = @($profileNames | ForEach-Object {
                $profilePath = Join-Path $ConfigDirectory $_
                [ordered]@{
                    name   = $_
                    path   = $profilePath
                    exists = Test-Path -LiteralPath $profilePath
                }
            })
    }
}

if ($StatusJson) {
    Get-StatusObject | ConvertTo-Json -Depth 6
    exit 0
}

if (-not $Demo) {
    throw "Specify -Demo or -StatusJson."
}

$vcvars = Resolve-VcVarsPath -ExplicitPath $VcVarsPath
Write-Host "RepoPath: $RepoPath"
Write-Host "ConfigDirectory: $ConfigDirectory"
Write-Host "DemoRoot: $demoRoot"
Write-Host "vcvars64.bat: $vcvars"

switch ($Demo) {
    "preflight" {
        Write-DemoHeader -Title "Preflight" -Summary "Verify wxc-exec.exe and the Visual Studio environment before running MXC profiles."
        Test-WxcExecLaunch -VcVars $vcvars
    }
    "baseline-network" {
        Write-DemoHeader -Title "Baseline network check" -Summary "Verify host VM TCP connectivity outside MXC."
        Write-Step "Connecting to ${networkHost}:$networkPort from normal PowerShell"
        Test-TcpConnectivity -HostName $networkHost -Port $networkPort
    }
    "network-open" {
        Write-DemoHeader -Title "Network open profile" -Summary "Verify that internetClient allows outbound network access from inside MXC."
        Invoke-WxcProfile -ProfilePath (Get-ProfilePath "network-open-microsoft.json") -Description "Running network open profile" -VcVars $vcvars
    }
    "network-block" {
        Write-DemoHeader -Title "Network block profile" -Summary "Verify that network.defaultPolicy=block prevents outbound access from inside MXC."
        if (-not (Test-IsAdministrator)) {
            Write-Warning "Network block uses Windows Firewall enforcement. Run the Node server from an elevated PowerShell for the most reliable result."
        }
        Invoke-WxcProfile -ProfilePath (Get-ProfilePath "network-block-microsoft.json") -Description "Running network block profile" -VcVars $vcvars
    }
    "filesystem-setup" {
        Write-DemoHeader -Title "Filesystem setup" -Summary "Prepare allowed and readonly folders for the filesystem demos."
        Write-Step "Preparing $demoRoot"
        Initialize-FilesystemDemo
    }
    "filesystem-readwrite" {
        Write-DemoHeader -Title "Filesystem read/write profile" -Summary "Verify that readwritePaths allows reading input and creating output."
        Invoke-WxcProfile -ProfilePath (Get-ProfilePath "filesystem-readwrite-allowed.json") -Description "Running filesystem read/write profile" -VcVars $vcvars
        $allowedOutput = Join-Path $demoRoot "allowed\output-from-mxc.txt"
        if (-not (Test-Path -LiteralPath $allowedOutput)) {
            throw "The readwritePaths demo output file was not created: $allowedOutput"
        }
        Write-Host "Host verification: expected output file exists: $allowedOutput"
        Write-Host "Host verification: output file content:"
        Get-Content -LiteralPath $allowedOutput
    }
    "filesystem-readonly" {
        Write-DemoHeader -Title "Filesystem readonly profile" -Summary "Verify that readonlyPaths can be read but cannot be written."
        Invoke-WxcProfile -ProfilePath (Get-ProfilePath "filesystem-readonly-deny-write.json") -Description "Running filesystem readonly profile" -VcVars $vcvars
        $readonlyUnexpectedOutput = Join-Path $demoRoot "readonly\write-should-fail.txt"
        if (Test-Path -LiteralPath $readonlyUnexpectedOutput) {
            throw "The readonlyPaths demo unexpectedly allowed a write: $readonlyUnexpectedOutput"
        }
        Write-Host "OK: no write side effect remains under readonlyPaths."
    }
}

Write-Host ""
Write-Host "Demo step completed: $Demo"