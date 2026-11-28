# =============================================================================
# bootstrap.ps1 — ◯◯-Office 導入の起動ファイル（オーナーがスタッフへ直接渡す 1 ファイル）
#
# 使い方（スタッフ）: このファイルを右クリック →「PowerShell で実行」
# 機能: 事前適合チェック → WSL2/Ubuntu 導入（再起動またぎ自動再開）→
#       Ubuntu 内ウィザードへ引き継ぎ → 定時ジョブ登録 → デスクトップショートカット
# 互換: Windows 標準 PowerShell 5.1（追加導入不要）。全ステップ冪等（再実行安全）
# =============================================================================

# ---- 設定（この 2 行のみ環境依存・オーナーが配布前に確認） -------------------
$BrainRepo = "https://github.com/Toshi-GA01/office-core.git"
$Distro    = "Ubuntu"

$ErrorActionPreference = "Stop"
$StateDir  = Join-Path $env:LOCALAPPDATA "OfficeKit"
$StateFile = Join-Path $StateDir "state.txt"
New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

function Say([string]$m)  { Write-Host "`n$m" -ForegroundColor Cyan }
function Info([string]$m) { Write-Host "  $m" }
# 画面の形（2026-11-16・見張りの文の決まり）: ✗ と「対処:」は続く導入の道具・最終自己検査と同じ形。
# 工程の番号・番地・英字の名前は人に向けた行に出さず、要る時だけ「詳しく:」の行に分ける（管理者が読む記録）
function Ng([string]$m, [string]$fix, [string]$detail) {
  Write-Host "  ✗ $m" -ForegroundColor Red
  if ($fix) { Write-Host "    対処: $fix" -ForegroundColor Yellow }
  if ($detail) { Write-Host "    詳しく: $detail" }
}
# 対処の決まり文句（導入の道具 wizard-setup.sh・健康診断と同じ字）
$FixAdmin = "この画面を撮って管理者へ送ってください（ご自身での操作は要りません）"
$FixRetry = "導入の 1 行を、もう一度実行してください（続きから再開します）"
function Mark([string]$s) { if (-not (Test-Path $StateFile) -or -not (Select-String -Quiet -Pattern "^$s$" -Path $StateFile)) { Add-Content $StateFile $s } }
function Done([string]$s) { (Test-Path $StateFile) -and (Select-String -Quiet -Pattern "^$s$" -Path $StateFile) }

# どんな予期しないエラーでも「表示して止まる」（黙って窓が閉じるのは禁止・2026-08-17 実機事故）
trap {
  Say "✗ 思わぬ問題が起きたので、止まりました"
  Info "対処: ${FixRetry}。同じ表示が続く時は、${FixAdmin}"
  Info ("詳しく: " + $_.Exception.Message)
  Read-Host "Enter で終了"
  exit 1
}

Say "導入を始めます（Windows 側の準備）"
Info "途中で止まっても、導入の 1 行をもう一度実行すれば、続きから再開します。"

# ---- 管理者権限（必要なら自動で昇格し直す） ----------------------------------
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
  Say "管理者の権限で開き直します。「ユーザーアカウント制御」の確認が出たら「はい」を押してください"
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit 0
}

# ---- P1: 事前適合チェック -----------------------------------------------------
Say "この PC で使えるかを確かめます（何も変えません）"
$ok = $true
$build = [System.Environment]::OSVersion.Version.Build
if ($build -ge 19041) { Info "✓ Windows の版は足りています" }
else { $ok = $false; Ng "Windows の版が古いです" "Windows Update で最新にしてから、導入の 1 行をもう一度実行してください" "Windows 10 の 2004 以降か Windows 11 が要ります（今の版: build ${build}）" }

$hv = (Get-CimInstance Win32_ComputerSystem).HypervisorPresent
$vt = (Get-CimInstance Win32_Processor | Select-Object -First 1).VirtualizationFirmwareEnabled
if ($hv -or $vt) { Info "✓ 仮想化の機能が使えます" }
else { $ok = $false; Ng "仮想化の機能が切られているようです" "会社から支給された PC なら、導入ガイドの付録の依頼文を IT 部門へ送ってください。ほかの PC なら、${FixAdmin}" "PC を起動する時の BIOS/UEFI の設定で Virtualization（VT-x / SVM）を有効にする" }

$free = [math]::Round((Get-PSDrive C).Free / 1GB, 1)
if ($free -ge 10) { Info "✓ C ドライブの空きは足りています（${free}GB）" }
else { $ok = $false; Ng "C ドライブの空きが足りません（今の空き: ${free}GB）" "C ドライブを 10GB 以上空けてから、導入の 1 行をもう一度実行してください" }

