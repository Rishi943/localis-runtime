; Localis Installer Script for Inno Setup 6.x
; ============================================================================
; This script creates a per-user installer for Localis that:
; - Installs to %LOCALAPPDATA%\Localis (no UAC required)
; - Creates Start Menu and optional Desktop shortcuts
; - Preserves user data across upgrades and reinstalls
; - Prompts before deleting personal data on uninstall (unless silent)
; ============================================================================

#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "Localis"
#define MyAppPublisher "Localis Project"
#define MyAppURL "https://github.com/yourusername/localis"
#define MyAppExeName "Localis.exe"

[Setup]
; ============================================================================
; IMPORTANT: AppId GUID - Generate once and NEVER change it!
; ============================================================================
; This GUID identifies your application across installations.
; To generate a new GUID: use Tools > Generate GUID in Inno Setup or
; PowerShell: [guid]::NewGuid()
; REPLACE THIS PLACEHOLDER WITH YOUR ACTUAL GUID:
AppId={{YOUR-GUID-HERE-REPLACE-ME-12345678-1234-1234-1234-123456789ABC}

; Basic Application Info
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}

; Per-user installation (no UAC prompt)
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; Installation Directory
DefaultDirName={localappdata}\{#MyAppName}
DisableDirPage=yes

; Start Menu
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes

; Output
OutputDir=output
OutputBaseFilename=LocalisSetup-{#MyAppVersion}
Compression=lzma2/max
SolidCompression=yes

; Uninstaller
UninstallDisplayName={#MyAppName}
UninstallDisplayIcon={app}\{#MyAppExeName}

; Visuals
WizardStyle=modern
; SetupIconFile=icon.ico
; Note: Icon file commented out (icon.ico not present - will use default Windows installer icon)

; Misc
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; ============================================================================
; PyInstaller Output (Localis.exe and its dependencies)
; ============================================================================
Source: "dist\Localis\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; ============================================================================
; Runtime Pack (Python, Git, and dependencies)
; ============================================================================
Source: "dist\runtime\*"; DestDir: "{app}\runtime"; Flags: ignoreversion recursesubdirs createallsubdirs

; ============================================================================
; Configuration File (only install if doesn't exist - preserve user changes)
; ============================================================================
Source: "dist\localis_runtime_config.json"; DestDir: "{app}"; Flags: onlyifdoesntexist uninsneveruninstall

; ============================================================================
; Visual C++ Redistributable (required for llama.dll)
; ============================================================================
Source: "dist\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Dirs]
; ============================================================================
; Create directories for user data (never deleted by uninstaller unless user confirms)
; ============================================================================
Name: "{app}\data"; Flags: uninsneveruninstall
Name: "{app}\models"; Flags: uninsneveruninstall
Name: "{app}\app"; Flags: uninsneveruninstall
Name: "{app}\updates"; Flags: uninsneveruninstall

[Icons]
; ============================================================================
; Shortcuts
; ============================================================================
; Start Menu shortcut (always created)
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

; Desktop shortcut (only if user selected the task)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; ============================================================================
; Post-install actions
; ============================================================================
; Launch Localis after installation (user can uncheck this)
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Pascal Script for Custom Install and Uninstall Behavior
// Global variable to track if restart is needed after VC++ installation
var
  VCRedistNeedsRestart: Boolean;

// Check if VC++ 2015-2022 x64 Redistributable is installed
function NeedsVCRedistX64(): Boolean;
var
  Installed: Cardinal;
begin
  // Check registry: HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64
  // Value "Installed" (DWORD) should be 1
  Result := True; // Default: assume not installed

  if RegQueryDWordValue(HKEY_LOCAL_MACHINE,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
      'Installed', Installed) then
  begin
    if Installed = 1 then
    begin
      Log('VC++ Redistributable already installed');
      Result := False;
    end
    else
    begin
      Log('VC++ Redistributable not installed (Installed value != 1)');
    end;
  end
  else
  begin
    Log('VC++ Redistributable not detected (registry key missing)');
  end;
end;

// Install VC++ Redistributable with proper exit code handling
procedure InstallVCRedist();
var
  VCRedistPath: String;
  ResultCode: Integer;
begin
  VCRedistPath := ExpandConstant('{tmp}\vc_redist.x64.exe');

  Log('Installing Visual C++ Redistributable from: ' + VCRedistPath);

  if not Exec(VCRedistPath, '/install /quiet /norestart', '', SW_HIDE,
      ewWaitUntilTerminated, ResultCode) then
  begin
    // Exec failed (couldn't launch the installer)
    MsgBox('Failed to launch Visual C++ Redistributable installer.' + #13#10 + #13#10 +
           'Localis may not function correctly without this component.' + #13#10 +
           'Please install the VC++ Redistributable manually from:' + #13#10 +
           'https://aka.ms/vs/17/release/vc_redist.x64.exe', mbError, MB_OK);
    VCRedistNeedsRestart := False;
  end
  else
  begin
    // Exec succeeded, check exit code
    Log('VC++ Redistributable installer exit code: ' + IntToStr(ResultCode));

    case ResultCode of
      0:
        begin
          Log('VC++ Redistributable installed successfully');
          VCRedistNeedsRestart := False;
        end;
      3010:
        begin
          Log('VC++ Redistributable installed successfully (restart required)');
          VCRedistNeedsRestart := True;
        end;
    else
      begin
        // Installation failed with unexpected exit code
        MsgBox('Visual C++ Redistributable installation failed with exit code ' + IntToStr(ResultCode) + '.' + #13#10 + #13#10 +
               'Localis may not function correctly without this component.' + #13#10 +
               'Please install the VC++ Redistributable manually from:' + #13#10 +
               'https://aka.ms/vs/17/release/vc_redist.x64.exe', mbError, MB_OK);
        VCRedistNeedsRestart := False;
      end;
    end;
  end;
end;

// Called during installation steps
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    // After files are installed, check and install VC++ if needed
    if NeedsVCRedistX64() then
    begin
      InstallVCRedist();
    end;
  end;
end;

// Query if restart is needed
function NeedRestart(): Boolean;
begin
  Result := VCRedistNeedsRestart;
end;

// ============================================================================
// Uninstall Behavior
// ============================================================================

// Uninstall event: Prompt user about deleting personal data
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DeleteUserData: Integer;
  AppDir: String;
  I: Integer;
  IsSilent: Boolean;
begin
  if CurUninstallStep = usUninstall then
  begin
    AppDir := ExpandConstant('{app}');

    // Check for silent mode using command-line parameters
    // (Cannot use WizardSilent() during uninstall - it's a WizardClient function)
    IsSilent := False;
    for I := 1 to ParamCount do
    begin
      if (CompareText(ParamStr(I), '/SILENT') = 0) or
         (CompareText(ParamStr(I), '/VERYSILENT') = 0) then
      begin
        IsSilent := True;
        Break;
      end;
    end;

    // Only prompt if NOT running in silent mode
    if not IsSilent then
    begin
      // Use SuppressibleMsgBox (works during uninstall, unlike MsgBox)
      DeleteUserData := SuppressibleMsgBox(
        'Do you want to delete all personal data?' + #13#10 + #13#10 +
        'This includes:' + #13#10 +
        '  • Downloaded models (models\)' + #13#10 +
        '  • Chat history and settings (data\)' + #13#10 +
        '  • Cached application code (app\)' + #13#10 +
        '  • Update files (updates\)' + #13#10 + #13#10 +
        'Choose "Yes" to delete everything and start fresh next time.' + #13#10 +
        'Choose "No" to keep your data for future installations.',
        mbConfirmation, MB_YESNO or MB_DEFBUTTON2, IDNO
      );

      if DeleteUserData = IDYES then
      begin
        // User chose YES - delete everything
        Log('User confirmed: Delete all personal data');

        // Delete data directories
        if DirExists(AppDir + '\data') then
          DelTree(AppDir + '\data', True, True, True);
        if DirExists(AppDir + '\models') then
          DelTree(AppDir + '\models', True, True, True);
        if DirExists(AppDir + '\app') then
          DelTree(AppDir + '\app', True, True, True);
        if DirExists(AppDir + '\updates') then
          DelTree(AppDir + '\updates', True, True, True);

        // Delete config file (user's customizations)
        if FileExists(AppDir + '\localis_runtime_config.json') then
          DeleteFile(AppDir + '\localis_runtime_config.json');

        // Delete log files
        if FileExists(AppDir + '\localis_launcher.log') then
          DeleteFile(AppDir + '\localis_launcher.log');
      end
      else
      begin
        // User chose NO - keep personal data
        Log('User confirmed: Keep personal data');
        // Do nothing - uninsneveruninstall flags will preserve the directories
      end;
    end
    else
    begin
      // Silent uninstall - default to keeping user data (safe default)
      Log('Silent uninstall: Keeping all personal data (default behavior)');
      // Do nothing - uninsneveruninstall flags will preserve the directories
    end;
  end;
end;

[UninstallDelete]
; ============================================================================
; Files to always delete on uninstall (these are NOT user data)
; ============================================================================
; Clean up any temporary or cache files that might have been created
Type: files; Name: "{app}\*.tmp"
Type: files; Name: "{app}\*.log"
Type: filesandordirs; Name: "{app}\__pycache__"

; Note: The main application files (Localis.exe, runtime\, etc.) are
; automatically removed by the uninstaller. The [Dirs] entries with
; uninsneveruninstall flags protect user data unless explicitly deleted
; in the CurUninstallStepChanged code above.
