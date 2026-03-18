[Setup]
AppName=Simonsen Flashcard
AppVersion=1.0
AppPublisher=Magnus Simonsen
DefaultDirName={autopf}\Simonsen Flashcard
DefaultGroupName=Simonsen Flashcard
OutputBaseFilename=SimonsenFlashcard_Setup
OutputDir=installer_output
Compression=lzma2
SolidCompression=yes
SetupIconFile=windows\runner\resources\app_icon.ico
WizardStyle=modern
PrivilegesRequired=lowest

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Simonsen Flashcard"; Filename: "{app}\simonsenflashcard.exe"
Name: "{commondesktop}\Simonsen Flashcard"; Filename: "{app}\simonsenflashcard.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Run]
Filename: "{app}\simonsenflashcard.exe"; Description: "Launch Simonsen Flashcard"; Flags: nowait postinstall skipifsilent
