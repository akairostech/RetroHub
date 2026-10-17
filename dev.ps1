# Revisa el código, corre las pruebas y abre la app en Windows.
# Uso:  .\dev.ps1
Set-Location $PSScriptRoot
$log = Join-Path $PSScriptRoot 'check_log.txt'
"=== flutter analyze ===" | Out-File -FilePath $log -Encoding utf8
flutter analyze --no-fatal-infos 2>&1 | ForEach-Object { "$_" } | Tee-Object -Variable a | Write-Host
$a | Out-File -FilePath $log -Append -Encoding utf8
"=== flutter test ===" | Out-File -FilePath $log -Append -Encoding utf8
flutter test 2>&1 | ForEach-Object { "$_" } | Tee-Object -Variable t | Write-Host
$t | Out-File -FilePath $log -Append -Encoding utf8
flutter run -d windows
