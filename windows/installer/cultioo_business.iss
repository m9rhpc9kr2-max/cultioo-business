[Setup]
AppName=Cultioo Business
AppVersion={#AppVersion}
AppPublisher=Cultioo
AppPublisherURL=https://cultioo.com
AppSupportURL=https://cultioo.com
AppUpdatesURL=https://cultioo.com
DefaultDirName={autopf}\Cultioo Business
DefaultGroupName=Cultioo Business
AllowNoIcons=yes
OutputDir=installer_output
OutputBaseFilename=cultioo_business_setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "release_build\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Ensure we're copying the Windows desktop build, not web
; The release_build folder should contain: cultioo_business.exe and all DLLs

[Icons]
Name: "{group}\Cultioo Business"; Filename: "{app}\cultioo_business.exe"
Name: "{group}\{cm:UninstallProgram,Cultioo Business}"; Filename: "{uninstallexe}"
Name: "{commondesktop}\Cultioo Business"; Filename: "{app}\cultioo_business.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\cultioo_business.exe"; Description: "{cm:LaunchProgram,Cultioo Business}"; Flags: nowait postinstall skipifsilent
