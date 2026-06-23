param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $DatabasePassword = $env:PGPASSWORD,
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store',
    [string] $Output = '',
    [switch] $Apply
)

$ErrorActionPreference = 'Stop'
$env:PYTHONIOENCODING = 'utf-8'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'database-env.ps1')
$DatabasePassword = Use-KqgDatabasePassword -DatabasePassword $DatabasePassword

if ([string]::IsNullOrWhiteSpace($DatabasePassword)) {
    throw 'DatabasePassword or PGPASSWORD is required for Guangzhou 2015 real ingest slice'
}

if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = ('docs\evidence\{0}-guangzhou-2015-real-ingest-slice-report.json' -f (Get-Date -Format 'yyyyMMdd'))
}

function Restore-KnownGuangzhou2015FileStoreInputs {
    param(
        [string] $FileStoreRoot
    )

    $knownFiles = @(
        @{
            Sha256 = '534d8eee3b99446d514af736aaf4cd8e36f2803154f7778c0f656f1832b7510c'
            RelativePath = 'original\53\4d\534d8eee3b99446d514af736aaf4cd8e36f2803154f7778c0f656f1832b7510c.pdf'
            Candidates = @(
                'D:\2015广州中考.pdf',
                'D:\CODE\k12-question-graph\tmp\p001-p006-onsite-agent\广州中考真题\2015广州中考.pdf'
            )
        },
        @{
            Sha256 = '065a6293b5c1019ed2da199736df44c6d0304797d0a986a750449197ca9ba88d'
            RelativePath = 'original\06\5a\065a6293b5c1019ed2da199736df44c6d0304797d0a986a750449197ca9ba88d.pdf'
            Candidates = @(
                'D:\2015广州中考答案.pdf',
                'D:\CODE\k12-question-graph\tmp\p001-p006-onsite-agent\广州中考真题\2015广州中考答案.pdf'
            )
        }
    )

    foreach ($file in $knownFiles) {
        $targetPath = Join-Path $FileStoreRoot $file.RelativePath
        if (Test-Path -LiteralPath $targetPath) {
            continue
        }

        $restoreSource = $null
        foreach ($candidate in $file.Candidates) {
            if (-not (Test-Path -LiteralPath $candidate)) {
                continue
            }

            $hash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -eq $file.Sha256) {
                $restoreSource = $candidate
                break
            }
        }

        if ($null -eq $restoreSource) {
            throw "missing Guangzhou 2015 source file copy for $($file.RelativePath)"
        }

        New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
        Copy-Item -LiteralPath $restoreSource -Destination $targetPath -Force
    }
}

Push-Location $repoRoot
try {
    Restore-KnownGuangzhou2015FileStoreInputs -FileStoreRoot $FileStoreRoot

    $args = @(
        'tools\guangzhou_2015_real_ingest.py',
        '--host', $DatabaseHost,
        '--port', ([string] $DatabasePort),
        '--database', $DatabaseName,
        '--user', $DatabaseUser,
        '--password', $DatabasePassword,
        '--file-root', $FileStoreRoot,
        '--output', $Output
    )
    if ($Apply) {
        $args += '--apply'
    }

    & python @args
    if ($LASTEXITCODE -ne 0) {
        throw 'Guangzhou 2015 real ingest slice failed'
    }

    $report = Get-Content -LiteralPath (Join-Path $repoRoot $Output) -Raw | ConvertFrom-Json
    if ($Apply) {
        if ($report.status -ne 'pass') {
            throw "expected pass status after apply, got $($report.status)"
        }
    }
    elseif ($report.status -ne 'dry_run_pass') {
        throw "expected dry_run_pass status, got $($report.status)"
    }

    if ($report.after.questionCount -ne 18) {
        throw "expected 18 question items, got $($report.after.questionCount)"
    }
    if ($report.after.cutCandidateCount -ne 18) {
        throw "expected 18 cut candidates, got $($report.after.cutCandidateCount)"
    }
    if ($report.after.openReviewQueueCount -ne 18) {
        throw "expected 18 open review queue items, got $($report.after.openReviewQueueCount)"
    }
}
finally {
    Pop-Location
}
