# Installs the owner's apps, each the newest version, straight from the vendor, after checking the file's signature.
# Run as administrator (IWR.ps1 does this). No winget: it may not work after cullewie-s-progress All-in, and its
# catalog lags the vendors.
param()
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # the progress bar made a 168 MB download take minutes
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
$Root = Join-Path $env:ProgramData 'Cullewie\Apps'

# ---------- finding the newest version

# newest TeamSpeak 6 client MSI on teamspeak.com: a release beats the betas of the same version, beta10 beats beta5.1
function Get-TeamSpeakUrl([string]$Html) {
    $found = foreach ($m in [regex]::Matches([string]$Html, 'https://files\.teamspeak-services\.com/(?:pre_)?releases/client/(6\.\d+\.\d+)(?:-beta(\d+(?:\.\d+)?))?/teamspeak-client\.msi')) {
        $beta = if ($m.Groups[2].Success) { [version]($m.Groups[2].Value + $(if ($m.Groups[2].Value.Contains('.')) { '' } else { '.0' })) } else { [version]'9999.0' }
        [pscustomobject]@{ Url = $m.Value; Base = [version]$m.Groups[1].Value; Beta = $beta }
    }
    $best = $found | Sort-Object Base, Beta -Descending | Select-Object -First 1
    if ($best) { $best.Url } else { $null }
}
# the version label in a TeamSpeak URL (6.0.0-beta5.1)
function Get-TeamSpeakLabel([string]$Url) { [regex]::Match($Url, '/client/([^/]+)/').Groups[1].Value }

# the newest DDU page on Wagnardsoft's DDU listing (the number in its address is the version without dots)
function Get-DduPage([string]$Html) {
    $best = [regex]::Matches([string]$Html, '/content/Download-Display-Driver-Uninstaller-DDU-(\d+)') |
        Sort-Object { [int64]$_.Groups[1].Value } -Descending | Select-Object -First 1
    if ($best) { 'https://www.wagnardsoft.com/content/Download-Display-Driver-Uninstaller-DDU-' + $best.Groups[1].Value } else { $null }
}
function Get-DduVersion([string]$Html) {
    $m = [regex]::Match([string]$Html, 'Display Driver Uninstaller \(DDU\) (\d+\.\d+\.\d+\.\d+)')
    if ($m.Success) { $m.Groups[1].Value } else { $null }
}
function Get-DduUrl([string]$Version) { 'https://download.wagnardsoft.com/DDU/DDU%20v' + $Version + '_setup.exe' }

# newest AMD Chipset Software on AMD's chipset page
function Get-ChipsetUrl([string]$Html) {
    $best = [regex]::Matches([string]$Html, 'https://drivers\.amd\.com/drivers/amd_chipset_software_(\d+(?:\.\d+)+)\.exe') |
        Sort-Object { [version]$_.Groups[1].Value } -Descending | Select-Object -First 1
    if ($best) { $best.Value } else { $null }
}

# true when $Want is newer than $Have (nothing installed counts as older)
function Test-Newer([string]$Have, [string]$Want) {
    if (-not $Have) { return $true }
    try { return ([version]$Want -gt [version]$Have) } catch { return $Want -ne $Have }
}

# ---------- download, signature, running installers

