[CmdletBinding()]
param(
    [string]$RepoPath = "C:\mxc-demo\mxc",
    [string]$ConfigDirectory = (Join-Path $PSScriptRoot "mxc-profiles"),
    [string]$VcVarsPath = "",
    [switch]$SkipNetworkBlock,
    [switch]$SkipFilesystemDemo
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)

    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-DemoSeparator {
    param(
        [string]$Title,
        [string]$Summary
    )

    Write-Host ""
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Magenta
    Write-Host " DEMO: $Title" -ForegroundColor Magenta
    if ($Summary) {
        Write-Host " $Summary" -ForegroundColor DarkGray
    }
    Write-Host "======================================================================" -ForegroundColor Magenta
}

function Invoke-WxcProfile {
    param(
        [string]$WxcExecPath,
        [string]$ProfilePath,
        [string]$Description,
        [string]$WorkingDirectory,
        [string]$VcVars
    )

    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        throw "MXC profile が見つかりません: $ProfilePath"
    }

    Write-Step $Description
    $sdkBin = Split-Path -Parent $WxcExecPath
    $profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    Write-Host "MXC command:"
    Write-Host "  `"$WxcExecPath`" `"$ProfilePath`"" -ForegroundColor DarkGray
    Write-Host "Profile process.commandLine:"
    Write-Host "  $($profile.process.commandLine)" -ForegroundColor DarkGray
    $cmd = "call `"$VcVars`" >nul && set PATH=$sdkBin;%PATH% && cd /d `"$WorkingDirectory`" && `"$WxcExecPath`" `"$ProfilePath`""
    & $env:ComSpec /d /c $cmd
    if ($LASTEXITCODE -ne 0) {
        $hexExitCode = Format-WindowsExitCode -ExitCode $LASTEXITCODE
        $hint = if ($LASTEXITCODE -eq -1073741515) {
            " DLL が見つからないエラーです。先に `"$WxcExecPath --help`" も失敗する場合は、Visual Studio の C++ workload、VC++ Redistributable、または MXC build output の DLL 配置を確認してください。"
        } else {
            ""
        }
        throw "MXC profile failed with exit code ${LASTEXITCODE} ($hexExitCode): $ProfilePath.$hint"
    }
}

function Format-WindowsExitCode {
    param([int]$ExitCode)

    $unsigned = [int64]$ExitCode
    if ($unsigned -lt 0) {
        $unsigned += 0x100000000
    }

    return "0x{0:X8}" -f $unsigned
}

function Test-WxcExecLaunch {
    param(
        [string]$WxcExecPath,
        [string]$WorkingDirectory,
        [string]$VcVars
    )

    Write-Step "wxc-exec.exe が起動できることを確認しています"
    $sdkBin = Split-Path -Parent $WxcExecPath
    $cmd = "call `"$VcVars`" >nul && set PATH=$sdkBin;%PATH% && cd /d `"$WorkingDirectory`" && `"$WxcExecPath`" --help >nul"
    & $env:ComSpec /d /c $cmd
    if ($LASTEXITCODE -ne 0) {
        $hexExitCode = Format-WindowsExitCode -ExitCode $LASTEXITCODE
        $hint = if ($LASTEXITCODE -eq -1073741515) {
            "wxc-exec.exe の起動に必要な DLL が見つかっていません。Visual Studio Installer で Desktop development with C++ / MSVC x64 tools / Windows SDK が入っているか確認し、必要に応じて VC++ Redistributable x64 を入れてください。"
        } else {
            "wxc-exec.exe --help が失敗しました。"
        }
        throw "$hint ExitCode=${LASTEXITCODE} ($hexExitCode)"
    }
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

        Write-Host "OK: TCP ${HostName}:$Port connected" -ForegroundColor Green
    } finally {
        $client.Dispose()
    }
}

function Write-DemoDetails {
    param(
        [string]$Title,
        [string]$ProfilePath,
        [string[]]$AccessPolicy,
        [string[]]$AttemptedAccess,
        [string]$ExpectedResult
    )

    Write-Host ""
    Write-Host "---- Demo details: $Title ----" -ForegroundColor Yellow
    Write-Host "Profile: $ProfilePath"
    Write-Host "Access policy:"
    foreach ($item in $AccessPolicy) {
        Write-Host "  - $item"
    }

    Write-Host "This demo will try:"
    foreach ($item in $AttemptedAccess) {
        Write-Host "  - $item"
    }

    Write-Host "Expected result: $ExpectedResult"
    Write-Host "----------------------------------------" -ForegroundColor Yellow
}

