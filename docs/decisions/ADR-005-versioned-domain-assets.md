# ADR-005: Treat teaching structures as versioned domain assets

## Status
Accepted

## Date
2026-05-03

## Context
K12 teaching structures are not static. Knowledge ontologies, textbook chapters, curriculum standards, regional exam points, question types, tags, difficulty scales, rubrics, AI prompts, parser pipelines, assembly policies, analysis metrics, export templates, privacy policies, and school organization can all change over time.

This is especially important beyond junior physics. Chinese, politics, history, interdisciplinary topics, local exam policies, and school-specific teaching practices can change more frequently than physics concepts. If the system treats these structures as fixed enums or permanent truth, future updates will require destructive rewrites and will break old questions, papers, analysis reports, and exports.

## Decision
Model these structures as versioned domain assets, not static constants.

Stable contracts are:

- identity
- version
- status
- source evidence
- effective scope
- replacement mapping
- review state
- migration report
- rollback evidence

Mutable domain assets include at least:

- knowledge ontology
- textbook and chapter taxonomy
- curriculum standard nodes
- regional exam points
- question type taxonomy
- difficulty and ability dimensions
- tags and custom fields
- answer and rubric versions
- paper assembly policies
- AI prompt/schema/model routing policies
- document parser pipeline definitions
- analysis metrics
- export templates
- privacy and data retention policies
- school/class/teacher membership history

Draft assets may be used to build and test the whole system before formal source-derived assets are ready. They must be marked as non-authoritative and must not be silently promoted to production truth.

Rules, deterministic matching, and AI may generate mapping and replacement suggestions automatically. High-confidence one-to-one mappings can be applied automatically in non-destructive migrations. Low-confidence, high-impact, split, merge, policy-sensitive, or analysis-changing mappings require teacher or administrator review.

## Consequences
- Development can continue with draft bootstrap assets while formal source-derived assets are still pending.
- Production activation still requires source evidence, review state, impact analysis, and rollback.
- Future formal assets replace or update draft assets through mapping tables and migration reports, not in-place overwrites.
- Historical questions, papers, scores, and reports remain reproducible against the asset version active at the time.
- AI results must record prompt/schema/model/router versions so old outputs can be explained or recomputed.
- All modules must depend on stable contracts, not on one specific knowledge taxonomy, textbook edition, tag list, or prompt version.

## Alternatives Considered

### Freeze an initial knowledge system before building the rest
Rejected. This blocks system construction on domain curation and does not solve later curriculum, textbook, regional, or subject changes.

### Hard-code enums and manually update them later
Rejected. This creates hidden coupling between questions, labels, AI outputs, reports, exports, and analytics. Later changes would require unsafe bulk updates.

### Let AI fully auto-replace all mappings
Rejected. AI and rules should reduce manual work, but split/merge/low-confidence/high-impact mappings need human review because they can change teaching interpretation, analysis history, and exam assembly constraints.
