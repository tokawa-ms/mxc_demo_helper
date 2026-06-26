[CmdletBinding()]
param(
    [string]$RepoPath = "C:\mxc-demo\mxc",
    [string]$ConfigDirectory = (Join-Path $PSScriptRoot "mxc-profiles"),
    [string]$VcVarsPath = "",
    [switch]$SkipNetworkBlock,
    [switch]$SkipFilesystemDemo
)

$ErrorActionPreference = "Stop"

function Get-MxcMessageLanguage {
    $cultureName = [System.Globalization.CultureInfo]::CurrentUICulture.Name
    if ($cultureName -eq "ja" -or $cultureName -like "ja-*") {
        return "ja"
    }

    return "en"
}

$script:MxcMessageLanguage = Get-MxcMessageLanguage
$script:MxcMessages = @{
    AccessPolicyLabel = @{
        ja = "アクセスポリシー:"
        en = "Access policy:"
    }
    BaselineNetworkAttempt = @{
        ja = "試行: {0}:{1} へ TCP connect"
        en = "Attempt: TCP connect to {0}:{1}"
    }
    BaselineNetworkExpected = @{
        ja = "期待: 接続成功。ここが失敗する場合は MXC ではなく VM/Proxy/Firewall 側の問題です。"
        en = "Expected: connection succeeds. If this fails, the issue is in the VM, proxy, or firewall rather than MXC."
    }
    BaselineNetworkPurpose = @{
        ja = "目的: MXC の外側、つまり通常の VM 環境ではネットワーク到達性があることを先に確認します。"
        en = "Purpose: first verify that the normal VM environment outside MXC has network connectivity."
    }
    BaselineNetworkStep = @{
        ja = "VM 通常 PowerShell から {0}:{1} に TCP 接続できることを確認しています"
        en = "Verifying TCP connectivity to {0}:{1} from normal VM PowerShell"
    }
    BaselineNetworkSummary = @{
        ja = "MXC の外側で VM 自体のネットワーク到達性を確認します"
        en = "Verify the VM network connectivity outside MXC"
    }
    BaselineNetworkTitle = @{
        ja = "ベースラインネットワーク確認"
        en = "Baseline network check"
    }
    DemoDetailsLabel = @{
        ja = "---- デモ詳細: {0} ----"
        en = "---- Demo details: {0} ----"
    }
    DemoLabel = @{
        ja = " デモ: {0}"
        en = " DEMO: {0}"
    }
    DemoRootLabel = @{
        ja = "DemoRoot: {0}"
        en = "DemoRoot: {0}"
    }
    DllMissingHint = @{
        ja = " DLL が見つからないエラーです。先に `"{0} --help`" も失敗する場合は、Visual Studio の C++ workload、VC++ Redistributable、または MXC build output の DLL 配置を確認してください。"
        en = " This is a missing DLL error. If `"{0} --help`" also fails, check the Visual Studio C++ workload, VC++ Redistributable, or the MXC build output DLL layout."
    }
    ExpectedResultLabel = @{
        ja = "期待結果: {0}"
        en = "Expected result: {0}"
    }
    FilesystemAllowAttemptRead = @{
        ja = "READ: {0}\input.txt"
        en = "READ: {0}\input.txt"
    }
    FilesystemAllowAttemptWrite = @{
        ja = "WRITE: {0}\output-from-mxc.txt"
        en = "WRITE: {0}\output-from-mxc.txt"
    }
    FilesystemAllowExpected = @{
        ja = "input.txt の読み取りと output-from-mxc.txt の作成がどちらも成功する"
        en = "Reading input.txt and creating output-from-mxc.txt both succeed"
    }
    FilesystemAllowPolicyItem1 = @{
        ja = "filesystem.readwritePaths: {0}"
        en = "filesystem.readwritePaths: {0}"
    }
    FilesystemAllowPolicyItem2 = @{
        ja = "readonlyPaths は未指定"
        en = "readonlyPaths is not specified"
    }
    FilesystemAllowPolicyItem3 = @{
        ja = "この profile では allowed 配下のみを読み書き対象にする"
        en = "This profile only allows read/write access under allowed"
    }
    FilesystemAllowProfileStep = @{
        ja = "MXC から readwritePaths の allowed ディレクトリを読み書きできることを確認しています"
        en = "Verifying that MXC can read and write the allowed directory in readwritePaths"
    }
    FilesystemAllowSummary = @{
        ja = "readwritePaths 配下の読み取りと書き込みが成功することを確認します"
        en = "Verify that reads and writes under readwritePaths succeed"
    }
    FilesystemAllowTitle = @{
        ja = "ファイルシステム読み書きプロファイル"
        en = "Filesystem read/write profile"
    }
    FilesystemReadonlyAttemptReadAllowed = @{
        ja = "READ: {0}\input.txt"
        en = "READ: {0}\input.txt"
    }
    FilesystemReadonlyAttemptReadReadonly = @{
        ja = "READ: {0}\input.txt"
        en = "READ: {0}\input.txt"
    }
    FilesystemReadonlyAttemptWrite = @{
        ja = "WRITE: {0}\write-should-fail.txt"
        en = "WRITE: {0}\write-should-fail.txt"
    }
    FilesystemReadonlyExpected = @{
        ja = "2 つの read は成功し、readonly 配下への write は失敗する"
        en = "Both reads succeed, and the write under readonly fails"
    }
    FilesystemReadonlyPolicyItem1 = @{
        ja = "filesystem.readwritePaths: {0}"
        en = "filesystem.readwritePaths: {0}"
    }
    FilesystemReadonlyPolicyItem2 = @{
        ja = "filesystem.readonlyPaths: {0}"
        en = "filesystem.readonlyPaths: {0}"
    }
    FilesystemReadonlyPolicyItem3 = @{
        ja = "allowed は読み書き可能、readonly は読み取りのみ可能"
        en = "allowed is read/write, and readonly is read-only"
    }
    FilesystemReadonlyProfileStep = @{
        ja = "MXC から readonlyPaths を読めるが書き込めないことを確認しています"
        en = "Verifying that MXC can read readonlyPaths but cannot write to them"
    }
    FilesystemReadonlySummary = @{
        ja = "readonlyPaths 配下は読めるが書き込めないことを確認します"
        en = "Verify that readonlyPaths can be read but not written"
    }
    FilesystemReadonlyTitle = @{
        ja = "ファイルシステム読み取り専用プロファイル"
        en = "Filesystem readonly profile"
    }
    FilesystemSetupStep = @{
        ja = "filesystem demo 用ディレクトリを準備しています"
        en = "Preparing directories for the filesystem demo"
    }
    FilesystemSetupSummary = @{
        ja = "read/write と readonly の比較用ディレクトリと入力ファイルを準備します"
        en = "Prepare directories and input files for comparing read/write and readonly behavior"
    }
    FilesystemSetupTitle = @{
        ja = "ファイルシステム準備"
        en = "Filesystem setup"
    }
    HostVerificationContent = @{
        ja = "Host verification: output file content:"
        en = "Host verification: output file content:"
    }
    HostVerificationOutputExists = @{
        ja = "Host verification: expected output file exists: {0}"
        en = "Host verification: expected output file exists: {0}"
    }
    MxcCommandLabel = @{
        ja = "MXC コマンド:"
        en = "MXC command:"
    }
    MxcDemoCompleted = @{
        ja = "MXC demo が完了しました。"
        en = "MXC demo completed."
    }
    MxcDemoRunner = @{
        ja = "MXC デモ runner"
        en = "MXC demo runner"
    }
    MxcProfileFailed = @{
        ja = "MXC profile が終了コード {0} ({1}) で失敗しました: {2}.{3}"
        en = "MXC profile failed with exit code {0} ({1}): {2}.{3}"
    }
    NetworkBlockAttemptCurl = @{
        ja = "C:\Windows\System32\curl.exe を MXC 内で起動"
        en = "Start C:\Windows\System32\curl.exe inside MXC"
    }
    NetworkBlockAttemptHttp = @{
        ja = "HTTP HEAD: http://{0}/connecttest.txt"
        en = "HTTP HEAD: http://{0}/connecttest.txt"
    }
    NetworkBlockAttemptTcp = @{
        ja = "TCP destination: {0}:{1}"
        en = "TCP destination: {0}:{1}"
    }
    NetworkBlockExpected = @{
        ja = "curl がアクセス拒否または接続失敗になり、block が効いていることを確認する"
        en = "curl is denied or fails to connect, confirming that block is effective"
    }
    NetworkBlockPolicyItem1 = @{
        ja = "processContainer.capabilities: internetClient を付与"
        en = "processContainer.capabilities: internetClient is granted"
    }
    NetworkBlockPolicyItem2 = @{
        ja = "network.defaultPolicy: block"
        en = "network.defaultPolicy: block"
    }
    NetworkBlockPolicyItem3 = @{
        ja = "network.enforcementMode: firewall"
        en = "network.enforcementMode: firewall"
    }
    NetworkBlockPolicyItem4 = @{
        ja = "明示 allow rule は未設定"
        en = "No explicit allow rule is configured"
    }
    NetworkBlockProfileStep = @{
        ja = "MXC network block profile で {0}:{1} に TCP 接続できないことを確認しています"
        en = "Verifying that the MXC network block profile cannot connect to {0}:{1}"
    }
    NetworkBlockSkipped = @{
        ja = "network block demo をスキップしました"
        en = "Skipped the network block demo"
    }
    NetworkBlockSummary = @{
        ja = "network.defaultPolicy=block により MXC 内から外部ネットワークへ接続できないことを確認します"
        en = "Verify that network.defaultPolicy=block prevents external network access from inside MXC"
    }
    NetworkBlockTitle = @{
        ja = "ネットワーク遮断プロファイル"
        en = "Network block profile"
    }
    NetworkBlockWarning = @{
        ja = "network block profile は Windows Firewall enforcement を使うため、ゲスト VM 内の管理者 PowerShell での実行を推奨します。"
        en = "The network block profile uses Windows Firewall enforcement, so running from an elevated PowerShell inside the guest VM is recommended."
    }
    NetworkOpenAttemptCurl = @{
        ja = "C:\Windows\System32\curl.exe を MXC 内で起動"
        en = "Start C:\Windows\System32\curl.exe inside MXC"
    }
    NetworkOpenAttemptHttp = @{
        ja = "HTTP HEAD: http://{0}/connecttest.txt"
        en = "HTTP HEAD: http://{0}/connecttest.txt"
    }
    NetworkOpenAttemptTcp = @{
        ja = "TCP destination: {0}:{1}"
        en = "TCP destination: {0}:{1}"
    }
    NetworkOpenExpected = @{
        ja = "curl が HTTP response header を取得し、MXC 内からの network access が成功する"
        en = "curl retrieves the HTTP response header, and network access from inside MXC succeeds"
    }
    NetworkOpenPolicyItem1 = @{
        ja = "processContainer.capabilities: internetClient を付与"
        en = "processContainer.capabilities: internetClient is granted"
    }
    NetworkOpenPolicyItem2 = @{
        ja = "network.defaultPolicy は未指定のため、通常の outbound ネットワークを許可"
        en = "network.defaultPolicy is not specified, so normal outbound network access is allowed"
    }
    NetworkOpenProfileStep = @{
        ja = "MXC network open profile で {0}:{1} に TCP 接続できることを確認しています"
        en = "Verifying that the MXC network open profile can connect to {0}:{1}"
    }
    NetworkOpenSummary = @{
        ja = "internetClient capability により MXC 内から外部ネットワークへ接続できることを確認します"
        en = "Verify that the internetClient capability allows external network access from inside MXC"
    }
    NetworkOpenTitle = @{
        ja = "ネットワーク許可プロファイル"
        en = "Network open profile"
    }
    OutputFileMissing = @{
        ja = "readwritePaths demo の出力ファイルが作成されていません: {0}"
        en = "The readwritePaths demo output file was not created: {0}"
    }
    ProfileLabel = @{
        ja = "プロファイル: {0}"
        en = "Profile: {0}"
    }
    ProfileMissing = @{
        ja = "MXC profile が見つかりません: {0}"
        en = "MXC profile was not found: {0}"
    }
    ProfileProcessCommandLineLabel = @{
        ja = "Profile process.commandLine:"
        en = "Profile process.commandLine:"
    }
    ReadonlyUnexpectedOutput = @{
        ja = "readonlyPaths demo で書き込みが成功してしまいました: {0}"
        en = "The readonlyPaths demo unexpectedly allowed a write: {0}"
    }
    ReadonlyWriteSideEffectAbsent = @{
        ja = "OK: readonlyPaths への書き込み副作用は残っていません。"
        en = "OK: no write side effect remains under readonlyPaths."
    }
    RepoPathLabel = @{
        ja = "RepoPath: {0}"
        en = "RepoPath: {0}"
    }
    ConfigDirectoryLabel = @{
        ja = "ConfigDirectory: {0}"
        en = "ConfigDirectory: {0}"
    }
    SeparatorLine = @{
        ja = "======================================================================"
        en = "======================================================================"
    }
    SkippedFilesystemDemo = @{
        ja = "filesystem demo をスキップしました"
        en = "Skipped the filesystem demo"
    }
    TcpConnected = @{
        ja = "OK: TCP {0}:{1} connected"
        en = "OK: TCP {0}:{1} connected"
    }
    TcpConnectTimedOut = @{
        ja = "TCP connect がタイムアウトしました: {0}:{1}"
        en = "TCP connect timed out: {0}:{1}"
    }
    ThisDemoWillTryLabel = @{
        ja = "このデモで試すこと:"
        en = "This demo will try:"
    }
    VcVarsAutoMissing = @{
        ja = "vcvars64.bat が見つかりません。Visual Studio / Build Tools の C++ x64 tools をインストールするか、-VcVarsPath を指定してください。"
        en = "vcvars64.bat was not found. Install the C++ x64 tools for Visual Studio / Build Tools, or specify -VcVarsPath."
    }
    VcVarsExplicitMissing = @{
        ja = "指定された vcvars64.bat が見つかりません: {0}"
        en = "The specified vcvars64.bat was not found: {0}"
    }
    VcVarsLabel = @{
        ja = "vcvars64.bat: {0}"
        en = "vcvars64.bat: {0}"
    }
    WxcExecLaunchCheck = @{
        ja = "wxc-exec.exe が起動できることを確認しています"
        en = "Verifying that wxc-exec.exe can start"
    }
    WxcHelpFailed = @{
        ja = "wxc-exec.exe --help が失敗しました。"
        en = "wxc-exec.exe --help failed."
    }
    WxcLaunchDllMissing = @{
        ja = "wxc-exec.exe の起動に必要な DLL が見つかっていません。Visual Studio Installer で Desktop development with C++ / MSVC x64 tools / Windows SDK が入っているか確認し、必要に応じて VC++ Redistributable x64 を入れてください。"
        en = "A DLL required to start wxc-exec.exe was not found. In Visual Studio Installer, check that Desktop development with C++, MSVC x64 tools, and Windows SDK are installed, and install VC++ Redistributable x64 if needed."
    }
    WxcLaunchFailed = @{
        ja = "{0} ExitCode={1} ({2})"
        en = "{0} ExitCode={1} ({2})"
    }
    WxcMissingBuildFirst = @{
        ja = "wxc-exec.exe が見つかりません。先に build_mxc_windows.ps1 で MXC をビルドしてください: {0}"
        en = "wxc-exec.exe was not found. Build MXC with build_mxc_windows.ps1 first: {0}"
    }
}