# 送り先は呼び名で言う（番地は「詳しく:」）。確かめる番地の一覧は変えない
$siteName = @{ "github.com" = "GitHub"; "claude.ai" = "Claude" }
foreach ($h in @("github.com", "claude.ai")) {
  $reachable = $false
  try {
    $null = Invoke-WebRequest -Uri "https://$h" -Method Head -TimeoutSec 10 -UseBasicParsing
    $reachable = $true
  } catch {
    # サーバーが HTTP 応答（403 等）を返した＝ネットワークは到達できている → 合格。
    # claude.ai は自動アクセス対策で HEAD に 403 を返すことがある（2026-08-17 実機で実証）。
    # 到達失敗（DNS 不可・タイムアウト・接続拒否）のときだけ Response が null になる
    if ($null -ne $_.Exception.Response) { $reachable = $true }
  }
  if ($reachable) { Info ("✓ " + $siteName[$h] + " につながります") }
  else { $ok = $false; Ng ($siteName[$h] + " につながりません") "インターネットにつながっているかを確かめて、導入の 1 行をもう一度実行してください。会社のネットワークなら、導入ガイドの付録の依頼文を IT 部門へ送ってください" "${h} に届かない" }
}
if (-not $ok) { Say "✗ この PC では、まだ導入を始められません。上の ✗ の項目のすぐ下にある「対処:」のとおりにしてください"; Read-Host "Enter で終了"; exit 1 }
Info "✓ この PC で使えます"

# ---- P2: WSL2 + Ubuntu 導入（再起動またぎ対応） -------------------------------
$wslReady = $false
try { $null = wsl.exe -d $Distro -e true 2>$null; if ($LASTEXITCODE -eq 0) { $wslReady = $true } } catch {}
if (-not $wslReady) {
  Say "Windows の中に、Linux の土台（Ubuntu）を入れます"
  # 再起動後の自動再開を仕込む（RunOnce）＋保険のデスクトップショートカット
  $resume = "powershell.exe -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce" -Name "OfficeKitResume" -Value $resume
  $ws = New-Object -ComObject WScript.Shell
  $lnk = $ws.CreateShortcut((Join-Path $ws.SpecialFolders("Desktop") "セットアップを再開.lnk"))
  $lnk.TargetPath = "powershell.exe"; $lnk.Arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""; $lnk.Save()

  wsl.exe --install -d $Distro
  Say "PC の再起動が要ります。再起動の後、続きが自動で始まります"
  Info "（自動で始まらない時は、デスクトップの「セットアップを再開」をダブルクリックしてください）"
  Read-Host "Enter を押すと再起動します"
  Restart-Computer -Force
  exit 0
}
Info "✓ Linux の土台（Ubuntu）が入っています"

# ---- P2b: Ubuntu の初期ユーザー確認 ------------------------------------------
$wu = (wsl.exe -d $Distro -e whoami 2>$null | Select-Object -First 1)
if (-not $wu -or $wu -eq "root") {
  Say "Ubuntu の初期設定（ユーザー名とパスワードを決める）をします"
  Info "これから開く黒い画面で、好きなユーザー名（半角英小文字）とパスワードを設定し、"
  Info "設定が終わったらその画面を閉じて、ここで Enter を押してください。"
  Start-Process wsl.exe -ArgumentList "-d $Distro"
  Read-Host "設定が終わったら Enter"
  $wu = (wsl.exe -d $Distro -e whoami 2>$null | Select-Object -First 1)
  if (-not $wu -or $wu -eq "root") { Ng "Ubuntu の初期設定を確かめられません" $FixRetry; Read-Host "Enter で終了"; exit 1 }
}
Info "✓ Ubuntu のユーザーが用意してあります（${wu}）"

