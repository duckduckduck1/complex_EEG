; Установщик приложения оператора ЭЭГ для Windows.
;
; Собирается из уже готовой сборки Flutter: сначала `flutter build windows
; --release`, потом этот скрипт. Порядок и обе команды — в build_installer.ps1.
;
; Выбран Inno Setup, а не MSIX: MSIX требует подписи, и без покупного
; сертификата оператору пришлось бы вручную устанавливать самоподписанный
; сертификат перед установкой программы. Здесь же обычный setup.exe — дважды
; кликнул, и готово.

#define AppName "Лаборатория Умного сна"
#define AppExeName "eeg_app_max30003_stm32.exe"
#define AppPublisher "Лаборатория «Умного сна»"
; Версию передаёт build_installer.ps1 из pubspec.yaml, чтобы она не разъезжалась
; с версией приложения. Значение по умолчанию — на случай ручного запуска.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

[Setup]
; AppId менять нельзя: по нему Windows понимает, что это обновление уже
; установленной программы, а не вторая копия рядом.
AppId={{8F3A6C21-4D7E-4B69-9E2F-7A1C5D0B3E84}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\EEG Lab
DefaultGroupName={#AppName}
; Установка только для текущего пользователя: прав администратора не нужно,
; а в лаборатории оператор редко сидит под админом.
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=eeg-lab-setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Приложение только 64-битное — на 32-битной Windows ставиться не должно.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Дополнительно:"

[Files]
; Всё содержимое релизной сборки: exe, flutter_windows.dll, плагины и data\.
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Запустить {#AppName}"; Flags: nowait postinstall skipifsilent
