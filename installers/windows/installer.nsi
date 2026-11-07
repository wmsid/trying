; Windows setup program. Build with:
;   makensis -DBRAND=slbzt -DDISPLAY=SLBZT -DVERSION=1.0.0 -DARCH=x64 -DEXE=path\slbzt.exe -DWINTUN=path\wintun.dll -DPATHTOOL=path\pathtool.ps1 -DOUT=setup.exe installer.nsi
; Silent install:  setup.exe /S /SETUPKEY=abcd        (the key is REQUIRED; optional: /MGMT=https://other-server:443)
; Silent uninstall: "%ProgramFiles%\slbzt\uninstall.exe" /S
Unicode true
!include MUI2.nsh
!include nsDialogs.nsh
!include LogicLib.nsh
!include FileFunc.nsh
!include WordFunc.nsh
!insertmacro WordReplace
!insertmacro un.WordReplace

Name "${DISPLAY}"
OutFile "${OUT}"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
!if "${ARCH}" == "x86"
  InstallDir "$PROGRAMFILES32\${BRAND}"
!else
  InstallDir "$PROGRAMFILES64\${BRAND}"
!endif
InstallDirRegKey HKLM "Software\${BRAND}" "InstallDir"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "LegalCopyright" "${DISPLAY}"
VIAddVersionKey "ProductName" "${DISPLAY}"
VIAddVersionKey "FileDescription" "${DISPLAY} setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
Page custom KeyPageCreate KeyPageLeave
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "Installation complete"
!define MUI_PAGE_CUSTOMFUNCTION_SHOW FinishShow
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Var KeyBox
Var SetupKey
Var MgmtUrl
Var FinishMsg
Var FinishBtn
Var Countdown

Function .onInit
  !if "${ARCH}" != "x86"
    SetRegView 64
  !endif
  ${GetParameters} $R0
  ${GetOptions} $R0 "/SETUPKEY=" $SetupKey
  ${GetOptions} $R0 "/MGMT=" $MgmtUrl
  ${If} ${Silent}
    StrLen $0 $SetupKey
    ${If} $0 < 8
      SetErrorLevel 5          ; setup key is mandatory: /S /SETUPKEY=<key>
      Abort
    ${EndIf}
  ${EndIf}
FunctionEnd

Function KeyPageCreate
  ${If} ${Silent}
    Abort
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "Connect" "A setup key is required to install."
  nsDialogs::Create 1018
  Pop $0
  ${NSD_CreateLabel} 0 0 100% 24u "Paste the setup key you were given. Setup cannot continue without it, and it is used to connect this computer."
  Pop $0
  ${NSD_CreateText} 0 36u 100% 12u "$SetupKey"
  Pop $KeyBox
  nsDialogs::Show
FunctionEnd

Function KeyPageLeave
  ${NSD_GetText} $KeyBox $SetupKey
  StrLen $0 $SetupKey
  ${If} $0 < 8
    MessageBox MB_OK|MB_ICONEXCLAMATION "Please enter your setup key to continue."
    Abort                      ; stay on this page
  ${EndIf}
FunctionEnd

Function FinishShow
  ${If} $FinishMsg != ""
    ${NSD_SetText} $mui.FinishPage.Text "$FinishMsg"
    ; keep Finish disabled for 10 s so the result is not clicked past; the window X still closes setup
    GetDlgItem $FinishBtn $HWNDPARENT 1
    EnableWindow $FinishBtn 0
    StrCpy $Countdown 10
    SendMessage $FinishBtn ${WM_SETTEXT} 0 "STR:Finish ($Countdown)"
    ${NSD_CreateTimer} CountdownTick 1000
  ${EndIf}
FunctionEnd

Function CountdownTick
  IntOp $Countdown $Countdown - 1
  ${If} $Countdown <= 0
    ${NSD_KillTimer} CountdownTick
    EnableWindow $FinishBtn 1
    SendMessage $FinishBtn ${WM_SETTEXT} 0 "STR:Finish"
  ${Else}
    SendMessage $FinishBtn ${WM_SETTEXT} 0 "STR:Finish ($Countdown)"
  ${EndIf}
FunctionEnd

Section "Install"
  InitPluginsDir
  SetOutPath "$INSTDIR"
  ; Remove a previous install cleanly (ignore failures)
  IfFileExists "$INSTDIR\${BRAND}.exe" 0 +4
    nsExec::Exec '"$INSTDIR\${BRAND}.exe" service stop'
    nsExec::Exec '"$INSTDIR\${BRAND}.exe" service uninstall'
    Sleep 1000
  File "/oname=${BRAND}.exe" "${EXE}"
  File "/oname=wintun.dll" "${WINTUN}"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; PATH (machine-wide). Done by a PowerShell helper because NSIS strings are capped at 1024
  ; chars and would truncate a long PATH. The helper backs up the old PATH and fails safe.
  SetShellVarContext all
  File "/oname=$INSTDIR\pathtool.ps1" "${PATHTOOL}"
  nsExec::ExecToLog '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\pathtool.ps1" -Action add -Dir "$INSTDIR" -BackupDir "$APPDATA\${DISPLAY}"'
  Pop $0
  SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000

  ; Add/Remove Programs
  WriteRegStr HKLM "Software\${BRAND}" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BRAND}" "DisplayName" "${DISPLAY}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BRAND}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BRAND}" "Publisher" "${DISPLAY}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BRAND}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BRAND}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BRAND}" "NoModify" 1

  ; Background service
  nsExec::ExecToLog '"$INSTDIR\${BRAND}.exe" service install'
  Pop $0
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONSTOP "Service install failed (code $0)." /SD IDOK
    SetErrorLevel 2
    Abort
  ${EndIf}
  nsExec::ExecToLog '"$INSTDIR\${BRAND}.exe" service start'
  Pop $0
  ${If} $0 != 0
    MessageBox MB_OK|MB_ICONSTOP "Service start failed (code $0)." /SD IDOK
    SetErrorLevel 3
    Abort
  ${EndIf}

  ; Connect if a key was supplied (passed via a temp file, not the command line)
  ${If} $SetupKey != ""
    Sleep 3000
    FileOpen $2 "$PLUGINSDIR\key.txt" w
    FileWrite $2 "$SetupKey"
    FileClose $2
    ${If} $MgmtUrl != ""
      nsExec::ExecToStack '"$INSTDIR\${BRAND}.exe" up --setup-key-file "$PLUGINSDIR\key.txt" --management-url "$MgmtUrl"'
    ${Else}
      nsExec::ExecToStack '"$INSTDIR\${BRAND}.exe" up --setup-key-file "$PLUGINSDIR\key.txt"'
    ${EndIf}
    Pop $0
    Pop $1
    Delete "$PLUGINSDIR\key.txt"
    ${If} $0 == 0
      ; $1 holds: Connected / DNS domain: ... / IP address: ...
      StrCpy $FinishMsg "${DISPLAY} is installed and connected.$\r$\n$\r$\n$1$\r$\n$\r$\nNote these down, then click Finish when it becomes available."
    ${Else}
      StrCpy $FinishMsg "${DISPLAY} is installed, but connecting failed (code $0).$\r$\n$\r$\n$1$\r$\n$\r$\nCheck the key, then run:$\r$\n${BRAND} up --setup-key <KEY>"
      SetErrorLevel 4
    ${EndIf}
  ${EndIf}
SectionEnd

Section "Uninstall"
  !if "${ARCH}" != "x86"
    SetRegView 64
  !endif
  nsExec::Exec '"$INSTDIR\${BRAND}.exe" down'
  nsExec::Exec '"$INSTDIR\${BRAND}.exe" service stop'
  nsExec::Exec '"$INSTDIR\${BRAND}.exe" service uninstall'
  Sleep 1000
  ; take our folder off the machine PATH first (uses the helper that setup installed)
  nsExec::Exec '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\pathtool.ps1" -Action remove -Dir "$INSTDIR"'
  Pop $0
  SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
  Delete "$INSTDIR\pathtool.ps1"
  Delete "$INSTDIR\${BRAND}.exe"
  Delete "$INSTDIR\wintun.dll"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  SetShellVarContext all
  RMDir /r "$APPDATA\${DISPLAY}"   ; %ProgramData%\<name> (config, logs)
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BRAND}"
  DeleteRegKey HKLM "Software\${BRAND}"
SectionEnd
