; ── Support Client Installer ────────────────────────────────────────────────
; Silently installs RustDesk pre-configured with your support server.
; Build with: makensis windows.nsi

Unicode True

!include "MUI2.nsh"
!include "nsDialogs.nsh"
!include "LogicLib.nsh"

; ── Defines ───────────────────────────────────────────────────────────────────
!define APP_NAME     "Support Client"
!define INSTALL_DIR  "$PROGRAMFILES64\SupportClient"
!define RDSK_EXE     "$PROGRAMFILES64\SupportClient\rustdesk.exe"
!define CONFIG_DIR   "$APPDATA\RustDesk\config"
!define CONFIG_FILE  "$APPDATA\RustDesk\config\RustDesk2.toml"

; These are injected by build.sh from .env — fallback values shown below
!ifndef SERVER_HOST
  !define SERVER_HOST "your.domain.com"
!endif
!ifndef SERVER_KEY
  !define SERVER_KEY  "your-server-key"
!endif
!ifndef SERVER_URL
  !define SERVER_URL  "http://your.domain.com:3030"
!endif

Name        "${APP_NAME}"
OutFile     "SupportClient-Setup.exe"
InstallDir  "${INSTALL_DIR}"
RequestExecutionLevel admin
BrandingText " "

; ── MUI Settings ──────────────────────────────────────────────────────────────
!define MUI_ICON                     "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TITLE        "Support Client Setup"
!define MUI_WELCOMEPAGE_TEXT         "This will install the Support Client on your computer.$\r$\n$\r$\nAt the end you will get a short ID — share it with the support agent to start a session.$\r$\n$\r$\nClick Install to continue."
!define MUI_WELCOMEFINISHPAGE_BITMAP "${NSISDIR}\Contrib\Graphics\Wizard\win.bmp"
!define MUI_BUTTONTEXT_INSTALL       "Install"

; Pages — custom ID page replaces the MUI finish page
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_INSTFILES
Page custom IDPageShow IDPageLeave

!insertmacro MUI_LANGUAGE "English"

; ── Variables ─────────────────────────────────────────────────────────────────
Var RustDeskID
Var hIDField
Var hCopyBtn
Var hCopiedLabel

; ── Helpers ───────────────────────────────────────────────────────────────────
Function CopyIDToClipboard
  FileOpen  $0 "$TEMP\_rdid.txt" w
  FileWrite $0 "$RustDeskID"
  FileClose $0
  nsExec::Exec 'cmd /c clip < "$TEMP\_rdid.txt"'
  Delete "$TEMP\_rdid.txt"
FunctionEnd

; ── Custom finish page ────────────────────────────────────────────────────────
Function IDPageShow
  !insertmacro MUI_HEADER_TEXT \
    "You're all set!" \
    "Your Support ID is ready. Share it with the support agent."

  nsDialogs::Create 1018
  Pop $0
  ${If} $0 == error
    Abort
  ${EndIf}

  ; ── Success message ───────────────────────────────────────────────────────
  ${NSD_CreateLabel} 0 0 100% 18u "Your support team has been notified automatically."
  Pop $0

  ; ── ID display (for reference / manual fallback) ─────────────────────────
  ${NSD_CreateLabel} 0 26u 100% 12u "Your Support ID (for reference):"
  Pop $0

  ${NSD_CreateText} 0 42u 75% 18u "$RustDeskID"
  Pop $hIDField
  SendMessage $hIDField ${EM_SETREADONLY} 1 0
  SendMessage $hIDField ${EM_SETSEL}     0 -1

  ${NSD_CreateButton} 77% 42u 23% 18u "Copy"
  Pop $hCopyBtn
  ${NSD_OnClick} $hCopyBtn OnCopyBtnClick

  ${NSD_CreateLabel} 0 66u 100% 12u ""
  Pop $hCopiedLabel

  ; ── Next step ─────────────────────────────────────────────────────────────
  ${NSD_CreateLabel} 0 86u 100% 30u \
    "Keep RustDesk open in your taskbar and accept the incoming connection request from the support agent."
  Pop $0

  ; ── Rename Next → Finish, hide Back ──────────────────────────────────────
  GetDlgItem $0 $HWNDPARENT 1   ; Next/Finish button
  SendMessage $0 ${WM_SETTEXT} 0 "STR:Finish"
  GetDlgItem $0 $HWNDPARENT 3   ; Back button
  ShowWindow $0 ${SW_HIDE}

  nsDialogs::Show
FunctionEnd

Function OnCopyBtnClick
  Call CopyIDToClipboard
  ; Update the confirmation label
  SendMessage $hCopiedLabel ${WM_SETTEXT} 0 "STR:Copied!"
