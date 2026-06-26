[CmdletBinding()]
param(
    [string]$Workspace = "C:\mxc-demo",
    [string]$RepoUrl = "https://github.com/microsoft/mxc.git",
    [string]$RepoDirectoryName = "mxc",
    [string]$RustToolchain = "1.93",
    [ValidateSet("x64")]
    [string]$Platform = "x64",
    [ValidateSet("release", "debug")]
    [string]$Configuration = "release",
    [string]$VcVarsPath = "",
    [switch]$ForceClone,
    [switch]$SkipRustInstall,
    [switch]$SkipBuild,
    [switch]$RunProbe
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
    BuildCompleted = @{
        ja = "MXC Windows build script が完了しました。"
        en = "MXC Windows build script completed."
    }
    BuildOutputMissing = @{
        ja = "wxc-exec.exe が見つかりません: {0}"
        en = "wxc-exec.exe was not found: {0}"
    }
    BuildOutputOk = @{
        ja = "OK: {0}"
        en = "OK: {0}"
    }
    CargoSkipHint = @{
        ja = "SkipRustInstall を使う場合は cargo を PATH に用意してください。"
        en = "When using SkipRustInstall, make cargo available on PATH."
    }
    CargoHomeLabel = @{
        ja = "CARGO_HOME: {0}"
        en = "CARGO_HOME: {0}"
    }
    CheckingExistingRust = @{
        ja = "既存 rustup で Rust {0} を確認しています"
        en = "Checking Rust {0} with the existing rustup"
    }
    CheckingPrerequisites = @{
        ja = "前提コマンドを確認しています"
        en = "Checking prerequisite commands"
    }
    CloningRepo = @{
        ja = "MXC リポジトリを clone しています"
        en = "Cloning the MXC repository"
    }
    CommandNotFound = @{
        ja = "{0} が PATH に見つかりません。{1}"
        en = "{0} was not found on PATH. {1}"
    }
    DownloadingRustup = @{
        ja = "Rustup をダウンロードしています"
        en = "Downloading Rustup"
    }
    GitCloneFailed = @{
        ja = "git clone が終了コード {0} で失敗しました"
        en = "git clone failed with exit code {0}"
    }
    GitInstallHint = @{
        ja = "Git for Windows をインストールしてください。"
        en = "Install Git for Windows."
    }
    InstallingRust = @{
        ja = "Rust {0} を隔離ディレクトリにインストールしています"
        en = "Installing Rust {0} into the isolated directory"
    }
    MxcBuildFailed = @{
        ja = "MXC build が終了コード {0} で失敗しました"
        en = "MXC build failed with exit code {0}"
    }
    MxcBuildStep = @{
        ja = "MXC をビルドしています: build.bat {0}"
        en = "Building MXC: build.bat {0}"
    }
    NodeInstallHint = @{
        ja = "Node.js 18 以上をインストールしてください。"
        en = "Install Node.js 18 or later."
    }
    NodeMinimumRequired = @{
        ja = "Node.js 18 以上が必要です。現在のバージョン: {0}"
        en = "Node.js 18 or later is required. Current version: {0}"
    }
    NodeVersionLabel = @{
        ja = "Node.js: {0}"
        en = "Node.js: {0}"
    }
    NpmCacheLabel = @{
        ja = "npm_config_cache: {0}"
        en = "npm_config_cache: {0}"
    }
    NpmInstallHint = @{
        ja = "Node.js 18 以上に含まれる npm を利用できるようにしてください。"
        en = "Make npm from Node.js 18 or later available."
    }
    PreparingWorkspace = @{
        ja = "作業ディレクトリを準備しています"
        en = "Preparing the workspace"
    }
    PythonMissingWarning = @{
        ja = "python が PATH に見つかりません。ビルド後の Hello World / network demo には実体のある python.exe が必要です。"
        en = "python was not found on PATH. A real python.exe is required for the post-build Hello World / network demo."
    }
    PythonWindowsAppsWarning = @{
        ja = "python が WindowsApps alias を指しています。デモ実行前に実体のある python.exe を PATH に追加してください: {0}"
        en = "python points to the WindowsApps alias. Add a real python.exe to PATH before running the demo: {0}"
    }
    RemovingExistingRepo = @{
        ja = "既存 MXC リポジトリを削除しています"
        en = "Removing the existing MXC repository"
    }
    RustInstallMayHaveFailed = @{
        ja = "Rust のインストールに失敗している可能性があります。"
        en = "The Rust installation may have failed."
    }
    RustcSkipHint = @{
        ja = "SkipRustInstall を使う場合は rustc を PATH に用意してください。"
        en = "When using SkipRustInstall, make rustc available on PATH."
    }
    RustupHomeLabel = @{
        ja = "RUSTUP_HOME: {0}"
        en = "RUSTUP_HOME: {0}"
    }
    SkippingMxcBuild = @{
        ja = "MXC ビルドをスキップしています"
        en = "Skipping the MXC build"
    }
    SkippingRustInstall = @{
        ja = "Rust インストールをスキップしています"
        en = "Skipping Rust installation"
    }
    UsingExistingRepo = @{
        ja = "既存 MXC リポジトリを使用します"
        en = "Using the existing MXC repository"
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
    VerifyingBuildOutput = @{
        ja = "ビルド成果物を確認しています"
        en = "Verifying the build output"
    }
    WorkspaceLabel = @{
        ja = "Workspace: {0}"
        en = "Workspace: {0}"
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

function Assert-Command {
    param(
        [string]$Name,
        [string]$InstallHint
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw (Get-MxcMessage -Key "CommandNotFound" -Arguments @($Name, $InstallHint))
    }

    return $command
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

function Initialize-IsolatedEnvironment {
    param([string]$WorkspacePath)

    $env:RUSTUP_HOME = Join-Path $WorkspacePath ".rustup"
    $env:CARGO_HOME = Join-Path $WorkspacePath ".cargo-home"
    $env:npm_config_cache = Join-Path $WorkspacePath ".npm-cache"
    $env:PATH = "$env:CARGO_HOME\bin;$env:PATH"

    New-Item -ItemType Directory -Force -Path $env:RUSTUP_HOME, $env:CARGO_HOME, $env:npm_config_cache | Out-Null
}

function Install-RustToolchain {
    param(
        [string]$WorkspacePath,
        [string]$Toolchain
    )

    $rustup = Join-Path $env:CARGO_HOME "bin\rustup.exe"
    if (-not (Test-Path -LiteralPath $rustup)) {
        $rustupInit = Join-Path $WorkspacePath "rustup-init.exe"
        Write-Step (Get-MxcMessage -Key "DownloadingRustup")
        Invoke-WebRequest "https://win.rustup.rs/x86_64" -OutFile $rustupInit

        Write-Step (Get-MxcMessage -Key "InstallingRust" -Arguments @($Toolchain))
        & $rustupInit -y --no-modify-path --default-toolchain $Toolchain --profile minimal --component rustfmt --component clippy
    } else {
        Write-Step (Get-MxcMessage -Key "CheckingExistingRust" -Arguments @($Toolchain))
        & $rustup toolchain install $Toolchain --profile minimal --component rustfmt --component clippy
        & $rustup default $Toolchain
    }

    Assert-Command "rustc" (Get-MxcMessage -Key "RustInstallMayHaveFailed") | Out-Null
    Assert-Command "cargo" (Get-MxcMessage -Key "RustInstallMayHaveFailed") | Out-Null
    rustc --version
    cargo --version
}

function Invoke-MxcBuild {
    param(
        [string]$RepoPath,
        [string]$VcVars,
        [string]$BuildConfiguration,
        [string]$BuildPlatform
    )

    $buildArgs = @()
    if ($BuildConfiguration -eq "release") {
        $buildArgs += "--release"
    }
    $buildArgs += "--$BuildPlatform"
    $buildArgsText = $buildArgs -join " "

    $cmd = "call `"$VcVars`" >nul && cd /d `"$RepoPath`" && build.bat $buildArgsText"
    Write-Step (Get-MxcMessage -Key "MxcBuildStep" -Arguments @($buildArgsText))
    & $env:ComSpec /d /c $cmd
    if ($LASTEXITCODE -ne 0) {
        throw (Get-MxcMessage -Key "MxcBuildFailed" -Arguments @($LASTEXITCODE))
    }
}

function Test-RealPython {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        Write-Warning (Get-MxcMessage -Key "PythonMissingWarning")
        return
    }

    if ($python.Source -like "*\Microsoft\WindowsApps\python.exe") {
        Write-Warning (Get-MxcMessage -Key "PythonWindowsAppsWarning" -Arguments @($python.Source))
    }
}

$workspaceFull = [System.IO.Path]::GetFullPath($Workspace)
$repoPath = Join-Path $workspaceFull $RepoDirectoryName
$wxcExecPath = Join-Path $repoPath "sdk\bin\$Platform\wxc-exec.exe"

Write-Step (Get-MxcMessage -Key "CheckingPrerequisites")
Assert-Command "git" (Get-MxcMessage -Key "GitInstallHint") | Out-Null
Assert-Command "node" (Get-MxcMessage -Key "NodeInstallHint") | Out-Null
Assert-Command "npm" (Get-MxcMessage -Key "NpmInstallHint") | Out-Null
Test-RealPython

$nodeVersionText = (& node --version)
if ($nodeVersionText -match "v?(\d+)\.") {
    $nodeMajor = [int]$Matches[1]
    if ($nodeMajor -lt 18) {
        throw (Get-MxcMessage -Key "NodeMinimumRequired" -Arguments @($nodeVersionText))
    }
}
Write-Host (Get-MxcMessage -Key "NodeVersionLabel" -Arguments @($nodeVersionText))

$vcvars = Resolve-VcVarsPath -ExplicitPath $VcVarsPath
Write-Host (Get-MxcMessage -Key "VcVarsLabel" -Arguments @($vcvars))

Write-Step (Get-MxcMessage -Key "PreparingWorkspace")
New-Item -ItemType Directory -Force -Path $workspaceFull | Out-Null
Initialize-IsolatedEnvironment -WorkspacePath $workspaceFull
Write-Host (Get-MxcMessage -Key "WorkspaceLabel" -Arguments @($workspaceFull))
Write-Host (Get-MxcMessage -Key "RustupHomeLabel" -Arguments @($env:RUSTUP_HOME))
Write-Host (Get-MxcMessage -Key "CargoHomeLabel" -Arguments @($env:CARGO_HOME))
Write-Host (Get-MxcMessage -Key "NpmCacheLabel" -Arguments @($env:npm_config_cache))

if ($ForceClone -and (Test-Path -LiteralPath $repoPath)) {
    Write-Step (Get-MxcMessage -Key "RemovingExistingRepo")
    Remove-Item -LiteralPath $repoPath -Recurse -Force
}

if (-not (Test-Path -LiteralPath $repoPath)) {
    Write-Step (Get-MxcMessage -Key "CloningRepo")
    git clone --depth 1 $RepoUrl $repoPath
    if ($LASTEXITCODE -ne 0) {
        throw (Get-MxcMessage -Key "GitCloneFailed" -Arguments @($LASTEXITCODE))
    }
} else {
    Write-Step (Get-MxcMessage -Key "UsingExistingRepo")
    Write-Host $repoPath
}

if (-not $SkipRustInstall) {
    Install-RustToolchain -WorkspacePath $workspaceFull -Toolchain $RustToolchain
} else {
    Write-Step (Get-MxcMessage -Key "SkippingRustInstall")
    Assert-Command "rustc" (Get-MxcMessage -Key "RustcSkipHint") | Out-Null
    Assert-Command "cargo" (Get-MxcMessage -Key "CargoSkipHint") | Out-Null
}

if (-not $SkipBuild) {
    Invoke-MxcBuild -RepoPath $repoPath -VcVars $vcvars -BuildConfiguration $Configuration -BuildPlatform $Platform
} else {
    Write-Step (Get-MxcMessage -Key "SkippingMxcBuild")
}

Write-Step (Get-MxcMessage -Key "VerifyingBuildOutput")
if (Test-Path -LiteralPath $wxcExecPath) {
    Write-Host (Get-MxcMessage -Key "BuildOutputOk" -Arguments @($wxcExecPath)) -ForegroundColor Green
    if ($RunProbe) {
        & $wxcExecPath --probe
    }
} else {
    throw (Get-MxcMessage -Key "BuildOutputMissing" -Arguments @($wxcExecPath))
}

Write-Host ""
Write-Host (Get-MxcMessage -Key "BuildCompleted") -ForegroundColor Green
