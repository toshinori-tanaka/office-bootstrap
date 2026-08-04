# =============================================================================
# bootstrap.ps1 — ◯◯-Office 導入の起動ファイル（オーナーがスタッフへ直接渡す 1 ファイル）
#
# 使い方（スタッフ）: このファイルを右クリック →「PowerShell で実行」
# 機能: 事前適合チェック → WSL2/Ubuntu 導入（再起動またぎ自動再開）→
#       Ubuntu 内ウィザードへ引き継ぎ → 定時ジョブ登録 → デスクトップショートカット
# 互換: Windows 標準 PowerShell 5.1（追加導入不要）。全ステップ冪等（再実行安全）
# =============================================================================

# ---- 設定（この 2 行のみ環境依存・オーナーが配布前に確認） -------------------
$BrainRepo = "https://github.com/toshinori-tanaka/office-core.git"
$Distro    = "Ubuntu"

$ErrorActionPreference = "Stop"
$StateDir  = Join-Path $env:LOCALAPPDATA "OfficeKit"
$StateFile = Join-Path $StateDir "state.txt"
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Say([string]$m)  { Write-Host "`n$m" -ForegroundColor Cyan }
function Info([string]$m) { Write-Host "  $m" }
function Ng([string]$m, [string]$fix) {
  Write-Host "  ✗ $m" -ForegroundColor Red
  if ($fix) { Write-Host "    対処: $fix" -ForegroundColor Yellow }
}
function Mark([string]$s) { if (-not (Test-Path $StateFile) -or -not (Select-String -Quiet -Pattern "^$s$" -Path $StateFile)) { Add-Content $StateFile $s } }
function Done([string]$s) { (Test-Path $StateFile) -and (Select-String -Quiet -Pattern "^$s$" -Path $StateFile) }

Say "◯◯-Office 導入ウィザード（Windows 側）へようこそ"
Info "途中で止まっても、もう一度このファイルを実行すれば続きから再開します。"

# ---- 管理者権限（必要なら自動で昇格し直す） ----------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
  Say "管理者権限で再起動します（表示されるダイアログで「はい」を押してください）"
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit 0
}

# ---- P1: 事前適合チェック -----------------------------------------------------
Say "P1. この PC が要件を満たすか検査します（何も変更しません）"
$ok = $true
$build = [System.Environment]::OSVersion.Version.Build
if ($build -ge 19041) { Info "✓ Windows のバージョン OK (build $build)" }
else { $ok = $false; Ng "Windows が古いです (build $build)" "Windows Update で最新化してください（Windows 10 2004 以降 / 11 が必要）" }

