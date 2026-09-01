; Inno Setup 脚本 - WeChat Selkies 本地远程客户端 Windows 安装包
; 由 GitHub Actions 在构建 Windows 版后调用编译生成 .exe 安装程序。

#ifndef AppVersion
  #define AppVersion "5.0.0"
#endif

#define AppName "WeChat Selkies"
#define AppPublisher "WeChat Selkies Client"
#define AppExeName "wechat_selkies_client.exe"
#define AppURL "https://github.com/Songxwn/Docker-Wechat-Localclient"

[Setup]
AppId={{7C2F1E9A-3B4D-4E6F-9A21-WECHATSELKIES}}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\WeChat Selkies
DefaultGroupName=WeChat Selkies
DisableProgramGroupPage=yes
AllowNoIcons=yes
OutputBaseFilename=WeChat-Selkies-Client-{#AppVersion}-windows-x64-setup
OutputDir=installer
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Default.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; 将整个 Flutter Windows Release 目录打包
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\WeChat Selkies"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,WeChat Selkies}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\WeChat Selkies"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,WeChat Selkies}"; Flags: nowait postinstall skipifsilent
