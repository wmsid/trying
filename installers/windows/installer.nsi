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
!insertmacro WordFind
!insertmacro un.WordReplace

!if "${DISPLAY}" == ""
  !error "DISPLAY must not be empty"
!endif
!if "${BRAND}" == ""
  !error "BRAND must not be empty"
!endif
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
Var ResultBox
Var CopyBtn
Var PathNote
Var Connected
Var DnsName
Var IpAddr
Var DnsBox
Var IpBox

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
    ShowWindow $mui.FinishPage.Text ${SW_HIDE}
    ${If} $Connected == 1
      ${NSD_CreateLabel} 120u 45u 195u 14u "${DISPLAY} is installed and connected."
      Pop $0
      ${NSD_CreateLabel} 120u 64u 195u 10u "DNS name:"
      Pop $0
      ; read-only single-line boxes: selectable with the mouse / Ctrl+C
      nsDialogs::CreateControl EDIT "${DEFAULT_STYLES}|${WS_TABSTOP}|${ES_AUTOHSCROLL}|${ES_READONLY}" "${WS_EX_CLIENTEDGE}" 120u 75u 140u 13u "$DnsName"
      Pop $DnsBox
      ${NSD_CreateButton} 265u 74u 50u 14u "Copy"
      Pop $CopyBtn
      ${NSD_OnClick} $CopyBtn CopyResult
      ${NSD_CreateLabel} 120u 96u 195u 10u "IP address:"
      Pop $0
      nsDialogs::CreateControl EDIT "${DEFAULT_STYLES}|${WS_TABSTOP}|${ES_AUTOHSCROLL}|${ES_READONLY}" "${WS_EX_CLIENTEDGE}" 120u 107u 140u 13u "$IpAddr"
      Pop $IpBox
      ${NSD_CreateLabel} 120u 128u 195u 34u "Press Copy to copy the DNS name, or select any text above. Finish becomes available shortly.$PathNote"
      Pop $0
    ${Else}
      ; failure / other message: one read-only multi-line box
      nsDialogs::CreateControl EDIT "${DEFAULT_STYLES}|${WS_TABSTOP}|${WS_VSCROLL}|${ES_MULTILINE}|${ES_READONLY}" "${WS_EX_CLIENTEDGE}" 120u 45u 195u 110u "$FinishMsg"
      Pop $ResultBox
    ${EndIf}
    ; keep Finish disabled for 10 s so the result is not clicked past; the window X still closes setup
    GetDlgItem $FinishBtn $HWNDPARENT 1
    EnableWindow $FinishBtn 0
    StrCpy $Countdown 10
    SendMessage $FinishBtn ${WM_SETTEXT} 0 "STR:Finish ($Countdown)"
    ${NSD_CreateTimer} CountdownTick 1000
  ${EndIf}
FunctionEnd

Function CopyResult
  ; copy ONLY the DNS name
  SendMessage $DnsBox ${EM_SETSEL} 0 -1
  SendMessage $DnsBox ${WM_COPY} 0 0
  SendMessage $CopyBtn ${WM_SETTEXT} 0 "STR:Copied"
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

; Deletes only sub-keys whose name starts with "<DISPLAY>-" (the client's own NRPT rules), in case
; the service died without cleaning up and left a DNS rule pointing at a resolver that no longer exists.
!macro CleanOwnRules ROOT ID
  StrCpy $3 0
  StrLen $6 "${DISPLAY}-"
  loop_${ID}:
    EnumRegKey $4 HKLM "${ROOT}" $3
    StrCmp $4 "" done_${ID}
    StrCpy $5 $4 $6
    StrCmp $5 "${DISPLAY}-" del_${ID} skip_${ID}
    del_${ID}:
      DeleteRegKey HKLM "${ROOT}\$4"
      Goto loop_${ID}
    skip_${ID}:
      IntOp $3 $3 + 1
      Goto loop_${ID}
  done_${ID}:
!macroend

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
  ${If} $0 != 0
    StrCpy $PathNote "$\r$\n$\r$\nNote: ${DISPLAY} could not be added to PATH (your PATH was left unchanged). Run it as:$\r$\n$\"$INSTDIR\${BRAND}.exe$\" status"
  ${EndIf}
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
      StrCpy $Connected 1
      StrCpy $DnsName ""
      StrCpy $IpAddr ""
      StrCpy $R2 1
      parse_loop:
        ClearErrors
        ${WordFind} "$1" "$\n" "+$R2" $R3
        IfErrors parse_done
        StrCpy $R4 $R3 1 -1
        StrCmp $R4 "$\r" 0 +2
          StrCpy $R3 $R3 -1
        StrCpy $R4 $R3 12
        StrCmp $R4 "DNS domain: " 0 +3
          StrCpy $DnsName $R3 "" 12
          Goto next_line
        StrCmp $R4 "IP address: " 0 next_line
          StrCpy $IpAddr $R3 "" 12
        next_line:
        IntOp $R2 $R2 + 1
        Goto parse_loop
      parse_done:
      ${If} $DnsName == ""
        StrCpy $DnsName "(not reported)"
      ${EndIf}
      ${If} $IpAddr == ""
        StrCpy $IpAddr "(not reported)"
      ${EndIf}
      StrCpy $FinishMsg "connected"
    ${Else}
      StrCpy $Connected 0
      ; make the client's plain line breaks display properly in an edit box
      ClearErrors
      ${WordReplace} "$1" "$\r$\n" "$\n" "+*" $1
      ClearErrors
      ${WordReplace} "$1" "$\n" "$\r$\n" "+*" $1
      ClearErrors
      StrCpy $FinishMsg "${DISPLAY} is installed, but connecting failed (code $0).$\r$\n$\r$\n$1$\r$\n$\r$\nCheck the key, then run:$\r$\n${BRAND} up --setup-key <KEY>$PathNote"
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
  ; leftovers the service may not have removed (exact names only)
  !insertmacro CleanOwnRules "SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DnsPolicyConfig" local
  !insertmacro CleanOwnRules "SOFTWARE\Policies\Microsoft\Windows NT\DNSClient\DnsPolicyConfig" gpo
  nsExec::Exec '"$SYSDIR\netsh.exe" advfirewall firewall delete rule name="${DISPLAY}"'
  nsExec::Exec '"$SYSDIR\netsh.exe" advfirewall firewall delete rule name="${DISPLAY}-v6"'
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
