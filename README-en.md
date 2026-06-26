# MXC Windows Build & Policy Demo Scripts

This repository contains helper scripts for building [Microsoft MXC](https://github.com/microsoft/mxc) on Windows and demonstrating basic MXC policy behavior.

The primary documentation is Japanese. See [README.md](README.md).

## Contents

| Path | Purpose |
| --- | --- |
| `build_mxc_windows.ps1` | Clones the MXC repository and builds `wxc-exec.exe` for Windows x64. |
| `run_mxc_demo.ps1` | Runs policy demos with a built `wxc-exec.exe` and the sample profiles. |
| `mxc-profiles\*.json` | Demo MXC profiles for network allow/block and filesystem read-write/read-only behavior. |

This repository does not include the MXC source code. By default, `build_mxc_windows.ps1` shallow-clones `https://github.com/microsoft/mxc.git` into `C:\mxc-demo\mxc`.

## Prerequisites

### Environment

- Windows x64
- PowerShell 5.1 or later, or PowerShell 7 or later
- Internet access for:
  - cloning the MXC repository
  - downloading Rustup
  - downloading the Rust toolchain
  - fetching dependencies during the MXC build
  - reaching `www.msftconnecttest.com:80` during the network demo
- A disposable Windows VM is recommended
  - The scripts use `C:\mxc-demo` and `C:\mxc-demo-fs` by default.
  - The network block demo uses Windows Firewall enforcement, so running from an elevated PowerShell inside the guest VM is recommended.

### Required tools

`build_mxc_windows.ps1` checks or uses the following tools.

| Tool | Requirement | Notes |
| --- | --- | --- |
| Git for Windows | `git` must be available on PATH | Required to clone MXC. |
| Node.js | 18 or later | `node` and `npm` must be available on PATH. |
| Visual Studio / Build Tools | C++ x64 tools | The script auto-detects `vcvars64.bat`; use `-VcVarsPath` if auto-detection fails. |
| Rust / Rustup | By default, the script installs Rust `1.93` into an isolated workspace | If you use `-SkipRustInstall`, provide `rustc` and `cargo` on PATH. |

For Visual Studio 2022 or Build Tools for Visual Studio 2022, the following components are recommended:

- Desktop development with C++
- MSVC x64/x86 build tools
- Windows SDK
- C++ CMake tools for Windows

### Demo-specific notes

- `run_mxc_demo.ps1` looks for `C:\mxc-demo\mxc\sdk\bin\x64\wxc-exec.exe` by default. Use `-RepoPath` if MXC is elsewhere.
- If `wxc-exec.exe` fails with a missing DLL error, check the Visual Studio C++ workload, MSVC x64 tools, Windows SDK, VC++ Redistributable x64, and the MXC build output layout.
- If Python resolves to the WindowsApps alias, some MXC samples or checks may require a real `python.exe` on PATH.
- If PowerShell execution policy blocks the scripts, relax it for the current process only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

## Quick start

Open an elevated PowerShell and run the following from this repository directory:

```powershell
.\build_mxc_windows.ps1
.\run_mxc_demo.ps1
```

By default, the scripts:

1. Create `C:\mxc-demo` as the workspace.
2. Clone MXC into `C:\mxc-demo\mxc`.
3. Install the Rust toolchain into `C:\mxc-demo\.rustup` and `C:\mxc-demo\.cargo-home`.
4. Run `build.bat --release --x64`.
5. Verify `C:\mxc-demo\mxc\sdk\bin\x64\wxc-exec.exe`.
6. Run the sample MXC policy profiles.

## Build MXC

For the common case, run:

```powershell
.\build_mxc_windows.ps1
```

Common options:

| Option | Default | Description |
| --- | --- | --- |
| `-Workspace` | `C:\mxc-demo` | Workspace for the MXC clone, Rust, and npm cache. |
| `-RepoUrl` | `https://github.com/microsoft/mxc.git` | MXC repository URL to clone. |
| `-RepoDirectoryName` | `mxc` | Directory name created under `-Workspace`. |
| `-RustToolchain` | `1.93` | Rust toolchain to install or verify. |
| `-Configuration` | `release` | `release` or `debug`. |
| `-Platform` | `x64` | Currently only `x64` is supported. |
| `-VcVarsPath` | auto-detected | Explicit path to `vcvars64.bat`. |
| `-ForceClone` | disabled | Deletes the existing MXC clone and clones again. |
| `-SkipRustInstall` | disabled | Skips Rust installation and uses `rustc` / `cargo` from PATH. |
| `-SkipBuild` | disabled | Performs clone and prerequisite checks but skips the MXC build. |
| `-RunProbe` | disabled | Runs `wxc-exec.exe --probe` after the build. |

Example:

```powershell
.\build_mxc_windows.ps1 `
  -Workspace C:\work\mxc-demo `
  -Configuration debug `
  -VcVarsPath "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
```

## Run the policy demo

After the build completes, run:

```powershell
.\run_mxc_demo.ps1
```

The demo verifies:

| Demo | Profile | What it verifies |
| --- | --- | --- |
| Baseline network check | none | The VM can reach `www.msftconnecttest.com:80` outside MXC. |
| Network open profile | `mxc-profiles\network-open-microsoft.json` | With the `internetClient` capability, `curl.exe` inside MXC can perform an HTTP HEAD request. |
| Network block profile | `mxc-profiles\network-block-microsoft.json` | With `network.defaultPolicy=block` and `enforcementMode=firewall`, outbound access from inside MXC fails. |
| Filesystem read/write profile | `mxc-profiles\filesystem-readwrite-allowed.json` | Reading and writing under `C:\mxc-demo-fs\allowed` succeeds. |
| Filesystem readonly profile | `mxc-profiles\filesystem-readonly-deny-write.json` | `C:\mxc-demo-fs\readonly` is readable but not writable. |

Common options:

| Option | Default | Description |
| --- | --- | --- |
| `-RepoPath` | `C:\mxc-demo\mxc` | Path to the built MXC repository. |
| `-ConfigDirectory` | `.\mxc-profiles` | Directory containing demo JSON profiles. |
| `-VcVarsPath` | auto-detected | Explicit path to `vcvars64.bat`. |
| `-SkipNetworkBlock` | disabled | Skips the firewall-based network block demo. |
| `-SkipFilesystemDemo` | disabled | Skips filesystem policy demos. |

If you cannot run an elevated PowerShell, start by skipping the network block demo:

```powershell
.\run_mxc_demo.ps1 -SkipNetworkBlock
```

## Troubleshooting

### `vcvars64.bat` is not found

Check that Visual Studio C++ x64 tools are installed. If auto-detection fails, pass `-VcVarsPath`.

```powershell
.\build_mxc_windows.ps1 -VcVarsPath "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
```

### `Node.js 18 or later is required`

Install Node.js 18 or later and ensure `node` and `npm` are available on PATH.

```powershell
node --version
npm --version
```

### `wxc-exec.exe` is not found

Complete the build first. The default expected output path is:

```text
C:\mxc-demo\mxc\sdk\bin\x64\wxc-exec.exe
```

If you used a different workspace, pass `-RepoPath` when running the demo.

```powershell
.\run_mxc_demo.ps1 -RepoPath C:\work\mxc-demo\mxc
```

### The network block demo does not fail as expected

`network-block-microsoft.json` uses Windows Firewall enforcement. Run it from an elevated PowerShell inside the guest VM. Firewall, proxy, endpoint security, and network isolation settings can affect the result.

### Baseline network check fails

The VM cannot reach `www.msftconnecttest.com:80` outside MXC. Check the VM network, proxy, firewall, DNS, or corporate network restrictions.

## License

The scripts and documentation in this repository are licensed under the MIT License. See [LICENSE](LICENSE).

