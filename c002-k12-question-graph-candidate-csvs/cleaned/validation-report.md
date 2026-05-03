# C002 Candidate CSV Validation Report

## Result

Result: pass

## Generated Files

- `c002-asset-mapping.csv`
- `c002-curriculum-standard.csv`
- `c002-exam-point.csv`
- `c002-external-ai-candidate.csv`
- `c002-formal-knowledge.csv`
- `c002-processing-summary.csv`
- `c002-textbook-chapter.csv`
- `c002-trend-summary.csv`
- `source-material-manifest.candidate.json`

## Fixes Applied

- Cleared curriculum `parent_stable_id` values that pointed to knowledge IDs: 20
- Converted `mapping_type=related` to `broader` with notes and pending review: 48
- Generated trend summary rows for dangling `trend_summary` mappings: 3
- Generated source material manifest entries: 20

## Remaining Issues

- None for candidate import precheck. Activation still requires source upload hash verification and human review.

## Database Boundary

These files are suitable only for candidate/pending_review import. They must not be imported as active or production eligible assets.
