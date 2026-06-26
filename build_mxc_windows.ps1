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
        throw "$Name が PATH に見つかりません。$InstallHint"
    }

    return $command
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
        Write-Step "Rustup をダウンロードしています"
        Invoke-WebRequest "https://win.rustup.rs/x86_64" -OutFile $rustupInit

        Write-Step "Rust $Toolchain を隔離ディレクトリにインストールしています"
        & $rustupInit -y --no-modify-path --default-toolchain $Toolchain --profile minimal --component rustfmt --component clippy
    } else {
        Write-Step "既存 rustup で Rust $Toolchain を確認しています"
        & $rustup toolchain install $Toolchain --profile minimal --component rustfmt --component clippy
        & $rustup default $Toolchain
    }

    Assert-Command "rustc" "Rust のインストールに失敗している可能性があります。" | Out-Null
    Assert-Command "cargo" "Rust のインストールに失敗している可能性があります。" | Out-Null
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
    Write-Step "MXC をビルドしています: build.bat $buildArgsText"
    & $env:ComSpec /d /c $cmd
    if ($LASTEXITCODE -ne 0) {
        throw "MXC build failed with exit code $LASTEXITCODE"
    }
}

function Test-RealPython {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        Write-Warning "python が PATH に見つかりません。ビルド後の Hello World / network demo には実体のある python.exe が必要です。"
        return
    }

    if ($python.Source -like "*\Microsoft\WindowsApps\python.exe") {
        Write-Warning "python が WindowsApps alias を指しています。デモ実行前に実体のある python.exe を PATH に追加してください: $($python.Source)"
    }
}

$workspaceFull = [System.IO.Path]::GetFullPath($Workspace)
$repoPath = Join-Path $workspaceFull $RepoDirectoryName
$wxcExecPath = Join-Path $repoPath "sdk\bin\$Platform\wxc-exec.exe"

Write-Step "前提コマンドを確認しています"
Assert-Command "git" "Git for Windows をインストールしてください。" | Out-Null
Assert-Command "node" "Node.js 18 以上をインストールしてください。" | Out-Null
Assert-Command "npm" "Node.js 18 以上に含まれる npm を利用できるようにしてください。" | Out-Null
Test-RealPython

$nodeVersionText = (& node --version)
if ($nodeVersionText -match "v?(\d+)\.") {
    $nodeMajor = [int]$Matches[1]
    if ($nodeMajor -lt 18) {
        throw "Node.js 18 以上が必要です。現在のバージョン: $nodeVersionText"
    }
}
Write-Host "Node.js: $nodeVersionText"

$vcvars = Resolve-VcVarsPath -ExplicitPath $VcVarsPath
Write-Host "vcvars64.bat: $vcvars"

Write-Step "作業ディレクトリを準備しています"
New-Item -ItemType Directory -Force -Path $workspaceFull | Out-Null
Initialize-IsolatedEnvironment -WorkspacePath $workspaceFull
Write-Host "Workspace: $workspaceFull"
Write-Host "RUSTUP_HOME: $env:RUSTUP_HOME"
Write-Host "CARGO_HOME: $env:CARGO_HOME"
Write-Host "npm_config_cache: $env:npm_config_cache"

if ($ForceClone -and (Test-Path -LiteralPath $repoPath)) {
    Write-Step "既存 MXC リポジトリを削除しています"
    Remove-Item -LiteralPath $repoPath -Recurse -Force
}

if (-not (Test-Path -LiteralPath $repoPath)) {
    Write-Step "MXC リポジトリを clone しています"
    git clone --depth 1 $RepoUrl $repoPath
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE"
    }
} else {
    Write-Step "既存 MXC リポジトリを使用します"
    Write-Host $repoPath
}

if (-not $SkipRustInstall) {
    Install-RustToolchain -WorkspacePath $workspaceFull -Toolchain $RustToolchain
} else {
    Write-Step "Rust インストールをスキップしています"
    Assert-Command "rustc" "SkipRustInstall を使う場合は rustc を PATH に用意してください。" | Out-Null
    Assert-Command "cargo" "SkipRustInstall を使う場合は cargo を PATH に用意してください。" | Out-Null
}

if (-not $SkipBuild) {
    Invoke-MxcBuild -RepoPath $repoPath -VcVars $vcvars -BuildConfiguration $Configuration -BuildPlatform $Platform
} else {
    Write-Step "MXC ビルドをスキップしています"
}

Write-Step "ビルド成果物を確認しています"
if (Test-Path -LiteralPath $wxcExecPath) {
    Write-Host "OK: $wxcExecPath" -ForegroundColor Green
    if ($RunProbe) {
        & $wxcExecPath --probe
    }
} else {
    throw "wxc-exec.exe が見つかりません: $wxcExecPath"
}

Write-Host ""
Write-Host "MXC Windows build script completed." -ForegroundColor Green
