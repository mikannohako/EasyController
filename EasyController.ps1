$ErrorActionPreference = "Stop"

$script:DefaultRepositoryUrl = "https://github.com/mikannohako/EasyController.git"
$script:ConfigPath = Join-Path $PSScriptRoot "config.ini"
$script:ProgressState = $null

function Write-ECHeader {
    Clear-Host
    Write-Host ""
    Write-Host "  Easy Controller" -ForegroundColor Cyan
    Write-Host "  Git / Jujutsu project toolkit" -ForegroundColor DarkCyan
    Write-Host "  $('-' * 42)" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-StageProgress {
    param(
        [Parameter(Mandatory)] [int] $Current,
        [Parameter(Mandatory)] [int] $Total,
        [Parameter(Mandatory)] [string] $Activity,
        [Parameter(Mandatory)] [string] $Status
    )

    $percent = [math]::Round(($Current / $Total) * 100)
    $script:ProgressState = @{
        Current = $Current
        Total = $Total
        Activity = $Activity
        Status = $Status
    }
    try {
        $windowWidth = [Console]::WindowWidth
        $barWidth = [math]::Max(10, [math]::Min(40, $windowWidth - 42))
        $filledWidth = [math]::Round(($percent / 100) * $barWidth)
        $bar = ('#' * $filledWidth).PadRight($barWidth, '-')
        $line = "  $Activity [$bar] $percent% $Status"
        if ($line.Length -ge $windowWidth) {
            $line = $line.Substring(0, $windowWidth - 1)
        }

        $originalLeft = [Console]::CursorLeft
        $originalTop = [Console]::CursorTop
        [Console]::SetCursorPosition(0, [Console]::WindowHeight - 1)
        [Console]::Write($line.PadRight($windowWidth - 1))
        [Console]::SetCursorPosition($originalLeft, $originalTop)
    }
    catch {
        Write-Host "[$percent%] $Activity - $Status" -ForegroundColor DarkCyan
    }
}

function Clear-StageProgress {
    try {
        $windowWidth = [Console]::WindowWidth
        $originalLeft = [Console]::CursorLeft
        $originalTop = [Console]::CursorTop
        [Console]::SetCursorPosition(0, [Console]::WindowHeight - 1)
        [Console]::Write((' ' * ($windowWidth - 1)))
        [Console]::SetCursorPosition($originalLeft, $originalTop)
    }
    catch {
    }
}

function Invoke-RequiredCommand {
    param(
        [Parameter(Mandatory)] [string] $Command,
        [Parameter(Mandatory)] [string[]] $Arguments
    )

    $hasProgress = $null -ne $script:ProgressState
    if ($hasProgress) {
        Clear-StageProgress
    }

    try {
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "コマンドに失敗しました: $Command $($Arguments -join ' ')"
        }
    }
    finally {
        if ($hasProgress -and $null -ne $script:ProgressState) {
            $progress = $script:ProgressState
            Write-StageProgress -Current $progress.Current -Total $progress.Total -Activity $progress.Activity -Status $progress.Status
        }
    }
}

function Test-CommandAvailable {
    param([Parameter(Mandatory)] [string] $Name)

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Read-ECConfig {
    $config = @{}
    if (-not (Test-Path $script:ConfigPath)) {
        return $config
    }

    foreach ($line in [System.IO.File]::ReadAllLines($script:ConfigPath)) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith("#") -or $trimmedLine.StartsWith("[")) {
            continue
        }

        $separator = $trimmedLine.IndexOf('=')
        if ($separator -gt 0) {
            $key = $trimmedLine.Substring(0, $separator).Trim()
            $value = $trimmedLine.Substring($separator + 1).Trim()
            $config[$key] = $value
        }
    }

    return $config
}