function Get-Page([string]$Url, [hashtable]$Headers = @{}) {
    $h = @{ 'User-Agent' = $UserAgent } + $Headers
    $c = (Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers $h -TimeoutSec 60).Content
    if ($c -is [byte[]]) { $c = [Text.Encoding]::UTF8.GetString($c) }
    $c
}
function Save-Download([string]$Url, [string]$Path, [hashtable]$Headers = @{}) {
    $h = @{ 'User-Agent' = $UserAgent } + $Headers
    Invoke-WebRequest -Uri $Url -UseBasicParsing -Headers $h -OutFile $Path -TimeoutSec 900
}
# the file is signed, the signature is valid, and the signer's name is exactly $Cn
function Test-Signer([string]$Path, [string]$Cn) {
    $s = Get-AuthenticodeSignature -LiteralPath $Path
    if ($s.Status -ne 'Valid' -or -not $s.SignerCertificate) { return $false }
    $subject = $s.SignerCertificate.Subject
    return ($subject -eq "CN=$Cn" -or $subject.StartsWith("CN=$Cn, "))
}
# runs an installer and returns its exit code; -1 when it ran past the limit (it and its children are stopped)
function Invoke-Installer([string]$File, [string]$Arguments, [double]$TimeoutMinutes = 15) {
    $p = Start-Process -FilePath $File -ArgumentList $Arguments -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit([int]($TimeoutMinutes * 60000))) {
        & "$env:SystemRoot\System32\taskkill.exe" /PID $p.Id /T /F 2>$null | Out-Null
        return -1
    }
    return $p.ExitCode
}
# runs an installer as the signed-in user, not elevated (Spotify refuses to install as administrator)
function Invoke-AsUser([string]$File, [string]$Arguments, [double]$TimeoutMinutes = 15) {
    $explorer = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Select-Object -First 1
    if (-not $explorer) { throw 'Kimse oturum açmamış (explorer.exe yok).' }
    $owner = Invoke-CimMethod -InputObject $explorer -MethodName GetOwner
    $user = "$($owner.Domain)\$($owner.User)"
    $name = 'cullewie-apps-asuser'
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    $action = New-ScheduledTaskAction -Execute $File -Argument $Arguments
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force | Out-Null
    try {
        Start-ScheduledTask -TaskName $name
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        Start-Sleep -Seconds 2
        while ((Get-ScheduledTask -TaskName $name).State -eq 'Running') {
            if ((Get-Date) -gt $deadline) { Stop-ScheduledTask -TaskName $name; return -1 }
            Start-Sleep -Seconds 2
        }
        return [int](Get-ScheduledTaskInfo -TaskName $name).LastTaskResult
    }
    finally { Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue }
}
# DisplayVersion of an installed program whose name matches $NamePattern exactly; $null when it is not installed.
# With $Exe: also $null when that file is gone (an uninstall can leave the registration behind)
function Get-InstalledVersion([string]$NamePattern, [string]$Exe) {
    if ($Exe -and -not (Test-Path -LiteralPath $Exe)) { return $null }
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $hit = Get-ItemProperty $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "^(?:$NamePattern)$" } | Select-Object -First 1
    if ($hit) { if ($hit.DisplayVersion) { [string]$hit.DisplayVersion } else { '0' } } else { $null }
}