FunctionEnd

Function IDPageLeave
  ; Nothing to validate — user clicked Finish, let the installer exit
FunctionEnd

; ── Main install section ──────────────────────────────────────────────────────
Section "Main"

  ; ── 1. Install Support Client (Flutter build output) ─────────────────────
  SetOutPath "$INSTDIR"
  DetailPrint "Installing Support Client..."
  ; Bundle the entire Flutter release build directory (app\*)
  File /r "app\*.*"

  ; Create Start Menu and Desktop shortcuts
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "${RDSK_EXE}"
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "${RDSK_EXE}"

  ; Register uninstaller
  WriteUninstaller "$INSTDIR\Uninstall.lnk"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SupportClient" \
    "DisplayName" "${APP_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SupportClient" \
    "UninstallString" "$INSTDIR\Uninstall.lnk"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SupportClient" \
    "InstallLocation" "$INSTDIR"

  ; ── 2. Write config ───────────────────────────────────────────────────────
  DetailPrint "Configuring server..."
  CreateDirectory "${CONFIG_DIR}"
  FileOpen  $0 "${CONFIG_FILE}" w
  FileWrite $0 "[options]$\r$\n"
  FileWrite $0 'custom-rendezvous-server = "${SERVER_HOST}"$\r$\n'
  FileWrite $0 'key = "${SERVER_KEY}"$\r$\n'
  FileWrite $0 'relay-server = "${SERVER_HOST}"$\r$\n'
  FileWrite $0 'support-server-url = "${SERVER_URL}"$\r$\n'
  FileClose $0

  ; ── 3. Launch RustDesk and wait for ID ───────────────────────────────────
  DetailPrint "Starting RustDesk..."
  Exec '"${RDSK_EXE}"'
  Sleep 3000

  ; ── 4. Get ID by polling config file (avoids IPC dependency) ─────────────
  DetailPrint "Fetching your Support ID..."
  StrCpy $RustDeskID ""

  ; Write a PS1 that polls RustDesk2.toml for the id field (up to 30s)
  ; TOML id line is either:  id = "123456789"  or  id = 123456789
  FileOpen  $0 "$TEMP\_rd_getid.ps1" w
  FileWrite $0 '$$cfg = "$$env:APPDATA\RustDesk\config\RustDesk2.toml"; $$id = ""; for ($$i = 0; $$i -lt 15; $$i++) { if (Test-Path $$cfg) { $$line = (Get-Content $$cfg | Where-Object { $$_ -match "^id\s*=" } | Select-Object -First 1); if ($$line) { $$id = (($$line -split "=",2)[1].Trim()).Trim([char]34).Trim([char]39); if ($$id -ne "") { break } } }; Start-Sleep 2 }; Write-Output $$id'
  FileClose $0

  nsExec::ExecToStack 'powershell -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "$TEMP\_rd_getid.ps1"'
  Pop $0          ; exit code
  Pop $RustDeskID ; stdout = the ID (or empty)

  ; Trim any trailing whitespace/newlines
  ${If} $RustDeskID != ""
    StrCpy $RustDeskID $RustDeskID -1  ; strip trailing newline if present
  ${EndIf}

  Delete "$TEMP\_rd_getid.ps1"

  ; ── 5. Notify support server ──────────────────────────────────────────────
  ${If} $RustDeskID != ""
    DetailPrint "Notifying support server..."

    ; Write PS1 with ID value already expanded by NSIS at install time
    FileOpen  $0 "$TEMP\_rd_claim.ps1" w
    FileWrite $0 'try { Invoke-RestMethod -Uri "${SERVER_URL}/api/session/claim" -Method POST -ContentType "application/json" -Body (ConvertTo-Json @{rustdesk_id="$RustDeskID"} -Compress) -ErrorAction Stop } catch {}'
    FileClose $0

    nsExec::Exec 'powershell -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "$TEMP\_rd_claim.ps1"'
    Delete "$TEMP\_rd_claim.ps1"

    Call CopyIDToClipboard
    DetailPrint "Support team notified. Your ID: $RustDeskID"
  ${Else}
    StrCpy $RustDeskID "(open RustDesk to see your ID)"
    DetailPrint "Could not read ID — open RustDesk to find it."
  ${EndIf}

SectionEnd

; ── Uninstall section ─────────────────────────────────────────────────────────
Section Uninstall

  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  RMDir  "$SMPROGRAMS\${APP_NAME}"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  RMDir /r "$INSTDIR"

  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\SupportClient"

SectionEnd