# ---- P3: Ubuntu 内ウィザードへ引き継ぎ ---------------------------------------
if (-not (Done "P3")) {
  Say "Ubuntu 内のセットアップを始めます（ここからは、画面の日本語の案内どおりに進めてください）"
  $stage1 = @'
set -u
# 画面の文は導入の道具（wizard-setup.sh）の同じ場面の字にそろえる（同じ画面に続けて出る）
echo ""
echo "導入に使う道具を入れます（数分かかることがあります・パスワードを聞かれたら、この PC のパスワードを入力）"
until sudo apt-get update -qq && sudo apt-get install -y -qq gh git curl >/dev/null; do
  echo ""
  echo "✗ 導入に使う道具を入れられませんでした（パスワードの打ち間違いか、インターネットにつながっていないことが多いです）"
  echo "  対処: パスワードとインターネットを確かめてから Enter を押すと、もう一度試します（やめる時は Ctrl+C。導入の 1 行をもう一度実行すれば、続きから再開します）"
  read -r _
done
# gh 不在のまま下の接続ループへ進むと無限ループになる（2026-08-17 実機事故）。ここで必ず止める
command -v gh >/dev/null 2>&1 || { echo "✗ GitHub につなぐ道具を入れられませんでした"
  echo "  対処: この画面を撮って管理者へ送ってください（ご自身での操作は要りません）"
  echo "  詳しく: gh が無い"; exit 1; }
until gh auth status >/dev/null 2>&1; do
  echo ""; echo "GitHub につなぎます（ブラウザでの作業）"
  echo "  GitHub のアカウントが無い時は、先にブラウザで GitHub を開いて作ってください（無料）。"
  echo "  この後、画面に 8 桁のコードが出ます。開いたブラウザに、そのコードを入力してください。"
  gh auth login --web --git-protocol https || sleep 2
done
if [ ! -d "$HOME/.claude-brain/.git" ]; then
  echo ""; echo "全 PC 共通の決まりと道具を受け取ります"
  echo "  受け取る許可がまだ無いと、受信できません。その時は、GitHub のアカウント名を管理者へ伝えてください。"
  echo "  招待のメールが届いたら「Accept invitation」を押し、ここへ戻って Enter を押してください。"
  until gh repo clone "__REPO__" "$HOME/.claude-brain" -- -q 2>/dev/null || [ -d "$HOME/.claude-brain/.git" ]; do
    printf '  まだ受信できません。招待のメールで「Accept invitation」を押してから Enter（やめる時は Ctrl+C）: '; read -r _
  done
fi
# 再実行時は頭脳を最新化してから走る（配信済みの修正を確実に反映・ff のみ＝安全）
git -C "$HOME/.claude-brain" pull --ff-only -q 2>/dev/null || true
exec bash "$HOME/.claude-brain/wizard-setup.sh"
'@
  $repoPath = $BrainRepo -replace "https://github.com/", "" -replace "\.git$", ""
  $stage1 = $stage1 -replace "__REPO__", $repoPath
  $tmp = Join-Path $env:TEMP "office-stage1.sh"
  # LF 改行で保存（CRLF だと bash が誤動作するため）
  [IO.File]::WriteAllText($tmp, ($stage1 -replace "`r`n", "`n"))
  wsl.exe -d $Distro -u $wu -- bash -c "cp `$(wslpath '$tmp') ~/office-stage1.sh"
  wsl.exe -d $Distro -u $wu -- bash -lic "bash ~/office-stage1.sh"
  if ($LASTEXITCODE -ne 0) { Ng "Ubuntu 内のセットアップが終わっていません" $FixRetry; Read-Host "Enter で終了"; exit 1 }
  Mark "P3"
}
Info "✓ Ubuntu 内のセットアップが済んでいます"

# ---- P4: 定時ジョブの登録（PC 起動中に自動で回る仕組み） ----------------------
# 定義の単一ソースは頭脳側 office-tasks-converge.sh（間隔・時刻の変更は配信だけで
# 既存機にも自動反映される・2026-08-18）。ここは収束の実行と結果確認のみを行う。
# 通常はウィザード S9b で登録済み＝ここは照合のみで即完了（再実行の取り残し保険）
Say "Windows の定時の仕事を用意します（記録の自動の保存と受け取りなど）"
wsl.exe -d $Distro -u $wu -- bash -lc "bash ~/.claude-brain/office-tasks-converge.sh"
if ($LASTEXITCODE -ne 0) { Ng "Windows の定時の仕事を用意できませんでした" $FixRetry; Read-Host "Enter で終了"; exit 1 }
Info "✓ Windows の定時の仕事が用意してあります"

# ---- P5: デスクトップの起動ショートカット ------------------------------------
Say "デスクトップにアイコンを作ります"
$oname = (wsl.exe -d $Distro -u $wu -e cat /home/$wu/.claude/office-name 2>$null | Select-Object -First 1)
if (-not $oname) { $oname = "Office" }
$ws2 = New-Object -ComObject WScript.Shell
$sc = $ws2.CreateShortcut((Join-Path $ws2.SpecialFolders("Desktop") "$oname-Office.lnk"))
# Windows Terminal exists -> launch through it so Shift+Enter inserts a newline.
# Leaving the host to the system default can pick the legacy console, which cannot
# distinguish Shift+Enter from Enter (2026-09-04, reported from a staff PC).
$wtExe = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"
if (Test-Path $wtExe) {
  $sc.TargetPath = $wtExe
  $sc.Arguments  = "wsl.exe -d $Distro -u $wu -- bash -lic office"
} else {
  $sc.TargetPath = "wsl.exe"
  $sc.Arguments  = "-d $Distro -u $wu -- bash -lic office"
}
# The wt.exe above is an app execution alias with no icon of its own, so without an explicit icon
# the shortcut shows a blank page. Use the WSL penguin (the launcher's icon before 2026-09-04).
# Same rule as office-launcher-converge.sh, which restores it on machines installed earlier.
$wslIco = Join-Path $env:SystemRoot "System32\wsl.exe"
if (Test-Path $wslIco) { $sc.IconLocation = "$wslIco,0" }
$sc.Description = "秘書を起動（$oname-Office）"
$sc.Save()
Remove-Item (Join-Path $ws2.SpecialFolders("Desktop") "セットアップを再開.lnk") -ErrorAction SilentlyContinue
Info "✓ デスクトップに「${oname}-Office」のアイコンを作りました"

Say "導入が終わりました"
Info "デスクトップの「${oname}-Office」をダブルクリックし、開いた画面で /office と打つと、"
Info "秘書との組織づくりが始まります。おつかれさまでした。"
Read-Host "Enter で終了"