# ---------- the apps (order is the install order)
# Update = $true: the newest version is read before downloading and a newer one replaces the installed one.
# The others update themselves, so an installed copy is left alone.
$Apps = @(
    @{ Name = 'Chrome'; Detect = 'Google Chrome'; Exe = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"; Signer = 'Google LLC'; Url = 'https://dl.google.com/dl/chrome/install/googlechromestandaloneenterprise64.msi'; File = 'chrome.msi'; Msi = $true }
    @{ Name = 'TeamSpeak'; Detect = 'TeamSpeak'; Signer = 'TeamSpeak Systems GmbH'; File = 'teamspeak.msi'; Msi = $true; Update = $true; Resolve = { $u = Get-TeamSpeakUrl (Get-Page 'https://teamspeak.com/en/downloads/'); if ($u) { @{ Url = $u; Version = (Get-TeamSpeakLabel $u) } } } }
    @{ Name = 'Steam'; Detect = 'Steam'; Exe = "${env:ProgramFiles(x86)}\Steam\steam.exe"; Signer = 'Valve Corp.'; Url = 'https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe'; File = 'steam.exe'; Args = '/S' }
    @{ Name = 'Spotify'; Detect = 'Spotify'; Exe = "$env:APPDATA\Spotify\Spotify.exe"; Signer = 'Spotify AB'; Url = 'https://download.scdn.co/SpotifyFullSetupX64.exe'; File = 'spotify.exe'; Args = '/silent'; AsUser = $true }
    @{ Name = 'FACEIT AC'; Detect = 'FACEIT Anti-Cheat'; Signer = 'ESL FACEIT Group Ltd.'; Url = 'https://anticheat-client.faceit-cdn.net/FACEITInstaller_64.exe'; File = 'faceit.exe'; Args = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' }
    @{ Name = 'DDU'; Detect = 'Display Driver Uninstaller'; Exe = "$env:ProgramFiles\Display Driver Uninstaller\Display Driver Uninstaller.exe"; Signer = 'Wagnardsoft'; File = 'ddu.exe'; Args = '/S'; Update = $true; Resolve = { $page = Get-DduPage (Get-Page 'https://www.wagnardsoft.com/display-driver-uninstaller-ddu'); if ($page) { $v = Get-DduVersion (Get-Page $page); if ($v) { @{ Url = (Get-DduUrl $v); Version = $v } } } } }
    @{ Name = 'AMD chipset'; Detect = 'AMD Chipset Software'; Signer = 'Advanced Micro Devices'; File = 'chipset.exe'; Args = '/S'; Update = $true; AmdOnly = $true; Headers = @{ Referer = 'https://www.amd.com/' }; Resolve = { $u = Get-ChipsetUrl (Get-Page 'https://www.amd.com/en/support/downloads/drivers.html/chipsets/am5/x870.html'); if ($u) { @{ Url = $u; Version = [regex]::Match($u, '_(\d+(?:\.\d+)+)\.exe$').Groups[1].Value } } } }
)

# ---------- main
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'PowerShell''i Yönetici olarak açıp komutu yeniden çalıştır.' -ForegroundColor Red
    exit 1
}
$work = Join-Path $Root 'Work'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$markerTs = Join-Path $Root 'teamspeak.txt'   # every TeamSpeak 6 beta reports 6.0.0, so the installed beta is kept here
Start-Transcript -Path (Join-Path $Root ('install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')) | Out-Null
$isAmd = (Get-CimInstance Win32_Processor | Select-Object -First 1).Manufacturer -eq 'AuthenticAMD'
$results = New-Object System.Collections.Generic.List[object]
$restart = $false

foreach ($app in $Apps) {
    $name = $app.Name
    try {
        if ($app.AmdOnly -and -not $isAmd) { continue }
        $have = Get-InstalledVersion $app.Detect $app.Exe
        if ($have -and -not $app.Update) { $results.Add([pscustomobject]@{ Name = $name; Result = 'zaten vardı'; Detail = $have }); continue }

        $url = $app.Url; $want = $null
        if ($app.Resolve) {
            $r = & $app.Resolve
            if (-not $r) { throw 'Üreticinin sayfasında indirme bağlantısı bulunamadı.' }
            $url = $r.Url; $want = $r.Version
        }
        if ($have -and $want) {
            $current = if ($name -eq 'TeamSpeak') { if (Test-Path $markerTs) { (Get-Content $markerTs -Raw).Trim() } else { '' } } else { $have }
            $same = if ($name -eq 'TeamSpeak') { $current -eq $want } else { -not (Test-Newer $current $want) }
            if ($same) { $results.Add([pscustomobject]@{ Name = $name; Result = 'zaten vardı'; Detail = $want }); continue }
        }

        Write-Host "$name indiriliyor..." -ForegroundColor Cyan
        # Spotify runs as the user, who cannot read the administrators-only work folder
        $dir = if ($app.AsUser) { $env:TEMP } else { $work }
        $file = Join-Path $dir $app.File
        $headers = if ($app.Headers) { $app.Headers } else { @{} }
        Save-Download $url $file $headers
        if (-not (Test-Signer $file $app.Signer)) {
            $s = Get-AuthenticodeSignature -LiteralPath $file
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            throw "İmza tutmadı ($($s.Status), $($s.SignerCertificate.Subject)); dosya çalıştırılmadı."
        }
        Write-Host "$name kuruluyor..." -ForegroundColor Cyan
        $code = if ($app.Msi) { Invoke-Installer "$env:SystemRoot\System32\msiexec.exe" "/i `"$file`" /qn /norestart" }
                elseif ($app.AsUser) { Invoke-AsUser $file $app.Args }
                else { Invoke-Installer $file $app.Args }
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        if ($code -eq -1) { throw 'Kurulum 15 dakikada bitmedi, durduruldu.' }
        if ($code -notin 0, 3010, 1641) { throw "Kurulum hata koduyla bitti: $code" }
        $now = $null
        for ($i = 0; $i -lt 15 -and -not $now; $i++) { $now = Get-InstalledVersion $app.Detect $app.Exe; if (-not $now) { Start-Sleep -Seconds 2 } }
        if (-not $now) { throw 'Kurulum bitti ama program Windows''ta görünmüyor.' }
        if ($name -eq 'TeamSpeak') { Set-Content -Path $markerTs -Value $want }
        if ($name -eq 'AMD chipset' -or $code -in 3010, 1641) { $restart = $true }
        $results.Add([pscustomobject]@{ Name = $name; Result = $(if ($have) { 'güncellendi' } else { 'kuruldu' }); Detail = $(if ($want) { $want } else { $now }) })
    }
    catch { $results.Add([pscustomobject]@{ Name = $name; Result = 'HATA'; Detail = $_.Exception.Message }) }
}
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
foreach ($r in $results) {
    $color = switch ($r.Result) { 'HATA' { 'Red' } 'zaten vardı' { 'Gray' } default { 'Green' } }
    Write-Host ('{0,-12} {1,-12} {2}' -f $r.Name, $r.Result, $r.Detail) -ForegroundColor $color
}
if ($restart) { Write-Host "`nChipset sürücüsü için bilgisayarı yeniden başlat." -ForegroundColor Yellow }
Stop-Transcript | Out-Null
if ($results | Where-Object Result -eq 'HATA') { exit 1 }
exit 0