function Save-ECConfig {
    param(
        [Parameter(Mandatory)] [string] $UserName,
        [Parameter(Mandatory)] [string] $UserEmail,
        [string] $RepositoryUrl = $script:DefaultRepositoryUrl
    )

    $lines = @(
        "[user]",
        "name=$UserName",
        "email=$UserEmail",
        "repository_url=$RepositoryUrl",
        ""
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($script:ConfigPath, $lines, $utf8NoBom)
    Write-Host "設定を保存しました: $script:ConfigPath" -ForegroundColor Green
}

function Get-ECRepositoryUrl {
    $config = Read-ECConfig
    $repositoryUrl = [string] $config["repository_url"]
    if ([string]::IsNullOrWhiteSpace($repositoryUrl)) {
        return $script:DefaultRepositoryUrl
    }
    return $repositoryUrl
}

function Read-ECRepositorySettings {
    param([Parameter(Mandatory)] [hashtable] $UserSettings)

    $currentRepositoryUrl = Get-ECRepositoryUrl
    Write-Host ""
    Write-Host "cloneするリポジトリを選択してください。" -ForegroundColor Cyan
    $repositoryUrl = Read-Host "リポジトリURL [$currentRepositoryUrl]"
    if ([string]::IsNullOrWhiteSpace($repositoryUrl)) {
        $repositoryUrl = $currentRepositoryUrl
    }
    Test-ECRepositoryUrl -RepositoryUrl $repositoryUrl

    $saveDecision = Read-Host "このリポジトリURLを設定に保存しますか？ [Y/n/C]"
    if ([string]::IsNullOrWhiteSpace($saveDecision) -or $saveDecision -match '^(?i)y(es)?$') {
        Save-ECConfig -UserName $UserSettings.Name -UserEmail $UserSettings.Email -RepositoryUrl $repositoryUrl
    }
    elseif ($saveDecision -match '^(?i)c(ancel)?$') {
        throw "リポジトリ選択をキャンセルしました。"
    }
    else {
        Write-Host "リポジトリURLは保存せず、今回のセットアップだけで利用します。" -ForegroundColor Yellow
    }

    return $repositoryUrl
}

function Test-ECRepositoryUrl {
    param([Parameter(Mandatory)] [string] $RepositoryUrl)

    if ($RepositoryUrl -match '^git@[^:]+:.+$') {
        return
    }

    $uri = $null
    if (-not [Uri]::TryCreate($RepositoryUrl, [UriKind]::Absolute, [ref] $uri) -or $uri.Scheme -notin @("http", "https", "ssh", "git")) {
        throw "リポジトリURLが正しくありません。"
    }
}

function Read-ECSaveDecision {
    $decision = Read-Host "設定を保存しますか？ [Y/n/C]"
    if ([string]::IsNullOrWhiteSpace($decision) -or $decision -match '^(?i)y(es)?$') {
        return "save"
    }
    if ($decision -match '^(?i)c(ancel)?$') {
        return "cancel"
    }
    return "skip"
}

function Read-ECUserSettings {
    $config = Read-ECConfig
    $savedName = [string] $config["name"]
    $savedEmail = [string] $config["email"]
    $hasSavedSettings = -not [string]::IsNullOrWhiteSpace($savedName) -and -not [string]::IsNullOrWhiteSpace($savedEmail)

    if ($hasSavedSettings) {
        Write-Host "保存済みの設定が見つかりました。" -ForegroundColor Cyan
        Write-Host "  名前: $savedName" -ForegroundColor DarkGray
        Write-Host "  メール: $savedEmail" -ForegroundColor DarkGray
        $useSavedSettings = Read-Host "この設定を利用しますか？ [Y/n]"
        if ([string]::IsNullOrWhiteSpace($useSavedSettings) -or $useSavedSettings -match '^(?i)y(es)?$') {
            return @{ Name = $savedName; Email = $savedEmail }
        }
    }

    $userName = Read-Host "Git ユーザー名"
    $userEmail = Read-Host "Git メールアドレス"
    if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($userEmail)) {
        throw "名前とメールアドレスは必須です。"
    }

    $saveDecision = Read-ECSaveDecision
    if ($saveDecision -eq "cancel") {
        throw "設定の保存をキャンセルしました。"
    }
    if ($saveDecision -eq "save") {
        Save-ECConfig -UserName $userName -UserEmail $userEmail -RepositoryUrl (Get-ECRepositoryUrl)
    }
    else {
        Write-Host "設定は保存せず、この処理でのみ利用します。" -ForegroundColor Yellow
    }
    return @{ Name = $userName; Email = $userEmail }
}

