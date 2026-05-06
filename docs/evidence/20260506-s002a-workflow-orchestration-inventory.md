# S002A Workflow Orchestration Inventory

- task_id: S002A
- checked_at: 2026-05-06T19:52:04+08:00
- scope: Program.cs / App.tsx / tools scripts
- objective: inventory existing teacher-workflow orchestration locations and define migration destination for S002B-S002F

## Current orchestration locations

### API (apps/api/Program.cs)
- Import workflow related endpoints currently in minimal API:
  - `POST /files`
  - `POST /imports`
  - `GET /imports/{id}`
  - `POST /imports/{id}/status`
  - `POST /imports/{id}/worker-smoke`
- Review/source workflow related endpoints currently in minimal API:
  - `GET /source-documents`
  - `POST /source-documents/{id}/regions`
  - `GET /source-documents/{id}/preview`
  - `POST /questions`
  - `GET /questions`
  - `GET /questions/{id}`
  - `GET /questions/{id}/sources`
- Paper workflow related endpoints currently in minimal API:
  - `POST /paper-requests/parse`
  - `POST /paper-requests/replace-question`
- Analysis/knowledge explanation endpoint currently in minimal API:
  - `POST /knowledge-version-explanations/resolve`

### Web (apps/web/src/App.tsx)
- Teacher workflow staging currently implemented as one large component with synthetic UI state:
  - teacher home + import wizard + manual review + paper request + replacement + export + score workbench + analysis
- Contract markers indicate productized UI contracts exist, but orchestration remains view-state centered in `App.tsx`.

### Tools (tools/*.ps1)
- Contract scripts are segmented by domain (`run-i*`, `run-j*`, `run-k*`, `run-m*`, `run-n*`, `run-p*`, `run-s*`, `run-o*`).
- `tools/run-gates.ps1` orchestrates many contract scripts, but this is verification orchestration, not runtime application-service orchestration.

## S002 migration destination

- Destination layer in API:
  - `apps/api/Application/Workflows/ImportReviewWorkflowService.cs`
  - `apps/api/Application/Workflows/PaperWorkflowService.cs`
  - `apps/api/Application/Workflows/ScoreAnalysisWorkflowService.cs`
  - shared DTO/state/error model under `apps/api/Application/Workflows/Contracts/`
- Endpoint role after migration:
  - `Program.cs` keeps route wiring + request/response translation + HTTP status mapping only.
  - Business orchestration moves into workflow services.
- Guard direction:
  - S002F should enforce thin endpoint boundary using architecture guard and prevent orchestration growth in `Program.cs`.

## Evidence commands
- `rg -n "Map(Get|Post|Put|Delete)|import|review|tag|paper|export|score|analysis|workflow|job|source|candidate|knowledge|basket" apps/api/Program.cs`
- `rg -n "import|review|tag|paper|export|score|analysis|source|candidate|knowledge|basket|admin|teacher" apps/web/src/App.tsx`
- `rg -n -g "*.ps1" "run-(i|j|k|m|n|p|s|o)\d|workflow|contract" tools`
