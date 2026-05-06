param(
  [string] $ProgramPath = 'apps/api/Program.cs'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$programFullPath = Join-Path $repoRoot $ProgramPath

if (-not (Test-Path -LiteralPath $programFullPath)) {
  throw "missing Program.cs: $ProgramPath"
}

$source = Get-Content -Raw -LiteralPath $programFullPath
$required = @(
  'app.MapPost("/paper-requests/parse", (PaperRequestParseRequest request, IPaperWorkflowService workflowService) =>',
  'app.MapPost("/paper-requests/replace-question", (PaperQuestionReplacementRequest request, IPaperWorkflowService workflowService) =>',
  'app.MapPost("/knowledge-version-explanations/resolve", (KnowledgeVersionExplanationRequest request, IPaperWorkflowService workflowService) =>'
)
foreach ($pattern in $required) {
  if (-not $source.Contains($pattern)) {
    throw "missing thin-endpoint pattern: $pattern"
  }
}

$forbidden = @(
  'InferPaperRequestScope(normalized)',
  'BuildReplacementPreview(current.StemPreview)',
  'BuildKnowledgeVersionExplanationText('
)
$foundForbidden = @()
foreach ($f in $forbidden) {
  if ($source.Contains($f)) {
    $foundForbidden += $f
  }
}

if ($foundForbidden.Count -gt 0) {
  throw "Program.cs still contains orchestration implementation markers: $($foundForbidden -join ', ')"
}

[ordered]@{
  status = 'pass'
  taskId = 'S002F'
  task = 'thin endpoint guard'
  checkedAt = (Get-Date).ToString('s')
  programPath = $ProgramPath
} | ConvertTo-Json -Depth 4
