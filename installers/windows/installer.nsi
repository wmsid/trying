; Windows setup program. Build with:
;   makensis -DBRAND=slbzt -DDISPLAY=SLBZT -DVERSION=1.0.0 -DARCH=x64 -DEXE=path\slbzt.exe -DWINTUN=path\wintun.dll -DOUT=setup.exe installer.nsi
; Silent install:  setup.exe /S /SETUPKEY=abcd        (optional: /MGMT=https://other-server:443)
; Silent uninstall: "%ProgramFiles%\slbzt\uninstall.exe" /S
Unicode true
!include MUI2.nsh
!include nsDialogs.nsh
!include LogicLib.nsh
!include FileFunc.nsh
!include StrFunc.nsh
!include WordFunc.nsh
${StrLoc}
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
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Var KeyBox
Var SetupKey
Var MgmtUrl

Function .onInit
  !if "${ARCH}" != "x86"
    SetRegView 64
  !endif
  ${GetParameters} $R0
  ${GetOptions} $R0 "/SETUPKEY=" $SetupKey
  ${GetOptions} $R0 "/MGMT=" $MgmtUrl
FunctionEnd

Function KeyPageCreate
  ${If} ${Silent}
    Abort
  ${EndIf}
  !insertmacro MUI_HEADER_TEXT "Connect" "Enter the setup key you were given (optional)."
  nsDialogs::Create 1018
  Pop $0
  ${NSD_CreateLabel} 0 0 100% 24u "Paste your setup key to connect this computer now. Leave empty to connect later with:$\r$\n${BRAND} up --setup-key <KEY>"
  Pop $0
  ${NSD_CreateText} 0 36u 100% 12u "$SetupKey"
  Pop $KeyBox
  nsDialogs::Show
FunctionEnd

Function KeyPageLeave
  ${NSD_GetText} $KeyBox $SetupKey
FunctionEnd

Section "Install"
  SetOutPath "$INSTDIR"
  ; Remove a previous install cleanly (ignore failures)
  IfFileExists "$INSTDIR\${BRAND}.exe" 0 +4
    nsExec::Exec '"$INSTDIR\${BRAND}.exe" service stop'
    nsExec::Exec '"$INSTDIR\${BRAND}.exe" service uninstall'
    Sleep 1000
  File "/oname=${BRAND}.exe" "${EXE}"
  File "/oname=wintun.dll" "${WINTUN}"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; PATH (machine-wide), only if missing
  ReadRegStr $0 HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path"
  ${StrLoc} $1 "$0;" "$INSTDIR;" ">"
  ${If} $1 == ""
    WriteRegExpandStr HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path" "$0;$INSTDIR"
    SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
  ${EndIf}

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
      nsExec::ExecToLog '"$INSTDIR\${BRAND}.exe" up --setup-key-file "$PLUGINSDIR\key.txt" --management-url "$MgmtUrl"'
    ${Else}
      nsExec::ExecToLog '"$INSTDIR\${BRAND}.exe" up --setup-key-file "$PLUGINSDIR\key.txt"'
    ${EndIf}
    Pop $0
    Delete "$PLUGINSDIR\key.txt"
    ${If} $0 != 0
      MessageBox MB_OK|MB_ICONEXCLAMATION "Installed, but connecting failed (code $0). Check the key and run:$\r$\n${BRAND} up --setup-key <KEY>" /SD IDOK
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
  Delete "$INSTDIR\${BRAND}.exe"
  Delete "$INSTDIR\wintun.dll"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  SetShellVarContext all
  RMDir /r "$APPDATA\${DISPLAY}"   ; %ProgramData%\<name> (config, logs)
  ReadRegStr $0 HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path"
  ${un.WordReplace} "$0" ";$INSTDIR" "" "+*" $1
  WriteRegExpandStr HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment" "Path" "$1"
  SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BRAND}"
  DeleteRegKey HKLM "Software\${BRAND}"
SectionEnd
