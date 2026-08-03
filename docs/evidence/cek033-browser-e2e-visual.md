# CEK-33 Browser E2E and Visual Evidence

- checkedAt: 2026-07-31
- taskId: CEK-33
- status: pass_with_explicit_source_cited_data_absence
- runtime: Web `http://127.0.0.1:5175`, API `http://127.0.0.1:5290`
- health: Web `ok`, API readiness `ok`
- productionEligible: false
- activeApply: false

## Review and undo

The browser wrote each decision through the teacher review UI and immediately used the same UI undo action. PostgreSQL then confirmed the audit status and restored candidate state.

| Path | Candidate | Decision | Browser result | Database result |
| --- | --- | --- | --- | --- |
| Source-linked target | `2839ae57-6848-50a3-9b58-87e2d2193034` | `keep_pending`, then undo | question and answer page links visible; undo success | audit `dismissed`; target `pending_review`; `production_eligible=false` |
| Retrospective alignment | `76a15967-8a66-5a7f-8ad3-c8d697354ad8` | `keep_pending`, then undo | `后设对齐` disclosed; undo success | audit `dismissed`; alignment `pending_review`; `production_eligible=false` |
| High-impact conflict | `5fd420d1-67e4-45b5-aa72-8c813c64a3d2` | `return`, then undo | high-impact range conflict returned and restored | audit `dismissed`; mapping `pending_review`; `auto_applied=false` |
| Reviewed search sample | target above | `approve`, reviewed search, then undo | reviewed mode showed 1 preview-only card and returned to 0 after undo | audit `dismissed`; target restored to `pending_review`; `production_eligible=false` |

The admitted real corpus contains `128 retrospective_crosswalk` and `5 contemporaneous_inferred` alignments, but no `source_cited` alignment. CEK-33 did not fabricate an original curriculum citation. The exact `source_cited` label/rendering branch remains covered by `CurriculumEvidenceReviewPanel.test.tsx`; the live browser used a real target with two source-page anchors as the closest non-fabricated source-review path.

- reason: no admitted year-report alignment explicitly cites a curriculum requirement version/item.
- alternativeVerification: browser review/undo of a real source-linked target plus the existing `source_cited` UI contract fixture.
- evidenceLink: this report and `docs/evidence/cek026-curriculum-evidence-review-ui.json`.
- expiresAt: next admission of an actual `source_cited` alignment.
- recoveryCondition: repeat this browser review/undo path when a source-supported `source_cited` candidate exists.

## Search, paper, and analysis

- Active search returned 0 cards without widening constraints.
- Candidate search returned 20 cards on the first page, with 20 disabled `仅预览` actions, 8 curriculum-page links, and 13 annual-report-page links.
- A temporary approved target appeared as one reviewed preview card; it could not enter the formal basket and disappeared after undo.
- Natural-language paper generation produced a three-row reviewable blueprint. Confirmation created one draft basket with 8 items. Exact cleanup removed the new review, basket, and 8 items; the paper-table fingerprint returned from and to `37f1b1a968338e9cbb6e72840b1934c9`.
- Score evidence analysis reused non-PII draft/test assessment `46a2399a-0854-40fc-ab8c-9e1dd7488f1f`. It failed closed with `Q1/Q2: question_mapping_missing`; knowledge, ability, error, and recommendation sections stayed empty instead of displaying a diagnosis.

## Source-page evidence

- Curriculum page endpoint rendered image title `screenshot (1192x1684)`.
- Annual-report page endpoint rendered image title `page-screenshot (1191x1684)`.
- Both were opened in controlled browser tabs using hrefs exposed by the visible candidate card.
- The raw source-page screenshots were removed from Git after the privacy/license scan identified them as tracked copyright-source binaries. This report retains the runtime observation and dimensions, but the source pages remain outside the repository.

## Visual and console checks

Desktop viewport was `1280x720` (`1265x712` captured content); mobile viewport was `390x844` (`375x812` captured content).

- Desktop and mobile document `scrollWidth == clientWidth`.
- Interactive-control overlap scan returned 0 overlaps.
- Horizontal viewport overflow scan returned 0 elements.
- The mobile review mode selector initially required horizontal scrolling. CEK-33 changed it to a visible `3 + 2` layout; its final `scrollWidth == clientWidth == 289`.
- `AnalysisPanelContent` migrated deprecated Ant Design `Alert.message` to `Alert.title`; a fresh tab then reported 0 `error`, `warn`, or `warning` console entries.
- Seven PNGs passed sampled non-blank checks with 108-345 distinct sampled colors during the run. Five product-UI screenshots remain as reviewed repository evidence; two raw source-page captures are intentionally not retained.

Screenshots:

- `docs/evidence/cek033-desktop-candidate-search.png`
- `docs/evidence/cek033-desktop-analysis.png`
- `docs/evidence/cek033-mobile-candidate-search.png`
- `docs/evidence/cek033-mobile-analysis.png`
- `docs/evidence/cek033-mobile-review.png`

## Verification

- Web tests: 6 files, 36/36 passed.
- Web lint: passed.
- Web production build: passed.
- CEK-26 review UI contract: passed.
- CEK-30 search UI contract: passed.
- Fresh browser console: 0 error/warn entries.
- Web/API health: `ok`/`ok`.

## Boundary and rollback

This is repo-side local-browser acceptance for CEK-33 and Checkpoint G2. It does not prove real teacher sign-off, identity authorization, school-network or isolated-machine behavior, production activation, or `REAL005` closure. Review candidates were restored by audited undo; temporary paper data was deleted by exact IDs and fingerprint-verified. Code rollback is limited to the CEK-33 CSS layout and Ant Design property update.