function Get-MxcMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [object[]]$Arguments = @()
    )

    $entry = $script:MxcMessages[$Key]
    if (-not $entry) {
        throw "Missing localized message: $Key"
    }

    $template = $entry[$script:MxcMessageLanguage]
    if (-not $template) {
        $template = $entry["en"]
    }

    if ($Arguments.Count -gt 0) {
        return ($template -f $Arguments)
    }

    return $template
}

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
    Write-Host (Get-MxcMessage -Key "SeparatorLine") -ForegroundColor Magenta
    Write-Host (Get-MxcMessage -Key "DemoLabel" -Arguments @($Title)) -ForegroundColor Magenta
    if ($Summary) {
        Write-Host " $Summary" -ForegroundColor DarkGray
    }
    Write-Host (Get-MxcMessage -Key "SeparatorLine") -ForegroundColor Magenta
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
        throw (Get-MxcMessage -Key "ProfileMissing" -Arguments @($ProfilePath))
    }

    Write-Step $Description
    $sdkBin = Split-Path -Parent $WxcExecPath
    $profile = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
    Write-Host (Get-MxcMessage -Key "MxcCommandLabel")
    Write-Host "  `"$WxcExecPath`" `"$ProfilePath`"" -ForegroundColor DarkGray
    Write-Host (Get-MxcMessage -Key "ProfileProcessCommandLineLabel")
    Write-Host "  $($profile.process.commandLine)" -ForegroundColor DarkGray
    $cmd = "call `"$VcVars`" >nul && set PATH=$sdkBin;%PATH% && cd /d `"$WorkingDirectory`" && `"$WxcExecPath`" `"$ProfilePath`""
    & $env:ComSpec /d /c $cmd
    if ($LASTEXITCODE -ne 0) {
        $hexExitCode = Format-WindowsExitCode -ExitCode $LASTEXITCODE
        $hint = if ($LASTEXITCODE -eq -1073741515) {
            Get-MxcMessage -Key "DllMissingHint" -Arguments @($WxcExecPath)
        } else {
            ""
        }
        throw (Get-MxcMessage -Key "MxcProfileFailed" -Arguments @($LASTEXITCODE, $hexExitCode, $ProfilePath, $hint))
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

    Write-Step (Get-MxcMessage -Key "WxcExecLaunchCheck")
    $sdkBin = Split-Path -Parent $WxcExecPath
    $cmd = "call `"$VcVars`" >nul && set PATH=$sdkBin;%PATH% && cd /d `"$WorkingDirectory`" && `"$WxcExecPath`" --help >nul"
    & $env:ComSpec /d /c $cmd
    if ($LASTEXITCODE -ne 0) {
        $hexExitCode = Format-WindowsExitCode -ExitCode $LASTEXITCODE
        $hint = if ($LASTEXITCODE -eq -1073741515) {
            Get-MxcMessage -Key "WxcLaunchDllMissing"
        } else {
            Get-MxcMessage -Key "WxcHelpFailed"
        }
        throw (Get-MxcMessage -Key "WxcLaunchFailed" -Arguments @($hint, $LASTEXITCODE, $hexExitCode))
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
            throw (Get-MxcMessage -Key "TcpConnectTimedOut" -Arguments @($HostName, $Port))
        }

        Write-Host (Get-MxcMessage -Key "TcpConnected" -Arguments @($HostName, $Port)) -ForegroundColor Green
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
    Write-Host (Get-MxcMessage -Key "DemoDetailsLabel" -Arguments @($Title)) -ForegroundColor Yellow
    Write-Host (Get-MxcMessage -Key "ProfileLabel" -Arguments @($ProfilePath))
    Write-Host (Get-MxcMessage -Key "AccessPolicyLabel")
    foreach ($item in $AccessPolicy) {
        Write-Host "  - $item"
    }

    Write-Host (Get-MxcMessage -Key "ThisDemoWillTryLabel")
    foreach ($item in $AttemptedAccess) {
        Write-Host "  - $item"
    }

    Write-Host (Get-MxcMessage -Key "ExpectedResultLabel" -Arguments @($ExpectedResult))
    Write-Host "----------------------------------------" -ForegroundColor Yellow
}

function Resolve-VcVarsPath {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath)) {
            throw (Get-MxcMessage -Key "VcVarsExplicitMissing" -Arguments @($ExplicitPath))
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
        throw (Get-MxcMessage -Key "VcVarsAutoMissing")
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
    throw (Get-MxcMessage -Key "WxcMissingBuildFirst" -Arguments @($wxcExec))
}

$vcvars = Resolve-VcVarsPath -ExplicitPath $VcVarsPath

$networkOpenProfile = Join-Path $ConfigDirectory "network-open-microsoft.json"
$networkBlockProfile = Join-Path $ConfigDirectory "network-block-microsoft.json"
$filesystemAllowProfile = Join-Path $ConfigDirectory "filesystem-readwrite-allowed.json"
$filesystemReadonlyProfile = Join-Path $ConfigDirectory "filesystem-readonly-deny-write.json"
$networkHost = "www.msftconnecttest.com"
$networkPort = 80

Write-Host (Get-MxcMessage -Key "MxcDemoRunner")
Write-Host (Get-MxcMessage -Key "RepoPathLabel" -Arguments @($RepoPath))
Write-Host (Get-MxcMessage -Key "ConfigDirectoryLabel" -Arguments @($ConfigDirectory))
Write-Host (Get-MxcMessage -Key "DemoRootLabel" -Arguments @($demoRoot))
Write-Host (Get-MxcMessage -Key "VcVarsLabel" -Arguments @($vcvars))

Test-WxcExecLaunch -WxcExecPath $wxcExec -WorkingDirectory $RepoPath -VcVars $vcvars

Write-DemoSeparator -Title (Get-MxcMessage -Key "BaselineNetworkTitle") -Summary (Get-MxcMessage -Key "BaselineNetworkSummary")
Write-Step (Get-MxcMessage -Key "BaselineNetworkStep" -Arguments @($networkHost, $networkPort))
Write-Host (Get-MxcMessage -Key "BaselineNetworkPurpose")
Write-Host (Get-MxcMessage -Key "BaselineNetworkAttempt" -Arguments @($networkHost, $networkPort))
Write-Host (Get-MxcMessage -Key "BaselineNetworkExpected")
Test-TcpConnectivity -HostName $networkHost -Port $networkPort

Write-DemoSeparator -Title (Get-MxcMessage -Key "NetworkOpenTitle") -Summary (Get-MxcMessage -Key "NetworkOpenSummary")
Write-DemoDetails `
    -Title (Get-MxcMessage -Key "NetworkOpenTitle") `
    -ProfilePath $networkOpenProfile `
    -AccessPolicy @(
        (Get-MxcMessage -Key "NetworkOpenPolicyItem1"),
        (Get-MxcMessage -Key "NetworkOpenPolicyItem2")
    ) `
    -AttemptedAccess @(
        (Get-MxcMessage -Key "NetworkOpenAttemptCurl"),
        (Get-MxcMessage -Key "NetworkOpenAttemptHttp" -Arguments @($networkHost)),
        (Get-MxcMessage -Key "NetworkOpenAttemptTcp" -Arguments @($networkHost, $networkPort))
    ) `
    -ExpectedResult (Get-MxcMessage -Key "NetworkOpenExpected")

