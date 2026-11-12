; ONE Windows setup program for every supported PC. It picks the right build at run time:
;   Windows 10/11 x64 -> amd64     Windows 10/11 ARM64 -> arm64
;   Windows 7/8/8.1 (64-bit) and any 32-bit Windows -> the Win7-compatible builds (if built with HAVE_WIN7)
; and it is both the installer and the updater:
;   - fresh machine: a setup key is required (wizard page, or /SETUPKEY= when silent)
;   - already set up (config found in %ProgramData%\<DISPLAY>): replaces the program, keeps the config,
;     reconnects as the same peer, no setup key needed (a supplied one is ignored)
; Build (see scripts/build.sh):
;   makensis -DBRAND=slbzt -DDISPLAY=SLBZT -DVERSION=1.1.0 -DWINDIR=<dir with amd64\ arm64\ [win7_amd64\ win7_386\]> [-DHAVE_WIN7] -DOUT=setup.exe installer.nsi
;   each subdir holds <BRAND>.exe and wintun.dll
; Silent install:  setup.exe /S /SETUPKEY=abcd   (optional /MGMT=https://other-server:443)
; Silent update:   setup.exe /S
; Silent uninstall: "%ProgramFiles%\slbzt\uninstall.exe" /S
Unicode true
ManifestSupportedOS all
!include MUI2.nsh
!include nsDialogs.nsh
!include LogicLib.nsh
!include FileFunc.nsh
!include WordFunc.nsh
!include x64.nsh
!include WinVer.nsh
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
InstallDir "$PROGRAMFILES\${BRAND}"   ; replaced in .onInit by the right Program Files for this PC

VIProductVersion "${VERSION}.0"
VIAddVersionKey "LegalCopyright" "${DISPLAY}"
VIAddVersionKey "ProductName" "${DISPLAY}"
VIAddVersionKey "FileDescription" "${DISPLAY} setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"

Var KeyBox
Var SetupKey
Var MgmtUrl
Var FinishMsg
Var FinishBtn
Var Countdown
Var ResultBox
Var CopyBtn
Var Connected
Var DnsName
Var IpAddr
Var DnsBox
Var IpBox
Var Variant        ; amd64 | arm64 | win7_amd64 | win7_386
Var Update         ; 1 = this PC is already set up -> update in place
Var WelcomeText
Var FinishTitle
Var Verb           ; "installed" / "updated"

!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "$WelcomeText"
!insertmacro MUI_PAGE_WELCOME
!define MUI_PAGE_CUSTOMFUNCTION_PRE SkipIfUpdate
!insertmacro MUI_PAGE_DIRECTORY
Page custom KeyPageCreate KeyPageLeave
!insertmacro MUI_PAGE_INSTFILES
!define MUI_FINISHPAGE_TITLE "$FinishTitle"
!define MUI_PAGE_CUSTOMFUNCTION_SHOW FinishShow
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"


Function .onInit
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}

  ; --- pick the build for this PC ---
  StrCpy $Variant ""
  ${If} ${IsNativeARM64}
    StrCpy $Variant "arm64"
  ${ElseIf} ${RunningX64}
    ${If} ${AtLeastBuild} 10240
      StrCpy $Variant "amd64"
    ${Else}
      !ifdef HAVE_WIN7
        StrCpy $Variant "win7_amd64"
      !endif
    ${EndIf}
  ${Else}
    !ifdef HAVE_WIN7
      StrCpy $Variant "win7_386"
    !endif
  ${EndIf}
  ${If} $Variant == ""
    MessageBox MB_OK|MB_ICONSTOP "${DISPLAY} does not support this version of Windows." /SD IDOK
    SetErrorLevel 6
    Abort
  ${EndIf}

  ; --- install folder: the previous one if any, else the native Program Files ---
  ReadRegStr $0 HKLM "Software\${BRAND}" "InstallDir"
  ${If} $0 != ""
    StrCpy $INSTDIR $0
  ${ElseIf} ${RunningX64}
    StrCpy $INSTDIR "$PROGRAMFILES64\${BRAND}"
  ${Else}
    StrCpy $INSTDIR "$PROGRAMFILES\${BRAND}"
  ${EndIf}

  ; --- fresh install or update? (the client's config lives in %ProgramData%\<DISPLAY>) ---
  SetShellVarContext all
  StrCpy $Update 0
  ${If} ${FileExists} "$APPDATA\${DISPLAY}\default.json"
  ${OrIf} ${FileExists} "$APPDATA\${DISPLAY}\config.json"
    StrCpy $Update 1
  ${EndIf}
  ${If} $Update == 1
    StrCpy $Verb "updated"
    StrCpy $FinishTitle "Update complete"
    StrCpy $WelcomeText "${DISPLAY} is already set up on this computer.$\r$\n$\r$\nSetup will update it to version ${VERSION}. Your settings and connection are kept; no setup key is needed.$\r$\n$\r$\nClick Next to continue."
  ${Else}
    StrCpy $Verb "installed"
    StrCpy $FinishTitle "Installation complete"
    StrCpy $WelcomeText "Setup will install ${DISPLAY} ${VERSION} and connect this computer.$\r$\n$\r$\nYou will need the setup key you were given.$\r$\n$\r$\nClick Next to continue."
  ${EndIf}

  ${GetParameters} $R0
  ${GetOptions} $R0 "/SETUPKEY=" $SetupKey
  ${GetOptions} $R0 "/MGMT=" $MgmtUrl
  ${If} $Update == 1
    StrCpy $SetupKey ""        ; already registered: never re-use a key
    StrCpy $MgmtUrl ""
  ${ElseIf} ${Silent}
    StrLen $0 $SetupKey
    ${If} $0 < 8
      SetErrorLevel 5          ; fresh install: setup key is mandatory: /S /SETUPKEY=<key>
      Abort
    ${EndIf}
  ${EndIf}
FunctionEnd

Function SkipIfUpdate
  ${If} $Update == 1
    Abort                      ; keep the existing install folder
  ${EndIf}
FunctionEnd

Function KeyPageCreate
  ${If} ${Silent}
  ${OrIf} $Update == 1
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
      ${NSD_CreateLabel} 120u 45u 195u 14u "${DISPLAY} ${VERSION} is $Verb and connected."
      Pop $0
      SetCtlColors $0 "" transparent
      ${NSD_CreateLabel} 120u 64u 195u 10u "DNS name:"
      Pop $0
      SetCtlColors $0 "" transparent
      ; read-only single-line boxes: selectable with the mouse / Ctrl+C
      nsDialogs::CreateControl EDIT "${DEFAULT_STYLES}|${WS_TABSTOP}|${ES_AUTOHSCROLL}|${ES_READONLY}" "${WS_EX_CLIENTEDGE}" 120u 75u 140u 13u "$DnsName"
      Pop $DnsBox
      ${NSD_CreateButton} 265u 74u 50u 14u "Copy"
      Pop $CopyBtn
      ${NSD_OnClick} $CopyBtn CopyResult
      ${NSD_CreateLabel} 120u 96u 195u 10u "IP address:"
      Pop $0
      SetCtlColors $0 "" transparent
      nsDialogs::CreateControl EDIT "${DEFAULT_STYLES}|${WS_TABSTOP}|${ES_AUTOHSCROLL}|${ES_READONLY}" "${WS_EX_CLIENTEDGE}" 120u 107u 140u 13u "$IpAddr"
      Pop $IpBox
      ${NSD_CreateLabel} 120u 128u 195u 34u "Press Copy to copy the DNS name, or select any text above. Finish becomes available shortly."
      Pop $0
      SetCtlColors $0 "" transparent
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

; Removes trailing CR, LF and spaces from the string on the stack top.
Function TrimEnd
  Exch $R0
  Push $R1
  trim_loop:
    StrCpy $R1 $R0 1 -1
    StrCmp $R1 "$\r" trim_cut
    StrCmp $R1 "$\n" trim_cut
    StrCmp $R1 " " trim_cut
    Goto trim_done
  trim_cut:
    StrCpy $R0 $R0 -1
    Goto trim_loop
  trim_done:
  Pop $R1
  Exch $R0
FunctionEnd

; Waits (up to ~15 s) until the service answers, so `up` does not race the service start.
Function WaitForService
  StrCpy $R5 0
  wait_loop:
    nsExec::ExecToStack '"$INSTDIR\${BRAND}.exe" status'
    Pop $R6
    Pop $R7
    ${If} $R6 == 0
      Return
    ${EndIf}
    IntOp $R5 $R5 + 1
    ${If} $R5 < 15
      Sleep 1000
      Goto wait_loop
    ${EndIf}
FunctionEnd

!macro PutFiles V
  File "/oname=${BRAND}.exe" "${WINDIR}/${V}/${BRAND}.exe"
  File "/oname=wintun.dll" "${WINDIR}/${V}/wintun.dll"
!macroend

Section "Install"
  InitPluginsDir
  SetOutPath "$INSTDIR"
  ; Stop the running copy (fresh install over a broken one, or an update); config is NOT touched
  IfFileExists "$INSTDIR\${BRAND}.exe" 0 +4
    nsExec::Exec '"$INSTDIR\${BRAND}.exe" service stop'
    nsExec::Exec '"$INSTDIR\${BRAND}.exe" service uninstall'
    Sleep 1500
  DetailPrint "Installing the $Variant build"
  ${If} $Variant == "arm64"
    !insertmacro PutFiles arm64
  ${ElseIf} $Variant == "amd64"
    !insertmacro PutFiles amd64
  !ifdef HAVE_WIN7
  ${ElseIf} $Variant == "win7_amd64"
    !insertmacro PutFiles win7_amd64
  ${ElseIf} $Variant == "win7_386"
    !insertmacro PutFiles win7_386
  !endif
  ${EndIf}
  WriteUninstaller "$INSTDIR\uninstall.exe"

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
  Call WaitForService

  ; Connect. Fresh install: with the key (passed via a temp file, not the command line).
  ; Update: the machine is already registered, so a plain `up` reconnects as the same peer.
  ${If} $Update == 1
    nsExec::ExecToStack '"$INSTDIR\${BRAND}.exe" up'
  ${Else}
    FileOpen $2 "$PLUGINSDIR\key.txt" w
    FileWrite $2 "$SetupKey"
    FileClose $2
    ${If} $MgmtUrl != ""
      nsExec::ExecToStack '"$INSTDIR\${BRAND}.exe" up --setup-key-file "$PLUGINSDIR\key.txt" --management-url "$MgmtUrl"'
    ${Else}
      nsExec::ExecToStack '"$INSTDIR\${BRAND}.exe" up --setup-key-file "$PLUGINSDIR\key.txt"'
    ${EndIf}
  ${EndIf}
  Pop $0
  Pop $1
  Delete "$PLUGINSDIR\key.txt"
  ${If} $0 == 0
    StrCpy $Connected 1
    StrCpy $DnsName ""
    StrCpy $IpAddr ""
    ; The name/IP can take a few seconds to appear after "up": ask the client's own `status` command
    ; (up to ~15 tries). `status --ipv4` prints just the IP; plain `status` has a "FQDN: <name>" line.
    StrCpy $R5 0
    poll_loop:
      ${If} $IpAddr == ""
        nsExec::ExecToStack '"$INSTDIR\${BRAND}.exe" status --ipv4'
        Pop $R6
        Pop $R7
        ${If} $R6 == 0
          Push $R7
          Call TrimEnd
          Pop $R7
          StrLen $R8 $R7
          ${If} $R8 >= 7
          ${AndIf} $R8 <= 15
            StrCpy $IpAddr $R7        ; the "no connection yet" help text is far longer than an IPv4 address
          ${EndIf}
        ${EndIf}
      ${EndIf}
      ${If} $DnsName == ""
        nsExec::ExecToStack '"$INSTDIR\${BRAND}.exe" status'
        Pop $R6
        Pop $R7
        ${If} $R6 == 0
          StrCpy $R2 1
          line_loop:
            ClearErrors
            ${WordFind} "$R7" "$\n" "E+$R2" $R3
            IfErrors line_done
            IntCmp $R2 60 line_done 0 line_done   ; hard cap: can never loop forever
            Push $R3
            Call TrimEnd
            Pop $R3
            StrCpy $R4 $R3 6
            StrCmp $R4 "FQDN: " 0 next_line
              StrCpy $DnsName $R3 "" 6
              Goto line_done
            next_line:
            IntOp $R2 $R2 + 1
            Goto line_loop
          line_done:
        ${EndIf}
      ${EndIf}
      ${If} $IpAddr != ""
      ${AndIf} $DnsName != ""
        Goto poll_done
      ${EndIf}
      IntOp $R5 $R5 + 1
      ${If} $R5 < 15
        Sleep 1000
        Goto poll_loop
      ${EndIf}
    poll_done:
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
    StrCpy $FinishMsg "${DISPLAY} ${VERSION} is $Verb, but connecting failed (code $0).$\r$\n$\r$\n$1$\r$\n$\r$\nCheck the key, then run (from the install folder):$\r$\n$\"$INSTDIR\${BRAND}.exe$\" up --setup-key <KEY>"
    SetErrorLevel 4
  ${EndIf}
SectionEnd

Function un.onInit
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}
FunctionEnd

Section "Uninstall"
  nsExec::Exec '"$INSTDIR\${BRAND}.exe" down'
  nsExec::Exec '"$INSTDIR\${BRAND}.exe" service stop'
  nsExec::Exec '"$INSTDIR\${BRAND}.exe" service uninstall'
  Sleep 1000
  ; leftovers the service may not have removed (exact names only)
  !insertmacro CleanOwnRules "SYSTEM\CurrentControlSet\Services\Dnscache\Parameters\DnsPolicyConfig" local
  !insertmacro CleanOwnRules "SOFTWARE\Policies\Microsoft\Windows NT\DNSClient\DnsPolicyConfig" gpo
  nsExec::Exec '"$SYSDIR\netsh.exe" advfirewall firewall delete rule name="${DISPLAY}"'
  nsExec::Exec '"$SYSDIR\netsh.exe" advfirewall firewall delete rule name="${DISPLAY}-v6"'
  Delete "$INSTDIR\${BRAND}.exe"
  Delete "$INSTDIR\wintun.dll"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  SetShellVarContext all
  RMDir /r "$APPDATA\${DISPLAY}"   ; %ProgramData%\<name> (config, logs)
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${BRAND}"
  DeleteRegKey HKLM "Software\${BRAND}"
SectionEnd