function Resolve-VcVarsPath {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath)) {
            throw "指定された vcvars64.bat が見つかりません: $ExplicitPath"
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
        throw "vcvars64.bat が見つかりません。Visual Studio / Build Tools の C++ x64 tools をインストールするか、-VcVarsPath を指定してください。"
    }

    return $vcvars
}

function Test-IsAdministrator {
    $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-FilesystemDemo {
    param([string]$Root)

    $allowed = Join-Path $Root "allowed"
    $readonly = Join-Path $Root "readonly"

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

    Get-ChildItem -LiteralPath $Root -Recurse | Select-Object FullName, Length
}

$demoRoot = "C:\mxc-demo-fs"
$wxcExec = Join-Path $RepoPath "sdk\bin\x64\wxc-exec.exe"
if (-not (Test-Path -LiteralPath $wxcExec)) {
    throw "wxc-exec.exe が見つかりません。先に build_mxc_windows.ps1 で MXC をビルドしてください: $wxcExec"
}

$vcvars = Resolve-VcVarsPath -ExplicitPath $VcVarsPath

$networkOpenProfile = Join-Path $ConfigDirectory "network-open-microsoft.json"
$networkBlockProfile = Join-Path $ConfigDirectory "network-block-microsoft.json"
$filesystemAllowProfile = Join-Path $ConfigDirectory "filesystem-readwrite-allowed.json"
$filesystemReadonlyProfile = Join-Path $ConfigDirectory "filesystem-readonly-deny-write.json"
$networkHost = "www.msftconnecttest.com"
$networkPort = 80

Write-Host "MXC demo runner"
Write-Host "RepoPath: $RepoPath"
Write-Host "ConfigDirectory: $ConfigDirectory"
Write-Host "DemoRoot: $demoRoot"
Write-Host "vcvars64.bat: $vcvars"

Test-WxcExecLaunch -WxcExecPath $wxcExec -WorkingDirectory $RepoPath -VcVars $vcvars

Write-DemoSeparator -Title "Baseline network check" -Summary "MXC の外側で VM 自体のネットワーク到達性を確認します"
Write-Step "VM 通常 PowerShell から ${networkHost}:${networkPort} に TCP 接続できることを確認しています"
Write-Host "目的: MXC の外側、つまり通常の VM 環境ではネットワーク到達性があることを先に確認します。"
Write-Host "試行: ${networkHost}:${networkPort} へ TCP connect"
Write-Host "期待: 接続成功。ここが失敗する場合は MXC ではなく VM/Proxy/Firewall 側の問題です。"
Test-TcpConnectivity -HostName $networkHost -Port $networkPort

Write-DemoSeparator -Title "Network open profile" -Summary "internetClient capability により MXC 内から外部ネットワークへ接続できることを確認します"
Write-DemoDetails `
    -Title "Network open" `
    -ProfilePath $networkOpenProfile `
    -AccessPolicy @(
        "processContainer.capabilities: internetClient を付与",
        "network.defaultPolicy は未指定のため、通常の outbound ネットワークを許可"
    ) `
    -AttemptedAccess @(
        "C:\Windows\System32\curl.exe を MXC 内で起動",
        "HTTP HEAD: http://${networkHost}/connecttest.txt",
        "TCP destination: ${networkHost}:${networkPort}"
    ) `
    -ExpectedResult "curl が HTTP response header を取得し、MXC 内からの network access が成功する"

Invoke-WxcProfile `
    -WxcExecPath $wxcExec `
    -ProfilePath $networkOpenProfile `
    -Description "MXC network open profile で ${networkHost}:${networkPort} に TCP 接続できることを確認しています" `
    -WorkingDirectory $RepoPath `
    -VcVars $vcvars

if (-not $SkipNetworkBlock) {
    Write-DemoSeparator -Title "Network block profile" -Summary "network.defaultPolicy=block により MXC 内から外部ネットワークへ接続できないことを確認します"
    if (-not (Test-IsAdministrator)) {
        Write-Warning "network block profile は Windows Firewall enforcement を使うため、ゲスト VM 内の管理者 PowerShell での実行を推奨します。"
    }

    Write-DemoDetails `
        -Title "Network block" `
        -ProfilePath $networkBlockProfile `
        -AccessPolicy @(
            "processContainer.capabilities: internetClient を付与",
            "network.defaultPolicy: block",
            "network.enforcementMode: firewall",
            "明示 allow rule は未設定"
        ) `
        -AttemptedAccess @(
            "C:\Windows\System32\curl.exe を MXC 内で起動",
            "HTTP HEAD: http://${networkHost}/connecttest.txt",
            "TCP destination: ${networkHost}:${networkPort}"
        ) `
        -ExpectedResult "curl がアクセス拒否または接続失敗になり、block が効いていることを確認する"

    Invoke-WxcProfile `
        -WxcExecPath $wxcExec `
        -ProfilePath $networkBlockProfile `
        -Description "MXC network block profile で ${networkHost}:${networkPort} に TCP 接続できないことを確認しています" `
        -WorkingDirectory $RepoPath `
        -VcVars $vcvars
} else {
    Write-Step "network block demo をスキップしました"
}

if (-not $SkipFilesystemDemo) {
    Write-DemoSeparator -Title "Filesystem setup" -Summary "read/write と readonly の比較用ディレクトリと入力ファイルを準備します"
    Write-Step "filesystem demo 用ディレクトリを準備しています"
    Initialize-FilesystemDemo -Root $demoRoot

    $allowedPath = Join-Path $demoRoot "allowed"
    $readonlyPath = Join-Path $demoRoot "readonly"
    Write-DemoSeparator -Title "Filesystem read/write profile" -Summary "readwritePaths 配下の読み取りと書き込みが成功することを確認します"
    Write-DemoDetails `
        -Title "Filesystem read/write allowed" `
        -ProfilePath $filesystemAllowProfile `
        -AccessPolicy @(
            "filesystem.readwritePaths: $allowedPath",
            "readonlyPaths は未指定",
            "この profile では allowed 配下のみを読み書き対象にする"
        ) `
        -AttemptedAccess @(
            "READ: $allowedPath\input.txt",
            "WRITE: $allowedPath\output-from-mxc.txt"
        ) `
        -ExpectedResult "input.txt の読み取りと output-from-mxc.txt の作成がどちらも成功する"

    Invoke-WxcProfile `
        -WxcExecPath $wxcExec `
        -ProfilePath $filesystemAllowProfile `
        -Description "MXC から readwritePaths の allowed ディレクトリを読み書きできることを確認しています" `
        -WorkingDirectory $RepoPath `
        -VcVars $vcvars

    $allowedOutput = Join-Path $demoRoot "allowed\output-from-mxc.txt"
    if (-not (Test-Path -LiteralPath $allowedOutput)) {
        throw "readwritePaths demo の出力ファイルが作成されていません: $allowedOutput"
    }
    Write-Host "Host verification: expected output file exists: $allowedOutput" -ForegroundColor Green
    Write-Host "Host verification: output file content:"
    Get-Content -LiteralPath $allowedOutput

    Write-DemoSeparator -Title "Filesystem readonly profile" -Summary "readonlyPaths 配下は読めるが書き込めないことを確認します"
    Write-DemoDetails `
        -Title "Filesystem readonly denies write" `
        -ProfilePath $filesystemReadonlyProfile `
        -AccessPolicy @(
            "filesystem.readwritePaths: $allowedPath",
            "filesystem.readonlyPaths: $readonlyPath",
            "allowed は読み書き可能、readonly は読み取りのみ可能"
        ) `
        -AttemptedAccess @(
            "READ: $allowedPath\input.txt",
            "READ: $readonlyPath\input.txt",
            "WRITE: $readonlyPath\write-should-fail.txt"
        ) `
        -ExpectedResult "2 つの read は成功し、readonly 配下への write は失敗する"

    Invoke-WxcProfile `
        -WxcExecPath $wxcExec `
        -ProfilePath $filesystemReadonlyProfile `
        -Description "MXC から readonlyPaths を読めるが書き込めないことを確認しています" `
        -WorkingDirectory $RepoPath `
        -VcVars $vcvars

    $readonlyUnexpectedOutput = Join-Path $demoRoot "readonly\write-should-fail.txt"
    if (Test-Path -LiteralPath $readonlyUnexpectedOutput) {
        throw "readonlyPaths demo で書き込みが成功してしまいました: $readonlyUnexpectedOutput"
    }
    Write-Host "OK: readonlyPaths への書き込み副作用は残っていません。" -ForegroundColor Green
} else {
    Write-Step "filesystem demo をスキップしました"
}

Write-Host ""
Write-Host "MXC demo completed." -ForegroundColor Green