$hv = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
$vt = (Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled
if ($hv -or $vt) { Info "✓ 仮想化機能 OK" }
else { $ok = $false; Ng "仮想化機能が無効の可能性があります" "PC 起動時の BIOS/UEFI 設定で Virtualization (VT-x / SVM) を有効化。会社支給 PC は IT 部門へ（同梱の依頼ひな型を利用）" }

$free = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
if ($free -ge 10) { Info "✓ 空き容量 OK (${free}GB)" }
else { $ok = $false; Ng "C ドライブの空きが不足 (${free}GB)" "10GB 以上空けてから再実行してください" }

foreach ($h in @("github.com", "claude.ai")) {
  try {
    $null = Invoke-WebRequest -Uri "https://$h" -Method Head -TimeoutSec 10 -UseBasicParsing
    Info "✓ 接続 OK: $h"
  } catch {
    $ok = $false; Ng "接続できません: $h" "ネット接続を確認。会社ネットワークの場合は IT 部門へ（同梱の依頼ひな型を利用）"
  }
}
if (-not $ok) { Say "✗ 要件を満たしていません。上の対処を行ってから、もう一度実行してください。"; Read-Host "Enter で終了"; exit 1 }
Info "✓ P1 すべて合格"

# ---- P2: WSL2 + Ubuntu 導入（再起動またぎ対応） -------------------------------
$wslReady = $false
try { $null = wsl.exe -d $Distro -e true 2>$null; if ($LASTEXITCODE -eq 0) { $wslReady = $true } } catch {}
if (-not $wslReady) {
  Say "P2. Windows 内に小さな Linux 環境（Ubuntu）を導入します"
  # 再起動後の自動再開を仕込む（RunOnce）＋保険のデスクトップショートカット
  $resume = "powershell.exe -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "OfficeKitResume" -Value $resume
  $ws = New-Object -ComObject WScript.Shell
  $lnk = $ws.CreateShortcut((Join-Path $ws.SpecialFolders("Desktop") "セットアップを再開.lnk"))
  $lnk.TargetPath = "powershell.exe"; $lnk.Arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""; $lnk.Save()

  wsl.exe --install -d $Distro
  Say "PC の再起動が必要です。再起動後、セットアップは自動で再開します"
  Info "（自動で始まらない場合はデスクトップの「セットアップを再開」をダブルクリック）"
  Read-Host "Enter を押すと再起動します"
  Restart-Computer -Force
  exit 0
}
Info "✓ P2 Ubuntu OK"

# ---- P2b: Ubuntu の初期ユーザー確認 ------------------------------------------
$wu = (wsl.exe -d $Distro -e whoami 2>$null | Select-Object -First 1)
if (-not $wu -or $wu -eq "root") {
  Say "P2b. Ubuntu の初期設定（ユーザー名とパスワードの作成）が必要です"
  Info "これから開く黒い画面で、好きなユーザー名（半角英小文字）とパスワードを設定し、"
  Info "設定が終わったらその画面を閉じて、ここで Enter を押してください。"
  Start-Process wsl.exe -ArgumentList "-d $Distro"
  Read-Host "設定が終わったら Enter"
  $wu = (wsl.exe -d $Distro -e whoami 2>$null | Select-Object -First 1)
  if (-not $wu -or $wu -eq "root") { Ng "Ubuntu の初期設定が確認できません" "もう一度このファイルを実行してください"; Read-Host "Enter で終了"; exit 1 }
}
Info "✓ P2b Ubuntu ユーザー OK ($wu)"

# ---- P3: Ubuntu 内ウィザードへ引き継ぎ ---------------------------------------
if (-not (Done "P3")) {
  Say "P3. Ubuntu 内のセットアップを開始します（ここからは開く画面の日本語案内に従ってください）"
  $stage1 = @'
set -u
sudo apt-get update -qq && sudo apt-get install -y -qq gh git curl >/dev/null
until gh auth status >/dev/null 2>&1; do
  echo ""; echo "== GitHub に接続します（8 桁コードをブラウザに入力） =="
  echo "   アカウントが無い場合は先に https://github.com で無料作成を"
  gh auth login --web --git-protocol https || true
done
if [ ! -d "$HOME/.claude-brain/.git" ]; then
  echo "== 組織の頭脳を受信します（権限が無い場合はアカウント名をオーナーへ伝えて招待後に再実行） =="
  until gh repo clone "__REPO__" "$HOME/.claude-brain" -- -q 2>/dev/null || [ -d "$HOME/.claude-brain/.git" ]; do
    printf "  招待の Accept 後に Enter: "; read -r _
  done
fi
exec bash "$HOME/.claude-brain/wizard-setup.sh"
'@
  $repoPath = $BrainRepo -replace "https://github.com/", "" -replace "\.git$", ""
  $stage1 = $stage1 -replace "__REPO__", $repoPath
  $tmp = Join-Path $env:TEMP "office-stage1.sh"
  # LF 改行で保存（CRLF だと bash が誤動作するため）
  [IO.File]::WriteAllText($tmp, ($stage1 -replace "`r`n", "`n"))
  wsl.exe -d $Distro -u $wu -- bash -c "cp `$(wslpath '$tmp') ~/office-stage1.sh"
  wsl.exe -d $Distro -u $wu -- bash -lic "bash ~/office-stage1.sh"
  if ($LASTEXITCODE -ne 0) { Ng "Ubuntu 内セットアップが未完了です" "もう一度このファイルを実行すると続きから再開します"; Read-Host "Enter で終了"; exit 1 }
  Mark "P3"
}
Info "✓ P3 Ubuntu 内セットアップ完了"

# ---- P4: 定時ジョブの登録（PC 起動中に自動で回る仕組み） ----------------------
Say "P4. 自動ジョブを登録します（同期・記憶・教訓の 5 本）"
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd -ExecutionTimeLimit (New-TimeSpan -Hours 2)
function Register-OfficeTask([string]$name, [string]$cmd, $trigger) {
  $action = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d $Distro -u $wu -- bash -lc `"$cmd`""
  Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
  Info "✓ $name"
}
Register-OfficeTask "Office-Sync"    "bash ~/.claude-brain/office-sync.sh"              (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::MaxValue))
Register-OfficeTask "Office-SyncLogon" "bash ~/.claude-brain/office-sync.sh"            (New-ScheduledTaskTrigger -AtLogOn)
Register-OfficeTask "Office-R0"      "bash ~/.claude-brain/transcript-archive-auto.sh"  (New-ScheduledTaskTrigger -Daily -At 09:45)
Register-OfficeTask "Office-R1"      "bash ~/.claude-brain/transcript-extract-auto.sh"  (New-ScheduledTaskTrigger -Daily -At 11:00)
Register-OfficeTask "Office-R2"      "bash ~/.claude-brain/transcript-reconcile-auto.sh" (New-ScheduledTaskTrigger -Daily -At 11:30)
Register-OfficeTask "Office-Lessons" "bash ~/.claude-brain/lesson-distill-auto.sh"      (New-ScheduledTaskTrigger -Daily -At 12:00)

# ---- P5: デスクトップの起動ショートカット ------------------------------------
Say "P5. デスクトップに起動ショートカットを作ります"
$oname = (wsl.exe -d $Distro -u $wu -e cat /home/$wu/.claude/office-name 2>$null | Select-Object -First 1)
if (-not $oname) { $oname = "Office" }
$ws2 = New-Object -ComObject WScript.Shell
$sc = $ws2.CreateShortcut((Join-Path $ws2.SpecialFolders("Desktop") "$oname-Office.lnk"))
$sc.TargetPath = "wsl.exe"
$sc.Arguments  = "-d $Distro -u $wu -- bash -lic office"
$sc.Description = "秘書を起動（$oname-Office）"
$sc.Save()
Remove-Item (Join-Path $ws2.SpecialFolders("Desktop") "セットアップを再開.lnk") -ErrorAction SilentlyContinue
Info "✓ ショートカット「$oname-Office」作成"

Say "🎉 導入が完了しました！"
Info "デスクトップの「$oname-Office」をダブルクリック → 開いた画面で /office と打つと、"
Info "秘書との組織づくり（部門の相談）が始まります。おつかれさまでした。"
Read-Host "Enter で終了"
