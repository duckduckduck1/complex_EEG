# Собирает установщик приложения оператора ЭЭГ.
#
# Запускать из корня репозитория:
#   powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
#
# Что делает: собирает релизную сборку Flutter, читает версию из pubspec.yaml и
# передаёт её в Inno Setup, чтобы версия установщика не разъехалась с версией
# приложения. Готовый файл кладётся в build\installer\.
#
# Требуется установленный Inno Setup 6 (https://jrsoftware.org/isdl.php).
# Готовый setup.exe в репозиторий не коммитим — он уходит в GitHub Releases:
# каждая версия бинарника добавляла бы десятки мегабайт в историю git навсегда.

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Версия берётся из единственного источника правды — pubspec.yaml. Часть после
# «+» (номер сборки) Inno Setup не нужна.
$pubspec = Get-Content (Join-Path $root 'pubspec.yaml')
$versionLine = $pubspec | Where-Object { $_ -match '^version:' } | Select-Object -First 1
if (-not $versionLine) { throw 'Не нашёл version: в pubspec.yaml' }
$version = ($versionLine -replace '^version:\s*', '') -replace '\+.*$', ''
Write-Host "Версия приложения: $version"

Write-Host 'Собираю релизную сборку Flutter…'
Push-Location $root
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows завершился с ошибкой' }
}
finally {
    Pop-Location
}

$iscc = Get-Command 'ISCC.exe' -ErrorAction SilentlyContinue
if (-not $iscc) {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
    )
    $found = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $found) {
        throw 'Не нашёл ISCC.exe. Установите Inno Setup 6: https://jrsoftware.org/isdl.php'
    }
    $iscc = $found
}
else {
    $iscc = $iscc.Source
}

Write-Host 'Собираю установщик…'
& $iscc "/DAppVersion=$version" (Join-Path $PSScriptRoot 'eeg_app.iss')
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup завершился с ошибкой' }

Write-Host "Готово: build\installer\eeg-lab-setup-$version.exe"
