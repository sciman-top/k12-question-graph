param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $Config = 'configs\installer_credentials.defaults.yaml',
    [string] $Report = 'docs\evidence\g004-pgpass-installer-dry-run-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Escape-PgpassField([string] $Value) {
    return ($Value -replace '\\', '\\' -replace ':', '\:')
}

function Get-RelativeOrRedactedTempPath([string] $Path) {
    return ($Path -replace [regex]::Escape($env:TEMP), '%TEMP%').Replace('\', '/')
}

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw "DatabasePassword or PGPASSWORD is required for G004 pgpass dry-run"
}

Push-Location $repoRoot
try {
    Assert-Condition (Test-Path -LiteralPath $Config) "missing installer credential config: $Config"
    $configText = Get-Content -LiteralPath $Config -Raw
    foreach ($pattern in @(
        'version:',
        'require_noninteractive_psql: true',
        'require_process_pgpassword_cleared: true',
        'require_acl_check: true',
        'do_not_modify_real_user_pgpass_in_dry_run: true',
        'do_not_log_password: true'
    )) {
        Assert-Condition ($configText.Contains($pattern)) "missing G004 config contract marker: $pattern"
    }

    python -c "import pathlib, yaml; assert yaml.safe_load(pathlib.Path('$($Config.Replace('\', '\\'))').read_text(encoding='utf-8'))['version'] == 'g004.installer-credentials.v1'; print('installer credential config ok')" | Write-Host
    Assert-Condition ($LASTEXITCODE -eq 0) "installer credential yaml parse failed"

    $psql = Join-Path $PgBin 'psql.exe'
    Assert-Condition (Test-Path -LiteralPath $psql) "psql.exe not found: $psql"

    $runId = "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(([Guid]::NewGuid().ToString('N')).Substring(0, 8))"
    $tempRoot = Join-Path $env:TEMP "kqg-g004-pgpass-dry-run\$runId"
    $tempAppData = Join-Path $tempRoot 'AppData\Roaming'
    $pgpassDir = Join-Path $tempAppData 'postgresql'
    $pgpassPath = Join-Path $pgpassDir 'pgpass.conf'
    New-Item -ItemType Directory -Path $pgpassDir -Force | Out-Null

    $pgpassLine = @(
        Escape-PgpassField $DatabaseHost
        [string]$DatabasePort
        Escape-PgpassField $DatabaseName
        Escape-PgpassField $DatabaseUser
        Escape-PgpassField $DatabasePassword
    ) -join ':'
    Set-Content -LiteralPath $pgpassPath -Value $pgpassLine -Encoding ASCII

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $pgpassPath /inheritance:r /grant:r "${identity}:F" | Out-Null
    Assert-Condition ($LASTEXITCODE -eq 0) "icacls failed when tightening pgpass ACL"
    $aclText = (& icacls.exe $pgpassPath) -join "`n"
    Assert-Condition ($aclText -notmatch 'Everyone|BUILTIN\\Users|Authenticated Users') "pgpass ACL is too broad"
    Assert-Condition ($aclText -match [regex]::Escape($identity)) "pgpass ACL does not include current identity"

    $previousAppData = $env:APPDATA
    $previousPgPassword = $env:PGPASSWORD
    $env:APPDATA = $tempAppData
    $env:PGPASSWORD = $null
    try {
        $queryOutput = & $psql -w -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -t -A -c "select current_database();"
        Assert-Condition ($LASTEXITCODE -eq 0) "psql -w failed with temp pgpass and cleared process PGPASSWORD"
        Assert-Condition (($queryOutput | Select-Object -First 1).Trim() -eq $DatabaseName) "psql -w returned unexpected database"
    }
    finally {
        $env:APPDATA = $previousAppData
        $env:PGPASSWORD = $previousPgPassword
    }

    Remove-Item -LiteralPath $tempRoot -Recurse -Force
    Assert-Condition (-not (Test-Path -LiteralPath $pgpassPath)) "temporary pgpass file was not removed"

    $reportObject = [ordered]@{
        status = 'pass'
        task = 'G004'
        mode = 'draft_test'
        productionEligible = $false
        config = $Config
        psqlVersion = (& $psql --version)
        tempAppData = Get-RelativeOrRedactedTempPath $tempAppData
        pgpassPath = Get-RelativeOrRedactedTempPath $pgpassPath
        realUserPgpassModified = $false
        processPgpasswordClearedForVerification = $true
        psqlNoPasswordPromptVerified = $true
        acl = [ordered]@{
            checked = $true
            currentIdentityOnly = $true
            broadPrincipalsAbsent = $true
        }
        cleanup = [ordered]@{
            tempPgpassRemoved = $true
            tempRootRemoved = $true
        }
        secretHandling = [ordered]@{
            passwordLogged = $false
            reportContainsPassword = $false
        }
        rollback = [ordered]@{
            realUserProfile = 'no real user pgpass was modified in this dry-run'
            tempFiles = 'temporary APPDATA root is deleted after verification'
            code = 'git revert this G004 commit'
        }
        summaryChinese = [ordered]@{
            title = 'G004 pgpass 安装器 dry-run 合同报告'
            result = '通过'
            boundary = '仅使用临时 APPDATA 写入 pgpass 并验证 psql -w；不修改真实用户 pgpass，不记录密码。'
        }
    }

    $reportJson = $reportObject | ConvertTo-Json -Depth 10
    Assert-Condition (-not $reportJson.Contains($DatabasePassword)) "report unexpectedly contains database password"
    New-Item -ItemType Directory -Path (Split-Path -Parent $Report) -Force | Out-Null
    $reportJson | Set-Content -LiteralPath $Report -Encoding UTF8
    $reportJson
}
finally {
    Pop-Location
}
