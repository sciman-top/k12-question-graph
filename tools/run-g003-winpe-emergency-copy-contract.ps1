param(
    [string] $Config = 'configs\recovery_media.defaults.yaml',
    [string] $OutputRoot = 'tmp\g003-winpe-recovery-media',
    [string] $Report = 'docs\evidence\g003-winpe-emergency-copy-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function ConvertTo-CmdPath([string] $Path) {
    return $Path.TrimEnd('\')
}

Push-Location $repoRoot
try {
    Assert-Condition (Test-Path -LiteralPath $Config) "missing recovery media config: $Config"
    $configText = Get-Content -LiteralPath $Config -Raw
    foreach ($pattern in @(
        'version:',
        'source_data_root:',
        'source_backup_root:',
        'default_destination_root:',
        'copy_items:',
        'no_mirror_delete: true',
        'require_destination_argument: true'
    )) {
        Assert-Condition ($configText.Contains($pattern)) "missing G003 config contract marker: $pattern"
    }

    $parsed = python -c "import pathlib, yaml; print(yaml.safe_load(pathlib.Path('$($Config.Replace('\', '\\'))').read_text(encoding='utf-8'))['version'])"
    Assert-Condition ($LASTEXITCODE -eq 0) "recovery media yaml parse failed"
    Assert-Condition ($parsed.Trim() -eq 'g003.recovery-media.v1') "unexpected recovery media config version: $parsed"

    $outputDir = Join-Path $OutputRoot 'KQG_RecoveryMedia'
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $cmdPath = Join-Path $outputDir 'KQG_EmergencyCopy.cmd'
    $ps1Path = Join-Path $outputDir 'KQG_EmergencyCopy.ps1'
    $readmePath = Join-Path $outputDir 'README-WinPE.txt'
    $manifestPath = Join-Path $outputDir 'recovery-media-manifest.json'

    $sourceDataRoot = 'D:\KQG_Data'
    $sourceBackupRoot = 'D:\KQG_Backups'
    $defaultDestinationRoot = 'E:\KQG_EmergencyCopy'
    $copyItems = @('file_store','logs','recovery','config','templates','prompts','ai_rules','teacher_profiles')

    $cmdLines = @(
        '@echo off',
        'setlocal enableextensions',
        'set "SOURCE_DATA_ROOT=D:\KQG_Data"',
        'set "SOURCE_BACKUP_ROOT=D:\KQG_Backups"',
        'set "DESTINATION_ROOT=%~1"',
        'if "%DESTINATION_ROOT%"=="" set "DESTINATION_ROOT=E:\KQG_EmergencyCopy"',
        'echo K12 Question Graph WinPE emergency copy',
        'echo Source data: %SOURCE_DATA_ROOT%',
        'echo Source backups: %SOURCE_BACKUP_ROOT%',
        'echo Destination: %DESTINATION_ROOT%',
        'if not exist "%DESTINATION_ROOT%" mkdir "%DESTINATION_ROOT%"',
        'robocopy "%SOURCE_DATA_ROOT%" "%DESTINATION_ROOT%\KQG_Data" /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /XJ /XD node_modules bin obj dist tmp',
        'robocopy "%SOURCE_BACKUP_ROOT%" "%DESTINATION_ROOT%\KQG_Backups" /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /XJ',
        'echo Mirror-delete mode is not used. Existing destination files are not deleted by this package.',
        'echo After copy, run verify-backup.ps1 against the newest manifest.json when Windows is available.',
        'exit /b %ERRORLEVEL%'
    )
    $cmdLines | Set-Content -LiteralPath $cmdPath -Encoding ASCII

    $psLines = @(
        'param(',
        '    [string] $DestinationRoot = "E:\KQG_EmergencyCopy",',
        '    [string] $SourceDataRoot = "D:\KQG_Data",',
        '    [string] $SourceBackupRoot = "D:\KQG_Backups"',
        ')',
        '$ErrorActionPreference = "Stop"',
        'New-Item -ItemType Directory -Path $DestinationRoot -Force | Out-Null',
        '$dataDestination = Join-Path $DestinationRoot "KQG_Data"',
        '$backupDestination = Join-Path $DestinationRoot "KQG_Backups"',
        'robocopy $SourceDataRoot $dataDestination /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /XJ /XD node_modules bin obj dist tmp',
        'if ($LASTEXITCODE -gt 7) { throw "robocopy data copy failed with exit code $LASTEXITCODE" }',
        'robocopy $SourceBackupRoot $backupDestination /E /COPY:DAT /DCOPY:DAT /R:2 /W:2 /XJ',
        'if ($LASTEXITCODE -gt 7) { throw "robocopy backup copy failed with exit code $LASTEXITCODE" }',
        '[pscustomobject]@{ status = "copied"; destinationRoot = $DestinationRoot; noMirrorDelete = $true } | ConvertTo-Json'
    )
    $psLines | Set-Content -LiteralPath $ps1Path -Encoding UTF8

    $readmeLines = @(
        'K12 Question Graph WinPE Emergency Copy',
        '',
        'Use when Windows cannot boot or the main application cannot open.',
        '',
        '1. Boot from WinPE or a recovery USB disk.',
        '2. Find the drive letters containing D:\KQG_Data and D:\KQG_Backups.',
        '3. Run: KQG_EmergencyCopy.cmd E:\KQG_EmergencyCopy',
        '4. Do not add mirror-delete options. This package never mirror-deletes the destination.',
        '5. After Windows is repaired, run tools\verify-backup.ps1 against the newest manifest.json.',
        '6. Restore with tools\restore.ps1 only after verifying the backup manifest.'
    )
    $readmeLines | Set-Content -LiteralPath $readmePath -Encoding UTF8

    $cmdText = Get-Content -LiteralPath $cmdPath -Raw
    $psText = Get-Content -LiteralPath $ps1Path -Raw
    $readmeText = Get-Content -LiteralPath $readmePath -Raw
    Assert-Condition ($cmdText.Contains('robocopy')) "cmd script must use robocopy"
    Assert-Condition (-not $cmdText.Contains('/MIR')) "cmd script must not use /MIR"
    Assert-Condition (-not $psText.Contains('/MIR')) "ps1 script must not use /MIR"
    Assert-Condition ($cmdText.Contains('%~1')) "cmd script must accept destination argument"
    Assert-Condition ($readmeText.Contains('verify-backup.ps1')) "readme must instruct backup verification"

    $manifest = [ordered]@{
        version = 'g003.recovery-media.v1'
        mode = 'draft_test'
        productionEligible = $false
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        sourceDataRoot = ConvertTo-CmdPath $sourceDataRoot
        sourceBackupRoot = ConvertTo-CmdPath $sourceBackupRoot
        defaultDestinationRoot = ConvertTo-CmdPath $defaultDestinationRoot
        copyItems = $copyItems
        outputs = [ordered]@{
            cmd = [System.IO.Path]::GetRelativePath($repoRoot, (Resolve-Path -LiteralPath $cmdPath)).Replace('\', '/')
            ps1 = [System.IO.Path]::GetRelativePath($repoRoot, (Resolve-Path -LiteralPath $ps1Path)).Replace('\', '/')
            readme = [System.IO.Path]::GetRelativePath($repoRoot, (Resolve-Path -LiteralPath $readmePath)).Replace('\', '/')
        }
        safety = [ordered]@{
            noMirrorDelete = $true
            copyOnly = $true
            destinationArgumentSupported = $true
            hashVerifyInstructionIncluded = $true
            productionDataMutated = $false
        }
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    $reportObject = [ordered]@{
        status = 'pass'
        task = 'G003'
        mode = 'draft_test'
        productionEligible = $false
        config = $Config
        generatedManifest = [System.IO.Path]::GetRelativePath($repoRoot, (Resolve-Path -LiteralPath $manifestPath)).Replace('\', '/')
        outputs = $manifest.outputs
        copyItems = $copyItems
        safety = $manifest.safety
        rollback = [ordered]@{
            code = 'git revert this G003 commit'
            generatedFiles = 'delete only tmp/g003-winpe-recovery-media generated package'
        }
        summaryChinese = [ordered]@{
            title = 'G003 WinPE 应急拷贝脚本生成合同报告'
            result = '通过'
            boundary = '仅生成 draft/test 离线拷贝脚本和说明；不执行真实拷贝，不删除目标介质内容。'
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $Report) -Force | Out-Null
    $reportObject | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Report -Encoding UTF8
    $reportObject | ConvertTo-Json -Depth 10
}
finally {
    Pop-Location
}