function Invoke-ConfigChange {
    Write-ECHeader
    try {
        $config = Read-ECConfig
        $currentName = [string] $config["name"]
        $currentEmail = [string] $config["email"]
        $currentRepositoryUrl = Get-ECRepositoryUrl

        Write-Host "設定を変更します。空入力なら現在の値を維持します。" -ForegroundColor Cyan
        $newName = Read-Host "Git ユーザー名 [$currentName]"
        $newEmail = Read-Host "Git メールアドレス [$currentEmail]"
        $newRepositoryUrl = Read-Host "リポジトリURL [$currentRepositoryUrl]"
        if ([string]::IsNullOrWhiteSpace($newName)) { $newName = $currentName }
        if ([string]::IsNullOrWhiteSpace($newEmail)) { $newEmail = $currentEmail }
        if ([string]::IsNullOrWhiteSpace($newRepositoryUrl)) { $newRepositoryUrl = $currentRepositoryUrl }
        if ([string]::IsNullOrWhiteSpace($newName) -or [string]::IsNullOrWhiteSpace($newEmail)) {
            throw "名前とメールアドレスは必須です。"
        }
        Test-ECRepositoryUrl -RepositoryUrl $newRepositoryUrl

        $saveDecision = Read-ECSaveDecision
        if ($saveDecision -eq "cancel") {
            Write-Host "設定変更をキャンセルしました。" -ForegroundColor Yellow
            return
        }
        if ($saveDecision -eq "save") {
            Save-ECConfig -UserName $newName -UserEmail $newEmail -RepositoryUrl $newRepositoryUrl
        }
        else {
            Write-Host "設定は変更せず終了しました。" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Update-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathEntries = @($machinePath, $userPath) | Where-Object { $_ } | ForEach-Object {
        $_ -split ';' | Where-Object { $_ }
    }

    $env:Path = ($pathEntries | Select-Object -Unique) -join ';'
    Write-Host "PATH を再読み込みしました。" -ForegroundColor Green
}

function Install-RequiredTools {
    if (-not (Test-CommandAvailable "winget")) {
        throw "winget が見つかりません。Windows App Installer をインストールしてください。"
    }

    Write-Host "winget を確認しました。" -ForegroundColor Green

    if (-not (Test-CommandAvailable "git")) {
        Write-Host "Git をインストールしています..." -ForegroundColor Yellow
        Invoke-RequiredCommand "winget" @("install", "--id", "Git.Git", "--exact", "--source", "winget")
        Write-Host "Git のインストールが完了しました。" -ForegroundColor Green
    }
    else {
        Write-Host "Git はインストール済みです。" -ForegroundColor DarkGray
    }

    if (-not (Test-CommandAvailable "jj")) {
        Write-Host "Jujutsu (jj) をインストールしています..." -ForegroundColor Yellow
        Invoke-RequiredCommand "winget" @("install", "--id", "jj-vcs.jj", "--exact", "--source", "winget")
        Write-Host "jj のインストールが完了しました。" -ForegroundColor Green
    }
    else {
        Write-Host "jj はインストール済みです。" -ForegroundColor DarkGray
    }

    Update-ProcessPath
}

function Select-ECProjectDirectory {
    $projectName = Read-Host "プロジェクトフォルダ名"
    if ([string]::IsNullOrWhiteSpace($projectName)) {
        throw "プロジェクトフォルダ名が入力されていません。"
    }

    $invalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()
    if ($projectName.IndexOfAny($invalidCharacters) -ge 0 -or $projectName -in @('.', '..')) {
        throw "プロジェクトフォルダ名に使用できない文字が含まれています。"
    }

    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "プロジェクトを置く親フォルダを選択してください"
    $dialog.ShowNewFolderButton = $true
    $dialog.SelectedPath = [Environment]::GetFolderPath("Desktop")

    try {
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            throw "プロジェクトフォルダの選択をキャンセルしました。"
        }

        $projectDirectory = Join-Path $dialog.SelectedPath $projectName
        if (Test-Path $projectDirectory) {
            if (-not (Test-Path $projectDirectory -PathType Container)) {
                throw "同名のファイルが既に存在します: $projectDirectory"
            }
            if (@(Get-ChildItem -LiteralPath $projectDirectory -Force).Count -gt 0) {
                throw "選択した場所に既存のファイルがあります: $projectDirectory"
            }
        }

        return $projectDirectory
    }
    finally {
        $dialog.Dispose()
    }
}

function Initialize-ECRepository {
    $projectDirectory = Select-ECProjectDirectory

    New-Item -ItemType Directory -Path $projectDirectory -Force | Out-Null
    Set-Location $projectDirectory

    $userSettings = Read-ECUserSettings
    $repositoryUrl = Read-ECRepositorySettings -UserSettings $userSettings

    Invoke-RequiredCommand "jj" @("config", "set", "--user", "user.name", $userSettings.Name)
    Invoke-RequiredCommand "jj" @("config", "set", "--user", "user.email", $userSettings.Email)

    Write-Host "リポジトリを取得しています..." -ForegroundColor Yellow
    Invoke-RequiredCommand "jj" @("git", "clone", $repositoryUrl, ".")
    explorer.exe $projectDirectory

    Write-Host "セットアップ先: $projectDirectory" -ForegroundColor Green
}

function Invoke-Setup {
    Write-ECHeader
    $total = 3
    try {
        Write-StageProgress 1 $total "EC セットアップ" "必要なツールを確認しています..."
        Install-RequiredTools

        Write-StageProgress 2 $total "EC セットアップ" "リポジトリ設定を準備しています..."
        if (-not (Test-CommandAvailable "jj")) {
            throw "PATH 再読み込み後も jj が見つかりません。新しい PowerShell で再実行してください。"
        }

        Write-StageProgress 3 $total "EC セットアップ" "ユーザー設定とリポジトリを準備しています..."
        Initialize-ECRepository
        Clear-StageProgress
        Write-Host "`nセットアップが完了しました。" -ForegroundColor Green
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-Update {
    Write-ECHeader
    try {
        Write-StageProgress 1 2 "EC 更新" "サーバーから最新情報を取得しています..."
        Invoke-RequiredCommand "jj" @("git", "fetch")

        Write-StageProgress 2 2 "EC 更新" "最新の main に合わせています..."
        Invoke-RequiredCommand "jj" @("rebase", "-d", "main@origin")
        Clear-StageProgress
        Write-Host "`n更新が完了しました。`n" -ForegroundColor Green
        & jj status
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "コンフリクトなどが発生している可能性があります。" -ForegroundColor Yellow
    }
}

function Invoke-Publish {
    Write-ECHeader
    try {
        Write-StageProgress 1 4 "EC 公開" "変更を確認しています..."
        Invoke-RequiredCommand "jj" @("status")
        
        Write-Host ""
        Write-Host "変更を公開するにはコメントが必要です。（空白でキャンセル）" -ForegroundColor Cyan
        $comment = Read-Host "変更コメント"
        if ([string]::IsNullOrWhiteSpace($comment)) {
            Clear-StageProgress
            Write-Host "`n公開をキャンセルしました。" -ForegroundColor Yellow
            return
        }

        Write-StageProgress 2 4 "EC 公開" "変更にコメントを設定しています..."
        Invoke-RequiredCommand "jj" @("desc", "-m", $comment)

        Write-StageProgress 3 4 "EC 公開" "main を更新しています..."
        Invoke-RequiredCommand "jj" @("bookmark", "set", "main", "-r", "@")

        Write-StageProgress 4 4 "EC 公開" "サーバーへアップロードしています..."
        Invoke-RequiredCommand "jj" @("git", "push")
        Clear-StageProgress
        Write-Host "`nアップロードが完了しました。" -ForegroundColor Green
        Write-Host "コメント: $comment" -ForegroundColor DarkGray
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-ReviewChanges {
    $changedFiles = @()
    try {
        Write-StageProgress 1 2 "変更を確認" "変更状態を確認しています..."
        $statusOutput = @(& jj status)
        if ($LASTEXITCODE -ne 0) {
            throw "コマンドに失敗しました: jj status"
        }

        foreach ($line in $statusOutput) {
            if ($line -match '^\s*([MADRC?])\s+(.+?)\s*$') {
                $changedFiles += [PSCustomObject]@{
                    Status = $Matches[1]
                    Path = $Matches[2]
                }
            }
        }

        Clear-StageProgress
        if ($changedFiles.Count -eq 0) {
            Write-ECHeader
            Write-Host "  変更されたファイルはありません。" -ForegroundColor Green
            return
        }

        Read-ECChangedFileChoice -ChangedFiles $changedFiles
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-ECStatusColor {
    param([Parameter(Mandatory)] [string] $Status)

    switch ($Status) {
        "M" { return "Yellow" }
        "A" { return "Green" }
        "D" { return "Red" }
        "R" { return "Cyan" }
        default { return "Gray" }
    }
}

function Read-ECChangedFileChoice {
    param([Parameter(Mandatory)] [array] $ChangedFiles)

    $selected = 0
    while ($true) {
        Write-ECHeader
        Write-Host "  変更されたファイル" -ForegroundColor White
        Write-Host "  M:変更  A:追加  D:削除  R:名前変更" -ForegroundColor DarkGray
        Write-Host ""

        for ($index = 0; $index -lt $ChangedFiles.Count; $index++) {
            $file = $ChangedFiles[$index]
            $color = Get-ECStatusColor -Status $file.Status
            $line = "[$($file.Status)] $($file.Path)"
            if ($index -eq $selected) {
                Write-Host "  > $line" -ForegroundColor $color -BackgroundColor DarkGray
            }
            else {
                Write-Host "    $line" -ForegroundColor $color
            }
        }

        Write-Host ""
        Write-Host "  Enter:差分を表示  Esc:戻る" -ForegroundColor DarkCyan
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" { $selected = ($selected - 1 + $ChangedFiles.Count) % $ChangedFiles.Count }
            "DownArrow" { $selected = ($selected + 1) % $ChangedFiles.Count }
            "Escape" { return }
            "Enter" {
                Show-ECFileDiff -Path $ChangedFiles[$selected].Path
            }
        }
    }
}

function Show-ECFileDiff {
    param([Parameter(Mandatory)] [string] $Path)

    Write-ECHeader
    Write-Host "  [$Path]" -ForegroundColor Cyan
    Write-Host ""
    & jj diff -- $Path
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n差分の表示に失敗しました。" -ForegroundColor Red
    }
    Write-Host ""
    Read-Host "Enter でファイル一覧に戻ります"
}

function Read-ECMenuChoice {
    $items = @(
        @{ Label = "変更を確認（status / diff）"; Color = "Cyan"; Action = { Invoke-ReviewChanges } },
        @{ Label = "最新の情報を取得（fetch / rebase）"; Color = "Blue"; Action = { Invoke-Update } },
        @{ Label = "変更を保存（commit / push）"; Color = "Green"; Action = { Invoke-Publish } },
        @{ Label = "保存済み設定を変更"; Color = "Yellow"; Action = { Invoke-ConfigChange } },
        @{ Label = "初回セットアップ（ツール・ユーザー設定・フォルダ選択・clone）"; Color = "Magenta"; Action = { Invoke-Setup } },
        @{ Label = "終了"; Color = "Gray"; Action = { return } }
    )
    $selected = 0

    while ($true) {
        Write-ECHeader
        Write-Host "  操作を選択してください" -ForegroundColor White
        Write-Host ""
        for ($index = 0; $index -lt $items.Count; $index++) {
            if ($index -eq $selected) {
                Write-Host "  > $($items[$index].Label)" -ForegroundColor $items[$index].Color -BackgroundColor DarkGray
            }
            else {
                Write-Host "    $($items[$index].Label)" -ForegroundColor $items[$index].Color
            }
        }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" { $selected = ($selected - 1 + $items.Count) % $items.Count }
            "DownArrow" { $selected = ($selected + 1) % $items.Count }
            "Enter" {
                if ($selected -eq ($items.Count - 1)) { return }
                & $items[$selected].Action
                Write-Host ""
                Read-Host "Enter でメニューに戻ります"
            }
        }
    }
}

try {
    Read-ECMenuChoice
}
catch {
    Write-Host "`n致命的なエラー: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}