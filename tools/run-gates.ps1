param(
    [string] $DatabaseName = 'k12_question_graph',
    [string] $DatabaseUser = 'postgres',
    [string] $DatabaseHost = '127.0.0.1',
    [int] $DatabasePort = 5432,
    [string] $PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string] $FileStoreRoot = 'D:\KQG_Data\file_store'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$results = New-Object System.Collections.Generic.List[object]

function Invoke-GateStep([string] $Name, [scriptblock] $Script) {
    $started = Get-Date
    try {
        & $Script
        $results.Add([ordered]@{
            name = $Name
            status = 'pass'
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
        })
    }
    catch {
        $results.Add([ordered]@{
            name = $Name
            status = 'fail'
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
            error = $_.Exception.Message
        })
        throw
    }
}

Push-Location $repoRoot
try {
    Invoke-GateStep 'backend build' {
        dotnet build apps\api\K12QuestionGraph.Api.csproj | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }
    }

    Invoke-GateStep 'frontend build' {
        Push-Location apps\web
        try {
            npm run build | Write-Host
            if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
        }
        finally {
            Pop-Location
        }
    }

    Invoke-GateStep 'frontend lint' {
        Push-Location apps\web
        try {
            npm run lint | Write-Host
            if ($LASTEXITCODE -ne 0) { throw "npm run lint failed" }
        }
        finally {
            Pop-Location
        }
    }

    Invoke-GateStep 'worker smoke' {
        $workerDir = Join-Path $FileStoreRoot 'gate'
        New-Item -ItemType Directory -Path $workerDir -Force | Out-Null
        $workerFile = Join-Path $workerDir 'worker-smoke.txt'
        Set-Content -LiteralPath $workerFile -Value 'worker smoke' -Encoding UTF8
        python workers\document\worker.py --job-id gate --relative-path gate/worker-smoke.txt --file-root $FileStoreRoot | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "worker smoke failed" }
    }

    Invoke-GateStep 'doc schema config csv' {
        python -c "import csv, json, pathlib, yaml; rows=list(csv.DictReader(open('tasks/backlog.csv', encoding='utf-8-sig'))); [json.loads(p.read_text(encoding='utf-8')) for p in pathlib.Path('schemas').rglob('*.json')]; [yaml.safe_load(p.read_text(encoding='utf-8')) for p in pathlib.Path('configs').rglob('*.yaml')]; print('doc gates ok', len(rows))" | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "doc gates failed" }
    }

    Invoke-GateStep 'database smoke' {
        $psql = Join-Path $PgBin 'psql.exe'
        & $psql -h $DatabaseHost -p $DatabasePort -U $DatabaseUser -d $DatabaseName -c "select count(*) from information_schema.tables where table_schema='public';" | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "database smoke failed" }
    }

    Invoke-GateStep 'backup verify' {
        $backup = .\tools\backup.ps1 -PgBin $PgBin -DatabaseName $DatabaseName -DatabaseHost $DatabaseHost -DatabasePort $DatabasePort -DatabaseUser $DatabaseUser | ConvertFrom-Json
        .\tools\verify-backup.ps1 -ManifestPath $backup.manifest | Write-Host
    }

    [ordered]@{
        status = 'pass'
        steps = $results
    } | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}
