param(
    [string] $DataRoot = 'tmp\g002-storage\data',
    [string] $FileStoreRoot = 'tmp\g002-storage\data\file_store',
    [string] $BackupRoot = 'tmp\g002-storage\backups',
    [string] $LogsRoot = 'tmp\g002-storage\data\logs',
    [string] $CacheRoot = 'tmp\g002-storage\data\cache',
    [string] $Report = 'docs\evidence\g002-storage-cleanup-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Get-FreeTcpPort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse('127.0.0.1'), 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Wait-HttpOk([string] $Url, [System.Diagnostics.Process] $Process, [string] $LogErr) {
    for ($i = 0; $i -lt 30; $i++) {
        if ($Process.HasExited) {
            throw "API exited before G002 contract check on $Url; see $LogErr"
        }

        try {
            $response = Invoke-RestMethod -Uri $Url -TimeoutSec 2
            if ($response.status -eq 'ok') {
                return $response
            }
        }
        catch {
            Start-Sleep -Seconds 1
        }
    }

    throw "API did not become available for G002 contract check on $Url"
}

Push-Location $repoRoot
try {
    $apiProgram = Get-Content -LiteralPath 'apps\api\Program.cs' -Raw
    foreach ($pattern in @(
        '/api/admin/storage/summary',
        '/api/admin/cache/cleanup',
        'CacheRoot',
        'ProductionEligible: false'
    )) {
        Assert-Condition ($apiProgram.Contains($pattern)) "missing G002 API contract marker: $pattern"
    }

    $app = Get-Content -LiteralPath 'apps\web\src\App.tsx' -Raw
    $adminPanels = Get-Content -LiteralPath 'apps\web\src\ui\AdminGovernancePanels.tsx' -Raw
    $uiSource = $app + "`n" + $adminPanels
    foreach ($pattern in @(
        'data-flow="admin-storage-dashboard"',
        'data-contract="storage-summary"',
        'data-contract="cache-cleanup-configured-root"',
        'data-action="cache-cleanup-dry-run"',
        'data-contract="no-production-data-delete"'
    )) {
        Assert-Condition ($uiSource.Contains($pattern)) "missing G002 UI contract marker: $pattern"
    }

    $resolved = @{
        DataRoot = (Join-Path $repoRoot $DataRoot)
        FileStoreRoot = (Join-Path $repoRoot $FileStoreRoot)
        BackupRoot = (Join-Path $repoRoot $BackupRoot)
        LogsRoot = (Join-Path $repoRoot $LogsRoot)
        CacheRoot = (Join-Path $repoRoot $CacheRoot)
    }
    foreach ($path in $resolved.Values) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }

    $oldCacheFile = Join-Path $resolved.CacheRoot 'old-cache.bin'
    $freshCacheFile = Join-Path $resolved.CacheRoot 'fresh-cache.bin'
    $protectedFile = Join-Path $resolved.FileStoreRoot 'protected-question-file.bin'
    Set-Content -LiteralPath $oldCacheFile -Value 'old cache candidate' -Encoding UTF8
    Set-Content -LiteralPath $freshCacheFile -Value 'fresh cache should stay' -Encoding UTF8
    Set-Content -LiteralPath $protectedFile -Value 'protected file store data should stay' -Encoding UTF8
    (Get-Item -LiteralPath $oldCacheFile).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddDays(-30)

    $port = Get-FreeTcpPort
    $apiUrl = "http://127.0.0.1:$port"
    $logOut = Join-Path $repoRoot 'docs\evidence\g002-api.out.log'
    $logErr = Join-Path $repoRoot 'docs\evidence\g002-api.err.log'
    $previousDataRoot = $env:KqgPaths__DataRoot
    $previousFileStoreRoot = $env:KqgPaths__FileStoreRoot
    $previousBackupRoot = $env:KqgPaths__BackupRoot
    $previousLogsRoot = $env:KqgPaths__LogsRoot
    $previousCacheRoot = $env:KqgPaths__CacheRoot

    $env:KqgPaths__DataRoot = $resolved.DataRoot
    $env:KqgPaths__FileStoreRoot = $resolved.FileStoreRoot
    $env:KqgPaths__BackupRoot = $resolved.BackupRoot
    $env:KqgPaths__LogsRoot = $resolved.LogsRoot
    $env:KqgPaths__CacheRoot = $resolved.CacheRoot

    $process = Start-Process -FilePath dotnet -ArgumentList @('run','--project','apps\api\K12QuestionGraph.Api.csproj','--urls',$apiUrl) -PassThru -WindowStyle Hidden -RedirectStandardOutput $logOut -RedirectStandardError $logErr
    try {
        Wait-HttpOk -Url "$apiUrl/health" -Process $process -LogErr $logErr | Out-Null

        $summary = Invoke-RestMethod -Uri "$apiUrl/api/admin/storage/summary" -TimeoutSec 5
        Assert-Condition ($summary.status -eq 'ok') "storage summary did not pass"
        Assert-Condition ($summary.mode -eq 'draft_test') "storage summary must remain draft_test"
        Assert-Condition ($summary.productionEligible -eq $false) "storage summary must not be productionEligible"
        $cacheArea = @($summary.areas) | Where-Object { $_.name -eq 'cache' } | Select-Object -First 1
        Assert-Condition ($null -ne $cacheArea) "storage summary missing cache area"
        Assert-Condition ($cacheArea.cleanupAllowed -eq $true) "only cache area should be cleanup allowed"
        Assert-Condition ($summary.cacheCleanupRoot -eq (Resolve-Path -LiteralPath $resolved.CacheRoot).Path) "storage summary uses unexpected cache root"

        $dryRun = Invoke-RestMethod -Uri "$apiUrl/api/admin/cache/cleanup" -Method Post -ContentType 'application/json' -Body '{"dryRun":true,"olderThanDays":7}' -TimeoutSec 5
        Assert-Condition ($dryRun.dryRun -eq $true) "cache cleanup preview must be dry-run"
        Assert-Condition ($dryRun.matchedFileCount -ge 1) "cache cleanup preview did not find old cache file"
        Assert-Condition (Test-Path -LiteralPath $oldCacheFile) "dry-run deleted old cache file"

        $cleanup = Invoke-RestMethod -Uri "$apiUrl/api/admin/cache/cleanup" -Method Post -ContentType 'application/json' -Body '{"dryRun":false,"olderThanDays":7}' -TimeoutSec 5
        Assert-Condition ($cleanup.dryRun -eq $false) "cache cleanup apply did not run"
        Assert-Condition ($cleanup.deletedFileCount -ge 1) "cache cleanup did not delete old cache file"
        Assert-Condition (-not (Test-Path -LiteralPath $oldCacheFile)) "old cache file still exists after cleanup"
        Assert-Condition (Test-Path -LiteralPath $freshCacheFile) "fresh cache file was deleted"
        Assert-Condition (Test-Path -LiteralPath $protectedFile) "protected file store file was deleted"

        $reportObject = [ordered]@{
            status = 'pass'
            task = 'G002'
            mode = 'draft_test'
            productionEligible = $false
            apiEndpoints = @(
                'GET /api/admin/storage/summary',
                'POST /api/admin/cache/cleanup'
            )
            uiContracts = @(
                'admin-storage-dashboard',
                'storage-summary',
                'cache-cleanup-configured-root',
                'no-production-data-delete'
            )
            cleanupBoundary = [ordered]@{
                configuredCacheRootOnly = $true
                dryRunSupported = $true
                protectedFileStoreUntouched = $true
                freshCacheUntouched = $true
                productionDataDeleteAllowed = $false
            }
            summary = $summary
            preview = $dryRun
            cleanup = $cleanup
            rollback = [ordered]@{
                code = 'git revert this G002 commit'
                data = 'delete only tmp/g002-storage synthetic files generated by this contract'
            }
            summaryChinese = [ordered]@{
                title = 'G002 缓存清理与存储看板合同报告'
                result = '通过'
                boundary = '仅清理配置化缓存目录；文件仓库、备份包、学生成绩和正式资产不纳入缓存清理。'
            }
        }

        New-Item -ItemType Directory -Path (Split-Path -Parent $Report) -Force | Out-Null
        $reportObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Report -Encoding UTF8
        $reportObject | ConvertTo-Json -Depth 10
    }
    finally {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $env:KqgPaths__DataRoot = $previousDataRoot
        $env:KqgPaths__FileStoreRoot = $previousFileStoreRoot
        $env:KqgPaths__BackupRoot = $previousBackupRoot
        $env:KqgPaths__LogsRoot = $previousLogsRoot
        $env:KqgPaths__CacheRoot = $previousCacheRoot
    }
}
finally {
    Pop-Location
}
