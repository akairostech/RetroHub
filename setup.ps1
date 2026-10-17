# Configura el proyecto RetroHub: genera las carpetas de plataforma,
# instala dependencias, ajusta permisos de Android y verifica el código.
# Uso (desde esta carpeta):  powershell -ExecutionPolicy Bypass -File .\setup.ps1

$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot
$log = Join-Path $PSScriptRoot 'setup_log.txt'
"RetroHub setup $(Get-Date -Format s)" | Out-File -FilePath $log -Encoding utf8

function Step($title, [scriptblock]$cmd) {
    Write-Host "`n=== $title ===" -ForegroundColor Cyan
    "`n=== $title ===" | Out-File -FilePath $log -Append -Encoding utf8
    $out = & $cmd 2>&1 | ForEach-Object { "$_" }
    $out | Write-Host
    $out | Out-File -FilePath $log -Append -Encoding utf8
    "exit code: $LASTEXITCODE" | Out-File -FilePath $log -Append -Encoding utf8
}

Step 'flutter --version' { flutter --version }

# Genera windows/, linux/ y android/ sin tocar lib/, pubspec.yaml ni test/.
Step 'flutter create' { flutter create --project-name retro_hub --org com.rajiv --platforms windows,android,linux . }

Step 'flutter pub get' { flutter pub get }

# Permisos de Android: red local, broadcast y acceso a la carpeta Emulation.
$manifest = Join-Path $PSScriptRoot 'android\app\src\main\AndroidManifest.xml'
if (Test-Path $manifest) {
    $xml = [IO.File]::ReadAllText($manifest)
    if ($xml -notmatch 'MANAGE_EXTERNAL_STORAGE') {
        $perms = @'

    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
'@
        $xml = [regex]::Replace($xml, '(<manifest[^>]*>)', { param($m) $m.Value + $perms }, 1)
        $xml = [regex]::Replace($xml, '<application', '<application android:usesCleartextTraffic="true" android:requestLegacyExternalStorage="true"', 1)
        [IO.File]::WriteAllText($manifest, $xml)
        Write-Host "`nAndroidManifest.xml actualizado" -ForegroundColor Green
        "AndroidManifest.xml actualizado" | Out-File -FilePath $log -Append -Encoding utf8
    }
}

Step 'flutter analyze' { flutter analyze --no-fatal-infos }
Step 'flutter test' { flutter test }

Write-Host "`nListo. El resultado completo quedó en setup_log.txt" -ForegroundColor Green
Write-Host "Para abrir la app en Windows:  flutter run -d windows" -ForegroundColor Green
