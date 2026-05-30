param(
    [string] $ReportPath = 'docs/evidence/20260529-ns203-privacy-license-scan-report.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

function Assert-Condition([bool] $Condition, [string] $Message) {
    if (-not $Condition) {
        throw $Message
    }
}

function Get-LineNumber([string] $Text, [int] $Index) {
    if ($Index -le 0) {
        return 1
    }

    return (($Text.Substring(0, $Index) -split "`n").Count)
}

function New-Hit([string] $Kind, [string] $Path, [int] $Line, [string] $Excerpt, [bool] $Allowed, [string] $Reason) {
    [ordered]@{
        kind = $Kind
        path = $Path
        line = $Line
        excerpt = $Excerpt
        allowed = $Allowed
        reason = $Reason
    }
}

function Test-AllowlistedCredentialLine([string] $Line) {
    return $Line -match '(?i)(redacted|placeholder|sample|example|contract-secret|ns202-contract-secret|o004-contract-secret|o004b-contract-secret|test-secret|your-|your_|dummy|fake|stub|changeme)' -or
        $Line -match '(?i)(Use-KqgDatabasePassword|args\.password|\$DatabasePassword\s*=)' -or
        $Line -match '(?i)(ApiKey|Password|Token|Secret)["'']?\s*[:=]\s*["'']?\s*["'']?\s*(,|$)' -or
        $Line -match '(?i)(HeaderName|RoleHeaderName|OperatorIdHeaderName|RollbackRefHeaderName)'
}

function Get-ItemCount($Items) {
    if ($null -eq $Items) {
        return 0
    }

    try {
        return [int]$Items.Count
    }
    catch {
        return [int]($Items | Measure-Object).Count
    }
}

Push-Location $repoRoot
try {
    $policyPath = 'docs/102_NonSiteFixturePrivacyPolicy.md'
    $fixturePolicyPath = 'tests/golden-import/privacy_and_license.md'
    $rawIgnorePath = 'sources/raw/.gitignore'
    foreach ($path in @($policyPath, $fixturePolicyPath, $rawIgnorePath)) {
        Assert-Condition (Test-Path -LiteralPath $path) "NS203 required policy file missing: $path"
    }

    $policy = Get-Content -LiteralPath $policyPath -Raw
    foreach ($marker in @('real_student_data', 'authorized_anonymized_material', 'sources/raw/', '不得进入 Git', '不得发送给外部 AI')) {
        Assert-Condition ($policy.Contains($marker)) "fixture privacy policy missing marker: $marker"
    }

    $fixturePolicy = Get-Content -LiteralPath $fixturePolicyPath -Raw
    foreach ($marker in @('synthetic_fixture', 'No real student name', 'No real school exam original', 'External AI is not required')) {
        Assert-Condition ($fixturePolicy.Contains($marker)) "golden fixture privacy policy missing marker: $marker"
    }

    $rawIgnore = Get-Content -LiteralPath $rawIgnorePath -Raw
    Assert-Condition ($rawIgnore.Contains('*')) 'sources/raw/.gitignore must ignore raw material by default'
    Assert-Condition ($rawIgnore.Contains('!.gitignore')) 'sources/raw/.gitignore must keep only its marker tracked'

    $scanRoots = @('docs', 'tests', 'prompts', 'sources', 'configs', 'apps', 'tools', 'tasks', 'schemas', 'README.md', 'ALL_IN_ONE_EXECUTIVE_SPEC.md')
    $trackedFiles = @(& git -C $repoRoot ls-files -- $scanRoots 2>$null)
    $trackedFiles = @($trackedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    Assert-Condition ($trackedFiles.Count -gt 0) 'NS203 tracked file scope is empty'

    $textExtensions = @(
        '.cs', '.css', '.csv', '.html', '.json', '.md', '.ps1', '.py', '.sql', '.ts', '.tsx', '.txt', '.xml', '.yaml', '.yml', '.gitignore'
    )
    $binaryExtensions = @('.doc', '.docx', '.gif', '.jpeg', '.jpg', '.pdf', '.png', '.ppt', '.pptx', '.tif', '.tiff', '.webp', '.xls', '.xlsx')

    $secretHits = New-Object System.Collections.Generic.List[object]
    $piiHits = New-Object System.Collections.Generic.List[object]
    $policyMentions = New-Object System.Collections.Generic.List[object]
    $rawSourceBlockers = New-Object System.Collections.Generic.List[object]
    $trackedBinaryFiles = New-Object System.Collections.Generic.List[object]
    $copyrightRawMarkers = New-Object System.Collections.Generic.List[object]

    $regexes = [ordered]@{
        openAiKey = [regex]'sk-[A-Za-z0-9_-]{40,}'
        credentialAssignment = [regex]'(?i)(api[_-]?key|secret|token|password|pwd)\s*[:=]\s*["'']?([A-Za-z0-9_./+=-]{12,})'
        cnPhone = [regex]'(?<!\d)1[3-9]\d{9}(?!\d)'
        cnResidentId = [regex]'(?<!\d)[1-9]\d{5}(18|19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])\d{3}[\dXx](?!\d)'
        studentNameValue = [regex]'学生姓名\s*[:：=]\s*[\p{IsCJKUnifiedIdeographs}]{2,4}'
        studentIdValue = [regex]'学号\s*[:：=]\s*[A-Za-z0-9-]{5,}'
        classRosterValue = [regex]'(班级|花名册)\s*[:：=]\s*[\p{IsCJKUnifiedIdeographs}A-Za-z0-9_-]{3,}'
    }

    foreach ($relativePath in $trackedFiles) {
        $normalized = $relativePath -replace '\\', '/'
        if ($normalized -match '(^|/)(bin|obj|node_modules|dist)/') {
            continue
        }

        $fullPath = Join-Path $repoRoot $relativePath
        if (-not (Test-Path -LiteralPath $fullPath)) {
            continue
        }

        $extension = [System.IO.Path]::GetExtension($relativePath).ToLowerInvariant()
        if ($binaryExtensions -contains $extension) {
            $isAllowedEvidenceScreenshot = $normalized -eq 'docs/evidence/20260512-real004-guangzhou-2015-review-ui.png'
            $isAllowedAppAsset = $normalized -eq 'apps/web/src/assets/hero.png'
            $trackedBinaryFiles.Add([ordered]@{
                path = $relativePath
                extension = $extension
                allowed = ($isAllowedEvidenceScreenshot -or $isAllowedAppAsset)
                reason = if ($isAllowedEvidenceScreenshot) { 'generated UI evidence screenshot, not raw source material' } elseif ($isAllowedAppAsset) { 'application visual asset, not raw source/student material' } else { 'tracked binary requires explicit source/license review' }
            })
            continue
        }

        $isText = ($textExtensions -contains $extension) -or ([System.IO.Path]::GetFileName($relativePath) -in @('README', 'README.md', 'AGENTS.md'))
        if (-not $isText) {
            continue
        }

        $text = Get-Content -LiteralPath $fullPath -Raw -ErrorAction Stop
        $lines = $text -split "`n"

        foreach ($match in $regexes.openAiKey.Matches($text)) {
            $lineNumber = Get-LineNumber $text $match.Index
            $line = $lines[$lineNumber - 1].Trim()
            $secretHits.Add((New-Hit 'openai_api_key_like' $relativePath $lineNumber $line $false 'API key shaped value must not be tracked'))
        }

        foreach ($match in $regexes.credentialAssignment.Matches($text)) {
            $lineNumber = Get-LineNumber $text $match.Index
            $line = $lines[$lineNumber - 1].Trim()
            $allowed = Test-AllowlistedCredentialLine $line
            $secretHits.Add((New-Hit 'credential_assignment_like' $relativePath $lineNumber $line $allowed $(if ($allowed) { 'placeholder/test contract value or header constant' } else { 'possible tracked credential assignment' })))
        }

        foreach ($patternName in @('cnPhone', 'cnResidentId', 'studentNameValue', 'studentIdValue', 'classRosterValue')) {
            foreach ($match in $regexes[$patternName].Matches($text)) {
                $lineNumber = Get-LineNumber $text $match.Index
                $line = $lines[$lineNumber - 1].Trim()
                $piiHits.Add((New-Hit $patternName $relativePath $lineNumber $line $false 'possible real student/person PII value'))
            }
        }

        foreach ($term in @('真实学生', '学生姓名', '学号', 'PII', '版权', '授权', 'containsStudentPii', 'realStudentDataUsed')) {
            if ($text.Contains($term)) {
                $policyMentions.Add([ordered]@{ path = $relativePath; term = $term })
            }
        }

        if ($normalized.StartsWith('sources/raw/') -and $normalized -ne 'sources/raw/.gitignore') {
            $rawSourceBlockers.Add([ordered]@{ path = $relativePath; reason = 'tracked file under ignored raw source staging area' })
        }

        if ($normalized -match '(^|/)(raw|original|source-materials)/' -and $normalized -notmatch 'sources/raw/.gitignore') {
            $copyrightRawMarkers.Add([ordered]@{ path = $relativePath; reason = 'path name suggests raw/original/source material; verify it is metadata only' })
        }
    }

    $rawLocalFiles = @()
    if (Test-Path -LiteralPath 'sources/raw') {
        $rawLocalFiles = @(Get-ChildItem -LiteralPath 'sources/raw' -Force -File | Where-Object { $_.Name -ne '.gitignore' } | ForEach-Object {
            [ordered]@{ path = $_.FullName; length = $_.Length }
        })
    }

    $blockingSecretHits = @($secretHits | Where-Object { -not $_.allowed })
    $blockingBinaryFiles = @($trackedBinaryFiles | Where-Object { -not $_.allowed })
    $blockingPiiHits = @($piiHits | Where-Object { -not $_.allowed })
    $blockers = @()
    $blockers += @($blockingSecretHits)
    $blockers += @($blockingPiiHits)
    $blockers += @($rawSourceBlockers | ForEach-Object { $_ })
    $blockers += @($blockingBinaryFiles)
    $blockers += @($rawLocalFiles)
    $status = 'pass'
    if (@($blockers).Count -ne 0) {
        $status = 'fail'
    }

    $report = [ordered]@{}
    $report.Add('status', $status)
    $report.Add('taskId', 'NS203')
    $report.Add('checkedAt', (Get-Date).ToString('s'))
    $report.Add('mode', 'tracked_text_privacy_license_scan')
    $report.Add('productionEligible', $false)
    $report.Add('scanScope', [ordered]@{
            roots = $scanRoots
            trackedFileCount = $trackedFiles.Count
            policyPath = $policyPath
            fixturePolicyPath = $fixturePolicyPath
            rawIgnorePath = $rawIgnorePath
    })
    $counts = [ordered]@{}
    $counts.Add('secretLikeHits', (Get-ItemCount $secretHits))
    $counts.Add('blockingSecretHits', (Get-ItemCount $blockingSecretHits))
    $counts.Add('piiValueHits', (Get-ItemCount $piiHits))
    $counts.Add('blockingPiiHits', (Get-ItemCount $blockingPiiHits))
    $counts.Add('trackedBinaryFiles', (Get-ItemCount $trackedBinaryFiles))
    $counts.Add('blockingTrackedBinaryFiles', (Get-ItemCount $blockingBinaryFiles))
    $counts.Add('trackedRawSourceBlockers', (Get-ItemCount $rawSourceBlockers))
    $counts.Add('localRawSourceFiles', (Get-ItemCount $rawLocalFiles))
    $counts.Add('policyMentionCount', (Get-ItemCount $policyMentions))
    $counts.Add('copyrightRawPathMarkers', (Get-ItemCount $copyrightRawMarkers))
    $report.Add('counts', $counts)
    $report.Add('allowedFindings', [ordered]@{
            allowedCredentialLikeHits = @($secretHits | Where-Object { $_.allowed })
            allowedTrackedBinaryFiles = @($trackedBinaryFiles | Where-Object { $_.allowed })
            policyMentionsSample = @($policyMentions | Select-Object -First 20)
            copyrightRawPathMarkers = @($copyrightRawMarkers | Select-Object -First 20)
    })
    $report.Add('blockers', @($blockers))
    $report.Add('acceptance', [ordered]@{
            noTrackedRealStudentPiiValues = ((Get-ItemCount $blockingPiiHits) -eq 0)
            noTrackedRealSecrets = ((Get-ItemCount $blockingSecretHits) -eq 0)
            rawSourceStagingIgnored = ((Get-ItemCount $rawSourceBlockers) -eq 0 -and (Get-ItemCount $rawLocalFiles) -eq 0)
            fixturePolicyPresent = $true
            evidencePolicyPresent = $true
    })
    $report.Add('boundary', 'NS203 scans tracked repo text and raw staging policy for PII/secret/source-license blockers. It cannot certify external untracked staging directories or legal sufficiency of third-party materials.')
    $report.Add('next', 'NS204 can continue no-active-write guard for AI candidates, imports, dynamic assets, and production history.')
    $report.Add('rollback', 'git restore tasks/non-site-implementation-plan.csv tools/run-gates.ps1; git clean -f -- tools/run-ns203-privacy-license-scan.ps1 docs/evidence/20260529-ns203-privacy-license-scan-report.json')

    $reportFullPath = Join-Path $repoRoot $ReportPath
    New-Item -ItemType Directory -Path (Split-Path -Parent $reportFullPath) -Force | Out-Null
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    $json = $report | ConvertTo-Json -Depth 8
    if ($report['status'] -ne 'pass') {
        Write-Host $json
        throw "NS203 privacy/license scan found blockers: $(@($blockers).Count)"
    }

    $json
}
finally {
    Pop-Location
}
