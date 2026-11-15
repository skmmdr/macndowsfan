Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "StrFunc.nsh"
${StrStr}
${UnStrStr}

; Never force-kill the app: its tray Quit restores firmware fan control.
!macro RequireAppClosed PHASE
  ${Do}
    nsExec::ExecToStack 'tasklist /FI "IMAGENAME eq ${APPEXE}" /NH'
    Pop $0
    Pop $1
    ${If} $0 != 0
      MessageBox MB_OK|MB_ICONSTOP "Could not check whether macndowsfan is running. Close it with Quit in its tray menu, then try again." /SD IDOK
      SetErrorLevel 1
      Abort
    ${EndIf}
    !if "${PHASE}" == "install"
      ${StrStr} $2 $1 "${APPEXE}"
    !else
      ${UnStrStr} $2 $1 "${APPEXE}"
    !endif
    ${If} $2 == ""
      ${ExitDo}
    ${EndIf}
    MessageBox MB_RETRYCANCEL|MB_ICONEXCLAMATION "Quit macndowsfan using its tray menu to restore automatic fan control, then choose Retry." /SD IDCANCEL IDRETRY +3
    SetErrorLevel 1
    Abort
  ${Loop}
!macroend

!define APPNAME "macndowsfan"
!define APPEXE "macndowsfan.exe"
!define APPVERSION "0.3.0"
!define PUBLISHER "macndowsfan"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\macndowsfan"
!define ROOT "${__FILEDIR__}\.."

Name "${APPNAME}"
OutFile "${__FILEDIR__}\output\macndowsfan-setup-${APPVERSION}.exe"
InstallDir "$PROGRAMFILES64\${APPNAME}"
InstallDirRegKey HKLM "Software\macndowsfan" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
BrandingText "${APPNAME} ${APPVERSION}"

VIProductVersion "${APPVERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "${APPNAME}"
VIAddVersionKey /LANG=1033 "FileDescription" "${APPNAME} installer"
VIAddVersionKey /LANG=1033 "FileVersion" "${APPVERSION}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${APPVERSION}"
VIAddVersionKey /LANG=1033 "CompanyName" "${PUBLISHER}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "MIT"

!define MUI_ABORTWARNING
!define MUI_ICON "${ROOT}\assets\macndowsfan.ico"
!define MUI_UNICON "${ROOT}\assets\macndowsfan.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APPEXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Launch ${APPNAME}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onInit
  SetRegView 64
FunctionEnd

Section "macndowsfan" SecMain
  SetShellVarContext all
  SetRegView 64

  !insertmacro RequireAppClosed install

  ; Clean registry entries written by older 32-bit installer builds.
  SetRegView 32
  DeleteRegKey HKLM "${UNINSTKEY}"
  DeleteRegKey HKLM "Software\macndowsfan"
  SetRegView 64

  SetOutPath "$INSTDIR"
  File /r /x "macndowsfan-setup-*.exe" "${ROOT}\dist\*.*"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\${APPEXE}"
  CreateShortcut "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk" "$INSTDIR\uninstall.exe"
  CreateShortcut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\${APPEXE}"

  WriteRegStr HKLM "Software\macndowsfan" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayVersion" "${APPVERSION}"
  WriteRegStr HKLM "${UNINSTKEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\${APPEXE}"
  WriteRegStr HKLM "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTKEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1

  ; Start with Windows for the user who ran the installer, hidden in the tray.
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${APPNAME}" '"$INSTDIR\${APPEXE}" --startup'

  ; Keep a local copy of the signed SMC driver so macndowsfan does not depend
  ; on the Macs Fan Control folder surviving.
  IfFileExists "$PROGRAMFILES32\Macs Fan Control\applesmc.sys" 0 no_driver_copy
    CopyFiles /SILENT "$PROGRAMFILES32\Macs Fan Control\applesmc.sys" "$INSTDIR\applesmc.sys"
  no_driver_copy:

  StrCpy $1 ""
  IfFileExists "$INSTDIR\applesmc.sys" 0 +2
    StrCpy $1 "$INSTDIR\applesmc.sys"
  ${If} $1 == ""
    IfFileExists "$PROGRAMFILES32\Macs Fan Control\applesmc.sys" 0 +2
      StrCpy $1 "$PROGRAMFILES32\Macs Fan Control\applesmc.sys"
  ${EndIf}

  ReadRegStr $0 HKLM "SYSTEM\CurrentControlSet\Services\AppleSMC" "ImagePath"
  ${If} $0 != ""
    ; If Macs Fan Control is gone but its driver path is still referenced,
    ; switch the service to our local copy.
    ${If} $1 == "$INSTDIR\applesmc.sys"
      IfFileExists "$PROGRAMFILES32\Macs Fan Control\MacsFanControl.exe" no_repoint
        nsExec::ExecToLog 'sc.exe config AppleSMC binPath= "\??\$INSTDIR\applesmc.sys"'
      no_repoint:
    ${EndIf}
    DetailPrint "Configuring AppleSMC driver for boot start..."
    nsExec::ExecToLog 'sc.exe config AppleSMC start= auto'
    nsExec::ExecToLog 'sc.exe start AppleSMC'
  ${ElseIf} $1 != ""
    DetailPrint "Creating AppleSMC driver service..."
    nsExec::ExecToLog 'sc.exe create AppleSMC type= kernel start= auto error= normal binPath= "\??\$1" DisplayName= "Apple SMC service"'
    nsExec::ExecToLog 'sc.exe start AppleSMC'
  ${Else}
    MessageBox MB_ICONEXCLAMATION|MB_OK "The AppleSMC driver was not found.$\r$\n$\r$\nInstall Macs Fan Control once so macndowsfan can access the fans and temperature sensors. The app is installed, but it will show a connection error until the driver exists."
  ${EndIf}
SectionEnd

Section "Uninstall"
  SetShellVarContext all

  !insertmacro RequireAppClosed uninstall

  ; Remove both 32- and 64-bit registry views (old builds registered 32-bit).
  SetRegView 32
  DeleteRegKey HKLM "${UNINSTKEY}"
  DeleteRegKey HKLM "Software\macndowsfan"
  SetRegView 64

  ; Remove the SMC service only if it was created against our local driver copy.
  ReadRegStr $0 HKLM "SYSTEM\CurrentControlSet\Services\AppleSMC" "ImagePath"
  StrCmp $0 "\??\$INSTDIR\applesmc.sys" 0 +3
    nsExec::ExecToLog 'sc.exe stop AppleSMC'
    nsExec::ExecToLog 'sc.exe delete AppleSMC'

  Delete "$DESKTOP\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\Uninstall ${APPNAME}.lnk"
  RMDir "$SMPROGRAMS\${APPNAME}"

  DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${APPNAME}"
  DeleteRegKey HKLM "${UNINSTKEY}"
  DeleteRegKey HKLM "Software\macndowsfan"

  IfSilent no_settings
  MessageBox MB_YESNO|MB_DEFBUTTON2 "Also remove saved settings and logs?" IDNO no_settings
  RMDir /r "$APPDATA\MacndowsFan"

no_settings:
  RMDir /r "$INSTDIR"
SectionEnd