Invoke-WxcProfile `
    -WxcExecPath $wxcExec `
    -ProfilePath $networkOpenProfile `
    -Description (Get-MxcMessage -Key "NetworkOpenProfileStep" -Arguments @($networkHost, $networkPort)) `
    -WorkingDirectory $RepoPath `
    -VcVars $vcvars

if (-not $SkipNetworkBlock) {
    Write-DemoSeparator -Title (Get-MxcMessage -Key "NetworkBlockTitle") -Summary (Get-MxcMessage -Key "NetworkBlockSummary")
    if (-not (Test-IsAdministrator)) {
        Write-Warning (Get-MxcMessage -Key "NetworkBlockWarning")
    }

    Write-DemoDetails `
        -Title (Get-MxcMessage -Key "NetworkBlockTitle") `
        -ProfilePath $networkBlockProfile `
        -AccessPolicy @(
            (Get-MxcMessage -Key "NetworkBlockPolicyItem1"),
            (Get-MxcMessage -Key "NetworkBlockPolicyItem2"),
            (Get-MxcMessage -Key "NetworkBlockPolicyItem3"),
            (Get-MxcMessage -Key "NetworkBlockPolicyItem4")
        ) `
        -AttemptedAccess @(
            (Get-MxcMessage -Key "NetworkBlockAttemptCurl"),
            (Get-MxcMessage -Key "NetworkBlockAttemptHttp" -Arguments @($networkHost)),
            (Get-MxcMessage -Key "NetworkBlockAttemptTcp" -Arguments @($networkHost, $networkPort))
        ) `
        -ExpectedResult (Get-MxcMessage -Key "NetworkBlockExpected")

    Invoke-WxcProfile `
        -WxcExecPath $wxcExec `
        -ProfilePath $networkBlockProfile `
        -Description (Get-MxcMessage -Key "NetworkBlockProfileStep" -Arguments @($networkHost, $networkPort)) `
        -WorkingDirectory $RepoPath `
        -VcVars $vcvars
} else {
    Write-Step (Get-MxcMessage -Key "NetworkBlockSkipped")
}

if (-not $SkipFilesystemDemo) {
    Write-DemoSeparator -Title (Get-MxcMessage -Key "FilesystemSetupTitle") -Summary (Get-MxcMessage -Key "FilesystemSetupSummary")
    Write-Step (Get-MxcMessage -Key "FilesystemSetupStep")
    Initialize-FilesystemDemo -Root $demoRoot

    $allowedPath = Join-Path $demoRoot "allowed"
    $readonlyPath = Join-Path $demoRoot "readonly"
    Write-DemoSeparator -Title (Get-MxcMessage -Key "FilesystemAllowTitle") -Summary (Get-MxcMessage -Key "FilesystemAllowSummary")
    Write-DemoDetails `
        -Title (Get-MxcMessage -Key "FilesystemAllowTitle") `
        -ProfilePath $filesystemAllowProfile `
        -AccessPolicy @(
            (Get-MxcMessage -Key "FilesystemAllowPolicyItem1" -Arguments @($allowedPath)),
            (Get-MxcMessage -Key "FilesystemAllowPolicyItem2"),
            (Get-MxcMessage -Key "FilesystemAllowPolicyItem3")
        ) `
        -AttemptedAccess @(
            (Get-MxcMessage -Key "FilesystemAllowAttemptRead" -Arguments @($allowedPath)),
            (Get-MxcMessage -Key "FilesystemAllowAttemptWrite" -Arguments @($allowedPath))
        ) `
        -ExpectedResult (Get-MxcMessage -Key "FilesystemAllowExpected")

    Invoke-WxcProfile `
        -WxcExecPath $wxcExec `
        -ProfilePath $filesystemAllowProfile `
        -Description (Get-MxcMessage -Key "FilesystemAllowProfileStep") `
        -WorkingDirectory $RepoPath `
        -VcVars $vcvars

    $allowedOutput = Join-Path $demoRoot "allowed\output-from-mxc.txt"
    if (-not (Test-Path -LiteralPath $allowedOutput)) {
        throw (Get-MxcMessage -Key "OutputFileMissing" -Arguments @($allowedOutput))
    }
    Write-Host (Get-MxcMessage -Key "HostVerificationOutputExists" -Arguments @($allowedOutput)) -ForegroundColor Green
    Write-Host (Get-MxcMessage -Key "HostVerificationContent")
    Get-Content -LiteralPath $allowedOutput

    Write-DemoSeparator -Title (Get-MxcMessage -Key "FilesystemReadonlyTitle") -Summary (Get-MxcMessage -Key "FilesystemReadonlySummary")
    Write-DemoDetails `
        -Title (Get-MxcMessage -Key "FilesystemReadonlyTitle") `
        -ProfilePath $filesystemReadonlyProfile `
        -AccessPolicy @(
            (Get-MxcMessage -Key "FilesystemReadonlyPolicyItem1" -Arguments @($allowedPath)),
            (Get-MxcMessage -Key "FilesystemReadonlyPolicyItem2" -Arguments @($readonlyPath)),
            (Get-MxcMessage -Key "FilesystemReadonlyPolicyItem3")
        ) `
        -AttemptedAccess @(
            (Get-MxcMessage -Key "FilesystemReadonlyAttemptReadAllowed" -Arguments @($allowedPath)),
            (Get-MxcMessage -Key "FilesystemReadonlyAttemptReadReadonly" -Arguments @($readonlyPath)),
            (Get-MxcMessage -Key "FilesystemReadonlyAttemptWrite" -Arguments @($readonlyPath))
        ) `
        -ExpectedResult (Get-MxcMessage -Key "FilesystemReadonlyExpected")

    Invoke-WxcProfile `
        -WxcExecPath $wxcExec `
        -ProfilePath $filesystemReadonlyProfile `
        -Description (Get-MxcMessage -Key "FilesystemReadonlyProfileStep") `
        -WorkingDirectory $RepoPath `
        -VcVars $vcvars

    $readonlyUnexpectedOutput = Join-Path $demoRoot "readonly\write-should-fail.txt"
    if (Test-Path -LiteralPath $readonlyUnexpectedOutput) {
        throw (Get-MxcMessage -Key "ReadonlyUnexpectedOutput" -Arguments @($readonlyUnexpectedOutput))
    }
    Write-Host (Get-MxcMessage -Key "ReadonlyWriteSideEffectAbsent") -ForegroundColor Green
} else {
    Write-Step (Get-MxcMessage -Key "SkippedFilesystemDemo")
}

Write-Host ""
Write-Host (Get-MxcMessage -Key "MxcDemoCompleted") -ForegroundColor Green
