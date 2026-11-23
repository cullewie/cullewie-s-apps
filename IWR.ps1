[CmdletBinding()]
param()

# cullewie-s-apps: one command after a format.
#  1. Downloads Install.ps1 from a pinned commit of this repo and checks its SHA-256.
#  2. Leaves it as cullewie-s-progress's extra setup script (C:\ProgramData\Cullewie\Work\after-setup.ps1, a folder
#     only administrators and SYSTEM can write), with its SHA-256 next to it.
#  3. Starts cullewie-s-progress with CULLEWIE_AUTO=all-in: All-in runs by itself, and after its last restart the
#     window installs the apps, then asks Digital Vibrance, cleans the disk and restarts once more.
& {
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
$Repository = 'cullewie/cullewie-s-apps'
$PayloadCommit = '832fa191b80fd0f97b799d86c7e2dea518f1b844'
$InstallSha256 = 'abfab8628cbcc15af289c9e7f8525856fcc9862de53036db05b3d666cc49cba6'
$RawRoot = 'https://raw.githubusercontent.com/' + $Repository + '/' + $PayloadCommit
$ProgressIwr = 'https://github.com/cullewie/cullewie-s-progress/raw/refs/heads/main/IWR.ps1'
$stage = $null

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Open PowerShell with Run as administrator, then run the one-line command again.'
    }
    if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) { throw 'Use 64-bit PowerShell on 64-bit Windows.' }
    if ([Environment]::OSVersion.Version.Build -lt 22000) { throw 'Windows 11 is required.' }
    if ($PayloadCommit -notmatch '^[0-9a-f]{40}$' -or $PayloadCommit -match '^0+$' -or $InstallSha256 -notmatch '^[0-9a-f]{64}$' -or $InstallSha256 -match '^0+$') {
        throw 'The bootstrap pins have not been configured.'
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # the same folder rules as cullewie-s-progress: owned by Administrators, only SYSTEM and Administrators inside
    $root = Join-Path $env:ProgramData 'Cullewie'
    $work = Join-Path $root 'Work'
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $icacls = Join-Path $env:SystemRoot 'System32\icacls.exe'
    & $icacls $root '/setowner' '*S-1-5-32-544' '/T' '/C' '/Q' | Out-Null
    & $icacls $root '/reset' '/T' '/C' '/Q' | Out-Null
    & $icacls $root '/inheritance:r' '/grant:r' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not restrict directory permissions: $root" }
    New-Item -ItemType Directory -Force -Path $work | Out-Null

    $stage = Join-Path $work ('after-setup-' + [Guid]::NewGuid().ToString('N') + '.ps1')
    Invoke-WebRequest -Uri ($RawRoot + '/Install.ps1') -UseBasicParsing -OutFile $stage -TimeoutSec 120
    $hash = (Get-FileHash -LiteralPath $stage -Algorithm SHA256).Hash
    if ($hash -ne $InstallSha256.ToUpperInvariant()) { throw 'Install.ps1 SHA-256 did not match the bootstrap pin.' }
    Move-Item -LiteralPath $stage -Destination (Join-Path $work 'after-setup.ps1') -Force
    $stage = $null
    Set-Content -LiteralPath (Join-Path $work 'after-setup.sha256') -Value $hash -Encoding ASCII
    Write-Host "Verified apps release: $($PayloadCommit.Substring(0, 12)). The apps install after All-in." -ForegroundColor Green

    $env:CULLEWIE_AUTO = 'all-in'
    Remove-Item Env:\CULLEWIE_MODE, Env:\CULLEWIE_APPS -ErrorAction SilentlyContinue
    $bootstrap = (Invoke-WebRequest -Uri $ProgressIwr -UseBasicParsing -TimeoutSec 60).Content
    if ($bootstrap -is [byte[]]) { $bootstrap = [Text.Encoding]::UTF8.GetString($bootstrap) }
    Invoke-Expression $bootstrap
}
catch {
    Write-Host "Stopped: $($_.Exception.Message)" -ForegroundColor Red
    if ($stage) { Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue }
}
finally {
    Remove-Item Env:\CULLEWIE_AUTO -ErrorAction SilentlyContinue
    [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol
}
}
