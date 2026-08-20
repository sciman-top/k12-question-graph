using K12QuestionGraph.Api.Application.Workflows.Contracts;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.Infrastructure.Queries;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace K12QuestionGraph.Api.Application.Workflows;

public sealed class KnowledgeEvidenceWorkflowService(KqgDbContext dbContext)
{
    private const string CurriculumRequirementImportKey = "cek009_curriculum_requirements_2022_2025_v1";
    private const string RegionalProfileImportKey = "cek023_regional_exam_profile_candidate_v1";

    private static readonly HashSet<string> AllowedReviewStatuses = new(StringComparer.Ordinal)
    {
        "pending_review", "approved", "rejected"
    };

    public static int NormalizeTake(int take) => Math.Clamp(take, 1, 500);

    public static string NormalizeReviewStatus(string? reviewStatus)
    {
        var normalized = string.IsNullOrWhiteSpace(reviewStatus)
            ? "pending_review"
            : reviewStatus.Trim().ToLowerInvariant();
        if (!AllowedReviewStatuses.Contains(normalized))
        {
            throw new ArgumentException("invalid_review_status", nameof(reviewStatus));
        }

        return normalized;
    }

    public static string NormalizeEvidenceMode(string? evidenceMode)
    {
        var normalized = string.IsNullOrWhiteSpace(evidenceMode)
            ? "active"
            : evidenceMode.Trim().ToLowerInvariant();
        if (normalized is not ("active" or "reviewed" or "candidate"))
        {
            throw new ArgumentException("invalid_evidence_mode", nameof(evidenceMode));
        }

        return normalized;
    }

    public static void ValidateQuestionEvidenceSearchRequest(QuestionEvidenceSearchRequest request)
    {
        var mode = NormalizeEvidenceMode(request.EvidenceMode);
        if (mode != "active" && !request.PreviewMode)
        {
            throw new ArgumentException("preview_mode_required", nameof(request.PreviewMode));
        }

        if ((request.ObservedDifficultyMin.HasValue && request.ObservedDifficultyMax.HasValue
                && request.ObservedDifficultyMin > request.ObservedDifficultyMax)
            || (request.EstimatedDifficultyMin.HasValue && request.EstimatedDifficultyMax.HasValue
                && request.EstimatedDifficultyMin > request.EstimatedDifficultyMax))
        {
            throw new ArgumentException("invalid_difficulty_range", nameof(request));
        }
    }

    public async Task<QuestionEvidenceSearchResponse> SearchQuestionsAsync(
        QuestionEvidenceSearchRequest request,
        CancellationToken cancellationToken)
    {
        ValidateQuestionEvidenceSearchRequest(request);
        var mode = NormalizeEvidenceMode(request.EvidenceMode);
        var previewMode = mode != "active";
        var pagination = PaginationWindow.Create(request.Page, request.PageSize, defaultPageSize: 20, maxPageSize: 50);
        var page = pagination.Page;
        var pageSize = pagination.PageSize;

        var targetQuery = dbContext.AssessmentTargets.AsNoTracking().AsQueryable();
        targetQuery = mode switch
        {
            "active" => targetQuery.Where(target => target.Status == "active"
                && target.ReviewStatus == "approved" && target.ProductionEligible),
            "reviewed" => targetQuery.Where(target => target.Status == "reviewed"
                && target.ReviewStatus == "approved" && !target.ProductionEligible),
            _ => targetQuery.Where(target => target.Status == "candidate"
                && target.ReviewStatus != "rejected" && !target.ProductionEligible),
        };

        if (!string.IsNullOrWhiteSpace(request.Ability))
        {
            var filter = BuildStringArrayJsonFilter("abilityDimensions", request.Ability);
            targetQuery = targetQuery.Where(target => EF.Functions.JsonContains(target.Metadata, filter));
        }
        if (!string.IsNullOrWhiteSpace(request.CognitiveDemand))
        {
            var filter = BuildStringArrayJsonFilter("cognitiveDemands", request.CognitiveDemand);
            targetQuery = targetQuery.Where(target => EF.Functions.JsonContains(target.Metadata, filter));
        }
        if (!string.IsNullOrWhiteSpace(request.MethodOrExperiment))
        {
            var filter = BuildStringArrayJsonFilter("methodModelExperimentIds", request.MethodOrExperiment);
            targetQuery = targetQuery.Where(target => EF.Functions.JsonContains(target.Metadata, filter));
        }
        if (!string.IsNullOrWhiteSpace(request.Context))
        {
            var filter = BuildStringJsonFilter("contextType", request.Context);
            targetQuery = targetQuery.Where(target => EF.Functions.JsonContains(target.Metadata, filter));
        }
        if (!string.IsNullOrWhiteSpace(request.Representation))
        {
            var filter = BuildStringArrayJsonFilter("representationTypes", request.Representation);
            targetQuery = targetQuery.Where(target => EF.Functions.JsonContains(target.Metadata, filter));
        }

        IQueryable<CurriculumAlignment> AlignmentQuery() => mode switch
        {
            "active" => dbContext.CurriculumAlignments.AsNoTracking()
                .Where(alignment => alignment.Status == "active"
                    && alignment.ReviewStatus == "approved" && alignment.ProductionEligible),
            "reviewed" => dbContext.CurriculumAlignments.AsNoTracking()
                .Where(alignment => alignment.Status == "reviewed"
                    && alignment.ReviewStatus == "approved" && !alignment.ProductionEligible),
            _ => dbContext.CurriculumAlignments.AsNoTracking()
                .Where(alignment => alignment.Status == "candidate"
                    && alignment.ReviewStatus != "rejected" && !alignment.ProductionEligible),
        };

        IQueryable<Guid> CurriculumTargetIds(string stableId)
        {
            var assetIds = dbContext.DomainAssetVersions.AsNoTracking()
                .Where(asset => asset.StableId == stableId && asset.Status == mode)
                .Select(asset => asset.Id);
            return AlignmentQuery()
                .Where(alignment => assetIds.Contains(alignment.CurriculumAssetVersionId))
                .Select(alignment => alignment.AssessmentTargetId);
        }

        if (!string.IsNullOrWhiteSpace(request.RequirementId))
        {
            var targetIds = CurriculumTargetIds(request.RequirementId.Trim());
            targetQuery = targetQuery.Where(target => targetIds.Contains(target.Id));
        }
        if (!string.IsNullOrWhiteSpace(request.FacetId))
        {
            var targetIds = CurriculumTargetIds(request.FacetId.Trim());
            targetQuery = targetQuery.Where(target => targetIds.Contains(target.Id));
        }

        IQueryable<ObservedPerformanceEvidence> ObservedQuery() => mode switch
        {
            "active" => dbContext.ObservedPerformanceEvidence.AsNoTracking()
                .Where(evidence => evidence.Status == "active"
                    && evidence.ReviewStatus == "approved" && evidence.ProductionEligible),
            "reviewed" => dbContext.ObservedPerformanceEvidence.AsNoTracking()
                .Where(evidence => evidence.Status == "reviewed"
                    && evidence.ReviewStatus == "approved" && !evidence.ProductionEligible),
            _ => dbContext.ObservedPerformanceEvidence.AsNoTracking()
                .Where(evidence => evidence.Status == "candidate"
                    && evidence.ReviewStatus != "rejected" && !evidence.ProductionEligible),
        };

        if (request.ObservedDifficultyMin.HasValue || request.ObservedDifficultyMax.HasValue)
        {
            var observed = ObservedQuery().Where(evidence => evidence.DifficultyObserved.HasValue);
            if (request.ObservedDifficultyMin.HasValue)
            {
                var minimum = request.ObservedDifficultyMin.Value;
                observed = observed.Where(evidence => evidence.DifficultyObserved >= minimum);
            }
            if (request.ObservedDifficultyMax.HasValue)
            {
                var maximum = request.ObservedDifficultyMax.Value;
                observed = observed.Where(evidence => evidence.DifficultyObserved <= maximum);
            }
            var targetIds = observed.Select(evidence => evidence.AssessmentTargetId);
            targetQuery = targetQuery.Where(target => targetIds.Contains(target.Id));
        }

        var profileAssets = await dbContext.DomainAssetVersions.AsNoTracking()
            .Where(asset => asset.AssetType == "exam_point" && asset.Status == mode
                && EF.Functions.JsonContains(asset.SourceEvidence, BuildStringJsonFilter("importKey", RegionalProfileImportKey)))
            .OrderBy(asset => asset.StableId)
            .ToArrayAsync(cancellationToken);
        if (!string.IsNullOrWhiteSpace(request.ProfileId))
        {
            var profile = profileAssets.FirstOrDefault(asset => string.Equals(
                asset.StableId,
                request.ProfileId.Trim(),
                StringComparison.OrdinalIgnoreCase));
            IReadOnlyList<Guid> targetIds = profile is null
                ? []
                : ReadGuidArray(ParseJsonElement(profile.SourceEvidence), "evidenceTargetIds");
            targetQuery = targetQuery.Where(target => targetIds.Contains(target.Id));
        }

        var targetQuestionIds = targetQuery.Select(target => target.QuestionItemId).Distinct();
        var questionQuery = dbContext.QuestionItems.AsNoTracking()
            .Where(question => targetQuestionIds.Contains(question.Id));
        if (request.EstimatedDifficultyMin.HasValue)
        {
            var minimum = request.EstimatedDifficultyMin.Value;
            questionQuery = questionQuery.Where(question => question.DifficultyEstimated.HasValue
                && question.DifficultyEstimated >= minimum);
        }
        if (request.EstimatedDifficultyMax.HasValue)
        {
            var maximum = request.EstimatedDifficultyMax.Value;
            questionQuery = questionQuery.Where(question => question.DifficultyEstimated.HasValue
                && question.DifficultyEstimated <= maximum);
        }
        if (!string.IsNullOrWhiteSpace(request.SourceType))
        {
            var sourceType = request.SourceType.Trim().ToLowerInvariant();
            var blockQuestionIds =
                from block in dbContext.QuestionBlocks.AsNoTracking()
                where block.SourceRegionId != null
                join region in dbContext.SourceRegions.AsNoTracking() on block.SourceRegionId!.Value equals region.Id
                join document in dbContext.SourceDocuments.AsNoTracking() on region.SourceDocumentId equals document.Id
                where document.SourceType == sourceType
                select block.QuestionItemId;
            var assetQuestionIds =
                from asset in dbContext.QuestionAssets.AsNoTracking()
                where asset.SourceRegionId != null
                join region in dbContext.SourceRegions.AsNoTracking() on asset.SourceRegionId!.Value equals region.Id
                join document in dbContext.SourceDocuments.AsNoTracking() on region.SourceDocumentId equals document.Id
                where document.SourceType == sourceType
                select asset.QuestionItemId;
            var sourceQuestionIds = blockQuestionIds.Concat(assetQuestionIds).Distinct();
            questionQuery = questionQuery.Where(question => sourceQuestionIds.Contains(question.Id));
        }

        var total = await questionQuery.CountAsync(cancellationToken);
        var questions = await questionQuery
            .OrderByDescending(question => question.UpdatedAt)
            .ThenBy(question => question.Id)
            .Skip(pagination.Offset)
            .Take(pageSize)
            .ToArrayAsync(cancellationToken);
        var questionIds = questions.Select(question => question.Id).ToArray();
        var targets = await (mode switch
        {
            "active" => dbContext.AssessmentTargets.AsNoTracking().Where(target => target.Status == "active"
                && target.ReviewStatus == "approved" && target.ProductionEligible),
            "reviewed" => dbContext.AssessmentTargets.AsNoTracking().Where(target => target.Status == "reviewed"
                && target.ReviewStatus == "approved" && !target.ProductionEligible),
            _ => dbContext.AssessmentTargets.AsNoTracking().Where(target => target.Status == "candidate"
                && target.ReviewStatus != "rejected" && !target.ProductionEligible),
        })
            .Where(target => questionIds.Contains(target.QuestionItemId))
            .OrderByDescending(target => target.IsPrimaryTarget)
            .ThenBy(target => target.StableKey)
            .ToArrayAsync(cancellationToken);
        var targetIdsForPage = targets.Select(target => target.Id).ToArray();

        var knowledgeMappings = await dbContext.AssessmentTargetKnowledgeMappings.AsNoTracking()
            .Where(mapping => targetIdsForPage.Contains(mapping.AssessmentTargetId)
                && mapping.ReviewStatus != "rejected")
            .OrderBy(mapping => mapping.Role)
            .ToArrayAsync(cancellationToken);
        var knowledgeAssetIds = knowledgeMappings.Select(mapping => mapping.DomainAssetVersionId).Distinct().ToArray();
        var knowledgeAssets = await dbContext.DomainAssetVersions.AsNoTracking()
            .Where(asset => knowledgeAssetIds.Contains(asset.Id))
            .ToDictionaryAsync(asset => asset.Id, cancellationToken);

        var alignments = await AlignmentQuery()
            .Where(alignment => targetIdsForPage.Contains(alignment.AssessmentTargetId))
            .OrderBy(alignment => alignment.StableKey)
            .ToArrayAsync(cancellationToken);
        var curriculumAssetIds = alignments.Select(alignment => alignment.CurriculumAssetVersionId).Distinct().ToArray();
        var curriculumAssets = await dbContext.DomainAssetVersions.AsNoTracking()
            .Where(asset => curriculumAssetIds.Contains(asset.Id))
            .ToDictionaryAsync(asset => asset.Id, cancellationToken);
        var observedRows = await ObservedQuery()
            .Where(evidence => targetIdsForPage.Contains(evidence.AssessmentTargetId)
                && evidence.DifficultyObserved.HasValue)
            .OrderBy(evidence => evidence.StableKey)
            .ToArrayAsync(cancellationToken);

        var knowledgeLookup = knowledgeMappings.ToLookup(mapping => mapping.AssessmentTargetId);
        var alignmentLookup = alignments.ToLookup(alignment => alignment.AssessmentTargetId);
        var observedLookup = observedRows.ToLookup(evidence => evidence.AssessmentTargetId);
        var profileLookup = profileAssets
            .SelectMany(profile => ReadGuidArray(ParseJsonElement(profile.SourceEvidence), "evidenceTargetIds")
                .Select(targetId => new { targetId, profile }))
            .Where(entry => targetIdsForPage.Contains(entry.targetId))
            .ToLookup(entry => entry.targetId, entry => entry.profile);
        var targetLookup = targets.ToLookup(target => target.QuestionItemId);

        var cards = questions.Select(question => new QuestionEvidenceCardDto(
            question.Id,
            ReadInt(ParseJsonElement(question.CustomFields), "questionNo"),
            question.Subject,
            question.Stage,
            question.Grade,
            question.QuestionType,
            question.Status,
            question.DifficultyEstimated,
            "question_estimated",
            targetLookup[question.Id].Select(target =>
            {
                var metadata = ParseJsonElement(target.Metadata);
                var knowledge = knowledgeLookup[target.Id]
                    .Where(mapping => knowledgeAssets.ContainsKey(mapping.DomainAssetVersionId))
                    .Select(mapping =>
                    {
                        var asset = knowledgeAssets[mapping.DomainAssetVersionId];
                        return new QuestionEvidenceKnowledgeDto(
                            asset.StableId,
                            asset.DisplayName,
                            mapping.Role,
                            mapping.Confidence,
                            mapping.Status,
                            mapping.ReviewStatus);
                    }).ToArray();
                var requirements = alignmentLookup[target.Id]
                    .Where(alignment => curriculumAssets.ContainsKey(alignment.CurriculumAssetVersionId))
                    .Select(alignment =>
                    {
                        var asset = curriculumAssets[alignment.CurriculumAssetVersionId];
                        var curriculumSource = CurriculumSourceAnchorParser.ReadFirst(asset.SourceEvidence);
                        return new QuestionEvidenceRequirementDto(
                            asset.StableId,
                            asset.DisplayName,
                            alignment.AlignmentType,
                            alignment.OriginalBasis,
                            alignment.AlignmentType,
                            alignment.SourceDocumentId,
                            alignment.SourceRegionId,
                            alignment.Confidence,
                            CurriculumSourceDocumentId: curriculumSource?.SourceDocumentId,
                            CurriculumSourceRegionId: curriculumSource?.SourceRegionId,
                            CurriculumSourcePageNumber: curriculumSource?.PageNumber);
                    }).ToArray();
                var observed = observedLookup[target.Id]
                    .Select(evidence => new QuestionObservedDifficultyDto(
                        evidence.DifficultyObserved!.Value,
                        evidence.DifficultyDirection,
                        evidence.SampleScope,
                        evidence.SourceRegionId,
                        evidence.Status,
                        evidence.ReviewStatus))
                    .ToArray();
                var profiles = profileLookup[target.Id]
                    .Select(profile => new QuestionEvidenceProfileDto(
                        profile.StableId,
                        profile.DisplayName,
                        profile.Status,
                        ReadNestedString(ParseJsonElement(profile.Metadata), "trend", "status")))
                    .ToArray();
                return new QuestionAssessmentTargetEvidenceDto(
                    target.Id,
                    target.StableKey,
                    target.ScopeType,
                    target.TargetStatement,
                    target.IsPrimaryTarget,
                    target.Confidence,
                    target.Status,
                    target.ReviewStatus,
                    target.ProductionEligible,
                    ReadStringArray(metadata, "abilityDimensions"),
                    ReadStringArray(metadata, "cognitiveDemands"),
                    ReadStringArray(metadata, "methodModelExperimentIds"),
                    ReadString(metadata, "contextType"),
                    ReadStringArray(metadata, "representationTypes"),
                    knowledge,
                    requirements,
                    observed,
                    profiles);
            }).ToArray(),
            ProductionEligible: mode == "active"))
            .ToArray();

        return new QuestionEvidenceSearchResponse(
            mode,
            previewMode,
            ProductionEligible: mode == "active",
            total,
            page,
            pageSize,
            cards,
            "updated_at_desc,id_asc",
            previewMode
                ? "Explicit candidate/reviewed preview only; productionEligible=false and retrospective alignment labels are preserved."
                : "Active evidence only; candidate and reviewed evidence is excluded unless previewMode=true is explicit.");
    }

    public async Task<CurriculumEvidenceReplacementOptionsResponse?> GetCurriculumEvidenceReplacementOptionsAsync(
        Guid candidateId,
        CancellationToken cancellationToken)
    {
        var curriculumAlignment = await dbContext.CurriculumAlignments
            .AsNoTracking()
            .FirstOrDefaultAsync(row => row.Id == candidateId, cancellationToken);
        if (curriculumAlignment is not null)
        {
            if (curriculumAlignment.ProductionEligible
                || !AllowedReviewStatuses.Contains(curriculumAlignment.ReviewStatus))
            {
                return null;
            }

            var requirementFacets = await dbContext.DomainAssetVersions
                .AsNoTracking()
                .Where(asset => asset.AssetType == "requirement_facet"
                    && asset.Id != curriculumAlignment.CurriculumAssetVersionId)
                .ToArrayAsync(cancellationToken);
            var options = requirementFacets
                .Where(asset => IsAssetReviewEligible(asset, "requirement"))
                .Select(ToReplacementOption)
                .OrderBy(option => option.DisplayName, StringComparer.Ordinal)
                .ThenBy(option => option.StableKey, StringComparer.Ordinal)
                .ToArray();
            return ReplacementOptionsResponse(options);
        }

        var mapping = await dbContext.DomainAssetMappings
            .AsNoTracking()
            .FirstOrDefaultAsync(row => row.Id == candidateId, cancellationToken);
        if (mapping is null || !IsMappingReviewEligible(mapping))
        {
            return null;
        }

        var currentTarget = await dbContext.DomainAssetVersions
            .AsNoTracking()
            .FirstOrDefaultAsync(asset => asset.Id == mapping.TargetAssetVersionId, cancellationToken);
        if (currentTarget is null)
        {
            return null;
        }

        var knowledgeAssets = await dbContext.DomainAssetVersions
            .AsNoTracking()
            .Where(asset => asset.AssetType == "knowledge_point"
                && asset.Status == DomainAssetStatuses.Active
                && asset.Id != mapping.TargetAssetVersionId
                && asset.Id != mapping.SourceAssetVersionId)
            .ToArrayAsync(cancellationToken);
        var mappingOptions = knowledgeAssets
            .Where(asset => IsMappingReplacementEligible(currentTarget, asset))
            .Select(ToReplacementOption)
            .OrderBy(option => option.DisplayName, StringComparer.Ordinal)
            .ThenBy(option => option.StableKey, StringComparer.Ordinal)
            .ToArray();
        return ReplacementOptionsResponse(mappingOptions);
    }

    private static CurriculumEvidenceReplacementOptionDto ToReplacementOption(DomainAssetVersion asset) =>
        new(asset.Id, asset.StableId, asset.DisplayName);

    private static CurriculumEvidenceReplacementOptionsResponse ReplacementOptionsResponse(
        IReadOnlyList<CurriculumEvidenceReplacementOptionDto> options) =>
        new(
            options,
            ProductionEligible: false,
            CompletionBoundary: "Replacement choices stay inside the current candidate or active asset family; selecting one only creates a pending review mapping change.");

    internal static IReadOnlyList<ErrorPatternCandidate> BuildErrorPatternCandidates(
        IEnumerable<ErrorPatternEvidenceInput> evidence,
        IEnumerable<ErrorPatternTaxonomyEntry> taxonomy,
        string normalizationMethod)
    {
        ArgumentNullException.ThrowIfNull(evidence);
        ArgumentNullException.ThrowIfNull(taxonomy);
        if (string.IsNullOrWhiteSpace(normalizationMethod))
        {
            throw new ArgumentException("invalid_normalization_method", nameof(normalizationMethod));
        }

        var normalizedMethod = normalizationMethod.Trim();
        var taxonomyByCode = taxonomy
            .Where(entry => !string.IsNullOrWhiteSpace(entry.Code))
            .ToDictionary(
                entry => NormalizePatternCode(entry.Code),
                entry => entry,
                StringComparer.Ordinal);
        var validEvidence = evidence
            .Where(item => item.EvidenceId != Guid.Empty
                && item.AssessmentTargetId != Guid.Empty
                && item.QuestionItemId != Guid.Empty
                && item.ExamYear >= 1900
                && item.ExamYear <= DateTime.UtcNow.Year + 1)
            .Select(item => item with { PatternCode = NormalizePatternCode(item.PatternCode) })
            .Where(item => taxonomyByCode.ContainsKey(item.PatternCode))
            .GroupBy(item => item.EvidenceId)
            .Select(group => group.First())
            .ToArray();
        var candidates = new List<ErrorPatternCandidate>();

        foreach (var group in validEvidence.GroupBy(item => item.PatternCode, StringComparer.Ordinal))
        {
            var groupedEvidence = group.ToArray();
            var distinctQuestionCount = groupedEvidence.Select(item => item.QuestionItemId).Distinct().Count();
            var distinctExamYearCount = groupedEvidence.Select(item => item.ExamYear).Distinct().Count();
            if (groupedEvidence.Length < 2 || (distinctQuestionCount < 2 && distinctExamYearCount < 2))
            {
                continue;
            }

            var taxonomyEntry = taxonomyByCode[group.Key];
            var evidenceIds = groupedEvidence.Select(item => item.EvidenceId).Distinct().ToArray();
            var targetIds = groupedEvidence.Select(item => item.AssessmentTargetId).Distinct().ToArray();
            var years = groupedEvidence.Select(item => item.ExamYear).Distinct().Order().ToArray();
            var stabilityBasis = distinctQuestionCount >= 2 && distinctExamYearCount >= 2
                ? "cross_question_and_year"
                : distinctQuestionCount >= 2
                    ? "cross_question"
                    : "cross_year";
            var promotion = BuildPromotionDecision(taxonomyEntry);
            var stableId = $"ERR-{group.Key.ToUpperInvariant().Replace('_', '-')}";
            var asset = new DomainAssetVersion
            {
                Id = CreateDeterministicGuid($"error_pattern:{group.Key}"),
                AssetType = "error_pattern",
                StableId = stableId,
                Version = 1,
                DisplayName = taxonomyEntry.DisplayName,
                Status = DomainAssetStatuses.Candidate,
                Authority = DomainAssetAuthorities.SourceDerived,
                EffectiveScope = JsonSerializer.Serialize(new
                {
                    subject = "junior_physics",
                    region = "guangzhou",
                    examYears = years
                }),
                SourceEvidence = JsonSerializer.Serialize(new
                {
                    evidenceIds,
                    assessmentTargetIds = targetIds
                }),
                Metadata = JsonSerializer.Serialize(new
                {
                    patternCode = group.Key,
                    taxonomyEntry.SemanticType,
                    evidenceCount = groupedEvidence.Length,
                    distinctQuestionCount,
                    distinctExamYearCount,
                    evidenceTargetIds = targetIds,
                    normalizationMethod = normalizedMethod,
                    reviewerStatus = DomainAssetReviewStatuses.PendingReview,
                    productionEligible = false,
                    stabilityBasis,
                    promotion
                })
            };

            candidates.Add(new ErrorPatternCandidate(
                asset,
                groupedEvidence.Length,
                distinctQuestionCount,
                distinctExamYearCount,
                targetIds,
                normalizedMethod,
                DomainAssetReviewStatuses.PendingReview,
                ProductionEligible: false,
                stabilityBasis,
                promotion));
        }

        return candidates.OrderBy(candidate => candidate.Asset.StableId, StringComparer.Ordinal).ToArray();
    }

    private static string NormalizePatternCode(string? value) =>
        string.IsNullOrWhiteSpace(value) ? string.Empty : value.Trim().ToLowerInvariant();

    private static MisconceptionPromotionDecision BuildPromotionDecision(ErrorPatternTaxonomyEntry entry) =>
        entry.MisconceptionEligible
            ? new(
                "pending_review",
                "misconception",
                RequiresHumanReview: true,
                RequiresC002RImpactReport: true,
                RequiresRollbackSnapshot: true,
                AutoApplyAllowed: false)
            : new(
                "not_eligible",
                TargetKnowledgeType: null,
                RequiresHumanReview: false,
                RequiresC002RImpactReport: false,
                RequiresRollbackSnapshot: false,
                AutoApplyAllowed: false);

    private static Guid CreateDeterministicGuid(string value)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        hash[6] = (byte)((hash[6] & 0x0F) | 0x50);
        hash[8] = (byte)((hash[8] & 0x3F) | 0x80);
        return new Guid(hash.AsSpan(0, 16));
    }

    internal static RegionalExamProfileDetailResponse? ProjectRegionalExamProfile(DomainAssetVersion asset)
    {
        if (!string.Equals(asset.AssetType, "exam_point", StringComparison.Ordinal)
            || !string.Equals(asset.Status, DomainAssetStatuses.Candidate, StringComparison.Ordinal))
        {
            return null;
        }

        try
        {
            using var metadataDocument = JsonDocument.Parse(asset.Metadata);
            using var evidenceDocument = JsonDocument.Parse(asset.SourceEvidence);
            var metadata = metadataDocument.RootElement;
            var evidence = evidenceDocument.RootElement;
            if (!metadata.TryGetProperty("semantic_type", out var semanticType)
                || semanticType.GetString() != "RegionalExamPointProfile"
                || !metadata.TryGetProperty("storage_asset_type", out var storageAssetType)
                || storageAssetType.GetString() != "exam_point"
                || !metadata.TryGetProperty("review_status", out var reviewStatus)
                || reviewStatus.GetString() != DomainAssetReviewStatuses.PendingReview
                || !metadata.TryGetProperty("production_eligible", out var productionEligible)
                || productionEligible.ValueKind != JsonValueKind.False
                || !metadata.TryGetProperty("diagnostics", out var diagnostics)
                || diagnostics.ValueKind != JsonValueKind.Object
                || !evidence.TryGetProperty("importKey", out var importKeyElement)
                || importKeyElement.GetString() != RegionalProfileImportKey
                || !evidence.TryGetProperty("evidenceTargetIds", out var targetIds)
                || targetIds.ValueKind != JsonValueKind.Array)
            {
                return null;
            }

            var evidenceTargetIds = new List<Guid>();
            foreach (var value in targetIds.EnumerateArray())
            {
                if (value.ValueKind != JsonValueKind.String
                    || !Guid.TryParse(value.GetString(), out var targetId))
                {
                    return null;
                }

                evidenceTargetIds.Add(targetId);
            }

            if (evidenceTargetIds.Count == 0)
            {
                return null;
            }

            return new RegionalExamProfileDetailResponse(
                asset.Id,
                asset.StableId,
                asset.Version,
                asset.DisplayName,
                asset.Status,
                DomainAssetReviewStatuses.PendingReview,
                ProductionEligible: false,
                metadata.Clone(),
                diagnostics.Clone(),
                evidenceTargetIds.Distinct().Order().ToArray(),
                importKeyElement.GetString()!,
                "Candidate regional exam profile only; teacher review and C002R activation remain required.");
        }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException)
        {
            return null;
        }
    }

    public async Task<RegionalExamProfileDetailResponse?> GetRegionalExamProfileAsync(
        string stableId,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(stableId))
        {
            return null;
        }

        var asset = await dbContext.DomainAssetVersions
            .AsNoTracking()
            .Where(x => x.AssetType == "exam_point"
                && x.StableId == stableId.Trim()
                && x.Status == DomainAssetStatuses.Candidate)
            .OrderByDescending(x => x.Version)
            .FirstOrDefaultAsync(cancellationToken);
        return asset is null ? null : ProjectRegionalExamProfile(asset);
    }

    public async Task<KnowledgeEvidenceListResponse> ListAssessmentTargetsAsync(
        KnowledgeEvidenceListRequest request,
        CancellationToken cancellationToken)
    {
        var reviewStatus = NormalizeReviewStatus(request.ReviewStatus);
        var take = NormalizeTake(request.Take);
        var targets = await dbContext.AssessmentTargets
            .AsNoTracking()
            .Where(x => x.ReviewStatus == reviewStatus)
            .OrderBy(x => x.CreatedAt)
            .Take(take)
            .ToListAsync(cancellationToken);
        var targetIds = targets.Select(x => x.Id).ToArray();
        var primaryMappings = await dbContext.AssessmentTargetKnowledgeMappings
            .AsNoTracking()
            .Where(x => targetIds.Contains(x.AssessmentTargetId) && x.Role == "primary")
            .ToDictionaryAsync(x => x.AssessmentTargetId, x => x.DomainAssetVersionId, cancellationToken);
        var alignments = await dbContext.CurriculumAlignments
            .AsNoTracking()
            .Where(x => targetIds.Contains(x.AssessmentTargetId))
            .OrderBy(x => x.CreatedAt)
            .ToListAsync(cancellationToken);
        var alignmentLookup = alignments.ToLookup(x => x.AssessmentTargetId);
        var items = targets.Select(target => new KnowledgeEvidenceTargetDto(
            target.Id,
            target.StableKey,
            target.QuestionItemId,
            target.QuestionBlockId,
            target.ScopeType,
            target.TargetStatement,
            target.Confidence,
            target.Status,
            target.ReviewStatus,
            target.ProductionEligible,
            primaryMappings.GetValueOrDefault(target.Id),
            target.Metadata,
            alignmentLookup[target.Id].Select(row => new KnowledgeEvidenceAlignmentDto(
                row.Id,
                row.StableKey,
                row.AlignmentType,
                row.StandardVersion,
                row.Confidence,
                row.OriginalBasis,
                row.Status,
                row.ReviewStatus,
                row.ProductionEligible,
                row.Evidence)).ToArray())).ToArray();

        return new KnowledgeEvidenceListResponse(
            items,
            items.Length,
            reviewStatus,
            ProductionEligible: false,
            "Candidate evidence only; retrospective mappings are not original exam-setting evidence and require teacher review.");
    }

    public async Task<ObservedEvidenceListResponse> ListObservedEvidenceAsync(
        ObservedEvidenceListRequest request,
        CancellationToken cancellationToken)
    {
        var reviewStatus = NormalizeReviewStatus(request.ReviewStatus);
        var take = NormalizeTake(request.Take);
        var performanceQuery = dbContext.ObservedPerformanceEvidence
            .AsNoTracking()
            .Where(x => x.ReviewStatus == reviewStatus);
        var errorQuery = dbContext.ObservedErrorEvidence
            .AsNoTracking()
            .Where(x => x.ReviewStatus == reviewStatus);
        var recommendationQuery = dbContext.TeachingRecommendations
            .AsNoTracking()
            .Where(x => x.ReviewStatus == reviewStatus);
        if (request.AssessmentTargetId.HasValue)
        {
            var targetId = request.AssessmentTargetId.Value;
            performanceQuery = performanceQuery.Where(x => x.AssessmentTargetId == targetId);
            errorQuery = errorQuery.Where(x => x.AssessmentTargetId == targetId);
            recommendationQuery = recommendationQuery.Where(x => x.AssessmentTargetId == targetId);
        }

        var performance = await performanceQuery
            .OrderBy(x => x.CreatedAt)
            .Take(take)
            .Select(x => new ObservedPerformanceEvidenceDto(
                x.Id, x.AssessmentTargetId, x.SourceRegionId, x.MaximumScore, x.AverageScore,
                x.ScoreRate, x.DifficultyObserved, x.Discrimination, x.DifficultyDirection,
                x.SampleScope, x.SampleSize, x.OptionDistribution, x.RawStatistics, x.Confidence,
                x.Status, x.ReviewStatus, x.ProductionEligible, x.Evidence))
            .ToArrayAsync(cancellationToken);
        var errors = await errorQuery
            .OrderBy(x => x.CreatedAt)
            .Take(take)
            .Select(x => new ObservedErrorEvidenceDto(
                x.Id, x.AssessmentTargetId, x.SourceRegionId, x.RecordKind, x.Content,
                x.GenerationMethod, x.Confidence, x.Status, x.ReviewStatus,
                x.ProductionEligible, x.Evidence))
            .ToArrayAsync(cancellationToken);
        var recommendations = await recommendationQuery
            .OrderBy(x => x.CreatedAt)
            .Take(take)
            .Select(x => new TeachingRecommendationDto(
                x.Id, x.AssessmentTargetId, x.SourceRegionId, x.Content, x.AuthorKind,
                x.GenerationMethod, x.Confidence, x.Status, x.ReviewStatus,
                x.ProductionEligible, x.Evidence))
            .ToArrayAsync(cancellationToken);

        return new ObservedEvidenceListResponse(
            performance,
            errors,
            recommendations,
            performance.Length,
            errors.Length,
            recommendations.Length,
            reviewStatus,
            request.AssessmentTargetId,
            ProductionEligible: false,
            "Report-derived candidate evidence only; observed metrics, interpreted errors, and teaching recommendations require teacher review.");
    }

    public async Task<CurriculumEvidenceReviewListResponse> ListCurriculumEvidenceReviewsAsync(
        CurriculumEvidenceReviewListRequest request,
        CancellationToken cancellationToken)
    {
        var pagination = PaginationWindow.Create(request.Page, request.PageSize, defaultPageSize: 100, maxPageSize: 500);
        var page = pagination.Page;
        var pageSize = pagination.PageSize;
        var allItems = await BuildCurriculumEvidenceReviewItemsAsync(cancellationToken);
        if (!string.IsNullOrWhiteSpace(request.GroupId))
        {
            var groupId = request.GroupId.Trim().ToLowerInvariant();
            allItems = allItems
                .Where(item => string.Equals(item.GroupId, groupId, StringComparison.Ordinal))
                .ToArray();
        }

        var ordered = OrderReviewItems(allItems);
        var totalPages = ordered.Count == 0 ? 0 : (int)Math.Ceiling(ordered.Count / (double)pageSize);
        var pageItems = ordered.Skip(pagination.Offset).Take(pageSize).ToArray();
        return new CurriculumEvidenceReviewListResponse(
            pageItems,
            page,
            pageSize,
            ordered.Count,
            totalPages,
            "impact_desc,confidence_asc,stable_key_asc",
            ProductionEligible: false,
            "Review decisions can move candidates between pending, approved, and rejected states only; C002R migration and active switching remain separate administrator gates.");
    }

    public async Task<CurriculumEvidenceDecisionResponse> DecideCurriculumEvidenceAsync(
        CurriculumEvidenceDecisionRequest request,
        CancellationToken cancellationToken)
    {
        ValidateDecisionRequest(request);
        var normalizedDecision = request.Decision.Trim().ToLowerInvariant();
        var normalizedType = request.CandidateType.Trim().ToLowerInvariant();
        var now = DateTimeOffset.UtcNow;
        var mutation = await ApplyCurriculumEvidenceDecisionAsync(
            normalizedType,
            request.CandidateId,
            normalizedDecision,
            request.ReplacementAssetVersionId,
            cancellationToken);
        var payload = BuildDecisionAuditPayload(new CurriculumEvidenceDecisionAuditInput(
            normalizedType,
            request.CandidateId,
            normalizedDecision,
            request.Reviewer.Trim(),
            request.Reason.Trim(),
            request.ActorRole.Trim().ToLowerInvariant(),
            mutation.Before,
            mutation.After,
            mutation.Evidence,
            now));
        var audit = new ReviewQueueItem
        {
            Id = Guid.NewGuid(),
            ReviewType = "curriculum_evidence_decision",
            Status = ReviewStatuses.Resolved,
            Payload = payload,
            CreatedAt = now,
            ResolvedAt = now,
        };
        dbContext.ReviewQueueItems.Add(audit);
        await dbContext.SaveChangesAsync(cancellationToken);

        return BuildDecisionResponse(audit);
    }

    public async Task<CurriculumEvidenceBatchDecisionResponse> BatchApproveCurriculumEvidenceAsync(
        CurriculumEvidenceBatchDecisionRequest request,
        CancellationToken cancellationToken)
    {
        if (request.Items is null || request.Items.Count == 0)
        {
            throw new ArgumentException("review_items_required", nameof(request));
        }

        if (request.Items.Any(item => item is null
                || item.CandidateId == Guid.Empty
                || string.IsNullOrWhiteSpace(item.CandidateType)))
        {
            throw new ArgumentException("candidate_reference_required", nameof(request));
        }

        ValidateReviewer(request.Reviewer, request.Reason, request.ActorRole);
        var distinct = request.Items
            .GroupBy(item => $"{item.CandidateType.Trim().ToLowerInvariant()}:{item.CandidateId}", StringComparer.Ordinal)
            .Select(group => group.First())
            .ToArray();
        var currentItems = await BuildCurriculumEvidenceReviewItemsAsync(cancellationToken);
        foreach (var requested in distinct)
        {
            var type = requested.CandidateType.Trim().ToLowerInvariant();
            var current = currentItems.FirstOrDefault(item =>
                item.CandidateId == requested.CandidateId
                && string.Equals(item.CandidateType, type, StringComparison.Ordinal));
            if (current is null)
            {
                throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
            }

            if (!IsBatchApprovalEligible(current))
            {
                throw new InvalidOperationException($"batch_approval_not_eligible:{type}:{requested.CandidateId}");
            }
        }

        await using var transaction = await dbContext.Database.BeginTransactionAsync(cancellationToken);
        var results = new List<CurriculumEvidenceDecisionResponse>();
        foreach (var item in distinct)
        {
            results.Add(await DecideCurriculumEvidenceAsync(
                new CurriculumEvidenceDecisionRequest(
                    item.CandidateType,
                    item.CandidateId,
                    "approve",
                    request.Reviewer,
                    request.Reason,
                    request.ActorRole),
                cancellationToken));
        }

        await transaction.CommitAsync(cancellationToken);
        return new CurriculumEvidenceBatchDecisionResponse(
            results,
            results.Count,
            ActiveApply: false);
    }

    public async Task<CurriculumEvidenceDecisionResponse> UndoCurriculumEvidenceDecisionAsync(
        Guid decisionId,
        CurriculumEvidenceUndoRequest request,
        CancellationToken cancellationToken)
    {
        ValidateReviewer(request.Reviewer, request.Reason, request.ActorRole);
        var audit = await dbContext.ReviewQueueItems
            .FirstOrDefaultAsync(item => item.Id == decisionId
                && item.ReviewType == "curriculum_evidence_decision", cancellationToken);
        if (audit is null)
        {
            throw new KeyNotFoundException("curriculum_evidence_decision_not_found");
        }

        using var auditDocument = JsonDocument.Parse(audit.Payload);
        var root = auditDocument.RootElement;
        if (!root.TryGetProperty("undo", out var undo)
            || !undo.TryGetProperty("allowed", out var allowed)
            || !allowed.GetBoolean())
        {
            throw new InvalidOperationException("curriculum_evidence_decision_not_undoable");
        }

        var candidateType = root.GetProperty("candidateType").GetString()
            ?? throw new InvalidOperationException("decision_candidate_type_missing");
        var candidateId = root.GetProperty("candidateId").GetGuid();
        var before = root.GetProperty("before").Clone();
        var after = root.GetProperty("after").Clone();
        await RestoreCurriculumEvidenceSnapshotAsync(candidateType, candidateId, before, after, cancellationToken);
        audit.Payload = BuildUndoAuditPayload(audit.Payload, request.Reviewer.Trim(), request.Reason.Trim(), DateTimeOffset.UtcNow);
        audit.Status = ReviewStatuses.Dismissed;
        audit.ResolvedAt = DateTimeOffset.UtcNow;
        await dbContext.SaveChangesAsync(cancellationToken);
        return BuildDecisionResponse(audit);
    }

    public async Task<CurriculumEvidenceReadinessSummary> GetCurriculumEvidenceReadinessAsync(
        CancellationToken cancellationToken)
    {
        var items = await BuildCurriculumEvidenceReviewItemsAsync(cancellationToken);
        var groups = items
            .GroupBy(item => item.GroupId, StringComparer.Ordinal)
            .Select(group => BuildGroupSummary(group.Key, group.ToArray()))
            .OrderBy(group => group.GroupId, StringComparer.Ordinal)
            .ToList();
        var errorPatternItems = items.Where(item => item.CandidateType == "error_pattern").ToArray();
        var errorPatternStatus = errorPatternItems.Length == 0
            ? "blocked_no_persisted_candidates"
            : errorPatternItems.Any(item => item.ReviewStatus == DomainAssetReviewStatuses.PendingReview)
                ? DomainAssetReviewStatuses.PendingReview
                : "reviewed";
        if (errorPatternItems.Length == 0)
        {
            groups.Add(new CurriculumEvidenceReviewGroupSummary(
                "error_patterns",
                "blocked_no_persisted_candidates",
                0,
                0,
                0,
                0,
                "CEK-20 promotion contract passed, but no persisted error-pattern candidates exist to review."));
        }

        var pending = items.Count(item => item.ReviewStatus == DomainAssetReviewStatuses.PendingReview);
        var approved = items.Count(item => item.ReviewStatus == DomainAssetReviewStatuses.Approved);
        var rejected = items.Count(item => item.ReviewStatus == DomainAssetReviewStatuses.Rejected);
        return new CurriculumEvidenceReadinessSummary(
            groups,
            pending,
            approved,
            rejected,
            ReviewComplete: pending == 0 && errorPatternItems.Length > 0,
            ActiveApplyAllowed: false,
            ProductionEligible: false,
            errorPatternStatus,
            "Readiness summarizes review state only. It never authorizes C002R migration, production activation, or silent historical rewrites.");
    }

    internal static IReadOnlyList<CurriculumEvidenceReviewItemDto> OrderReviewItems(
        IEnumerable<CurriculumEvidenceReviewItemDto> items) => items
        .OrderByDescending(item => ImpactRank(item.ImpactLevel))
        .ThenBy(item => item.Confidence)
        .ThenBy(item => item.StableKey, StringComparer.Ordinal)
        .ToArray();

    internal static bool IsBatchApprovalEligible(CurriculumEvidenceReviewItemDto item) =>
        item.ReviewStatus == DomainAssetReviewStatuses.PendingReview
        && item.Confidence >= 0.85m
        && string.Equals(item.ImpactLevel, "low", StringComparison.Ordinal)
        && string.Equals(item.MappingType, DomainAssetMappingTypes.Equivalent, StringComparison.Ordinal)
        && item.Reversible
        && !item.ProductionEligible;

    internal static bool IsAssetReviewEligible(DomainAssetVersion asset, string candidateType)
    {
        if (asset.Status is not (DomainAssetStatuses.Candidate or DomainAssetStatuses.Reviewed))
        {
            return false;
        }

        var metadata = ParseJsonObject(asset.Metadata);
        var sourceEvidence = ParseJsonObject(asset.SourceEvidence);
        var reviewStatus = ReadString(metadata, "review_status", "reviewerStatus")
            ?? ReadString(sourceEvidence, "review_status", "reviewStatus")
            ?? DomainAssetReviewStatuses.PendingReview;
        var productionEligible = ReadBoolean(metadata, "production_eligible", "productionEligible")
            ?? ReadBoolean(sourceEvidence, "production_eligible", "productionEligible");
        if (!AllowedReviewStatuses.Contains(reviewStatus)
            || productionEligible is not false)
        {
            return false;
        }

        return candidateType switch
        {
            "profile" => asset.AssetType == "exam_point"
                && string.Equals(ReadString(metadata, "semantic_type", "semanticType"), "RegionalExamPointProfile", StringComparison.Ordinal)
                && HasImportKey(asset.SourceEvidence, RegionalProfileImportKey),
            "requirement" => asset.AssetType is "curriculum_requirement" or "requirement_facet"
                && HasImportKey(asset.SourceEvidence, CurriculumRequirementImportKey),
            "error_pattern" => asset.AssetType == "error_pattern",
            _ => false,
        };
    }

    internal static bool IsMappingReviewEligible(DomainAssetMapping mapping) =>
        HasImportKey(mapping.Evidence, CurriculumRequirementImportKey)
        && AllowedReviewStatuses.Contains(mapping.ReviewStatus)
        && !mapping.AutoApplied;

    internal static bool IsMappingReplacementEligible(
        DomainAssetVersion currentTarget,
        DomainAssetVersion replacement)
    {
        if (currentTarget.AssetType != "knowledge_point"
            || currentTarget.Status != DomainAssetStatuses.Active
            || replacement.AssetType != "knowledge_point"
            || replacement.Status != DomainAssetStatuses.Active)
        {
            return false;
        }

        var currentImportKey = ReadString(ParseJsonObject(currentTarget.SourceEvidence), "importKey");
        var replacementImportKey = ReadString(ParseJsonObject(replacement.SourceEvidence), "importKey");
        return !string.IsNullOrWhiteSpace(currentImportKey)
            && string.Equals(currentImportKey, replacementImportKey, StringComparison.Ordinal);
    }

    internal static bool SnapshotsMatch(JsonElement expected, JsonElement actual) =>
        JsonNode.DeepEquals(
            CanonicalizeSnapshotNode(JsonNode.Parse(expected.GetRawText())),
            CanonicalizeSnapshotNode(JsonNode.Parse(actual.GetRawText())));

    internal static string BuildDecisionAuditPayload(CurriculumEvidenceDecisionAuditInput input) =>
        JsonSerializer.Serialize(new
        {
            schemaVersion = "curriculum-evidence-review-decision.v1",
            candidateType = input.CandidateType,
            candidateId = input.CandidateId,
            decision = input.Decision,
            reviewer = input.Reviewer,
            reason = input.Reason,
            actorRole = input.ActorRole,
            reviewedAt = input.ReviewedAt,
            before = input.Before,
            after = input.After,
            evidence = input.Evidence,
            undo = new
            {
                allowed = true,
                restores = input.Before,
            },
            activeApply = false,
            productionEligible = false,
        });

    internal static string BuildUndoAuditPayload(
        string decisionPayload,
        string reviewer,
        string reason,
        DateTimeOffset undoneAt)
    {
        var payload = JsonNode.Parse(decisionPayload) as JsonObject
            ?? throw new InvalidOperationException("invalid_decision_audit_payload");
        var before = payload["before"]?.DeepClone()
            ?? throw new InvalidOperationException("decision_before_snapshot_missing");
        var after = payload["after"]?.DeepClone()
            ?? throw new InvalidOperationException("decision_after_snapshot_missing");
        payload["undo"] = new JsonObject
        {
            ["allowed"] = false,
            ["reviewer"] = reviewer,
            ["reason"] = reason,
            ["undoneAt"] = undoneAt,
            ["restored"] = before,
            ["replaced"] = after,
        };
        payload["activeApply"] = false;
        payload["productionEligible"] = false;
        return payload.ToJsonString();
    }

    private async Task<IReadOnlyList<CurriculumEvidenceReviewItemDto>> BuildCurriculumEvidenceReviewItemsAsync(
        CancellationToken cancellationToken)
    {
        var items = new List<CurriculumEvidenceReviewItemDto>();
        var assets = await dbContext.DomainAssetVersions
            .AsNoTracking()
            .Where(asset => (asset.Status == DomainAssetStatuses.Candidate || asset.Status == DomainAssetStatuses.Reviewed)
                && (asset.AssetType == "curriculum_requirement"
                    || asset.AssetType == "requirement_facet"
                    || asset.AssetType == "error_pattern"
                    || asset.AssetType == "exam_point"))
            .ToArrayAsync(cancellationToken);
        foreach (var asset in assets)
        {
            var candidateType = asset.AssetType switch
            {
                "error_pattern" => "error_pattern",
                "exam_point" => "profile",
                _ => "requirement",
            };
            if (!IsAssetReviewEligible(asset, candidateType))
            {
                continue;
            }

            var metadata = ParseJsonObject(asset.Metadata);
            var reviewStatus = ReadString(metadata, "review_status", "reviewerStatus")
                ?? DomainAssetReviewStatuses.PendingReview;
            var confidence = ReadDecimal(metadata, "confidence", "overall_confidence") ?? 1m;
            var semanticType = ReadString(metadata, "semantic_type", "semanticType");
            var groupId = candidateType switch
            {
                "error_pattern" => "error_patterns",
                "profile" => "regional_profiles",
                _ => "curriculum_requirements",
            };
            var impactLevel = candidateType == "profile"
                && string.Equals(ReadNestedString(metadata, "standard_regime", "regime_type"), "transition", StringComparison.Ordinal)
                    ? "high"
                    : candidateType == "error_pattern" ? "high" : "medium";
            items.Add(new CurriculumEvidenceReviewItemDto(
                candidateType,
                asset.Id,
                asset.StableId,
                groupId,
                reviewStatus,
                confidence,
                impactLevel,
                MappingType: null,
                AlignmentType: null,
                OriginalBasis: false,
                ProductionEligible: false,
                Reversible: true,
                BatchApprovalEligible: false,
                JsonSerializer.SerializeToElement(new
                {
                    asset.DisplayName,
                    asset.AssetType,
                    asset.Status,
                    semanticType,
                }),
                ParseJsonElement(asset.SourceEvidence)));
        }

        var targets = await dbContext.AssessmentTargets.AsNoTracking().ToArrayAsync(cancellationToken);
        var targetIds = targets.Select(target => target.Id).ToArray();
        var questionIds = targets.Select(target => target.QuestionItemId).Distinct().ToArray();
        var targetKnowledgeMappings = await dbContext.AssessmentTargetKnowledgeMappings
            .AsNoTracking()
            .Where(mapping => targetIds.Contains(mapping.AssessmentTargetId) && !mapping.ProductionEligible)
            .ToArrayAsync(cancellationToken);
        var targetKnowledgeAssetIds = targetKnowledgeMappings
            .Select(mapping => mapping.DomainAssetVersionId)
            .Distinct()
            .ToArray();
        var targetKnowledgeAssets = await dbContext.DomainAssetVersions
            .AsNoTracking()
            .Where(asset => targetKnowledgeAssetIds.Contains(asset.Id))
            .ToDictionaryAsync(asset => asset.Id, cancellationToken);
        var targetKnowledgeLookup = targetKnowledgeMappings.ToLookup(mapping => mapping.AssessmentTargetId);
        var questionDifficulties = await dbContext.QuestionItems
            .AsNoTracking()
            .Where(question => questionIds.Contains(question.Id))
            .ToDictionaryAsync(question => question.Id, question => question.DifficultyEstimated, cancellationToken);
        var observedDifficulties = await dbContext.ObservedPerformanceEvidence
            .AsNoTracking()
            .Where(evidence => targetIds.Contains(evidence.AssessmentTargetId)
                && evidence.DifficultyObserved.HasValue
                && !evidence.ProductionEligible)
            .OrderBy(evidence => evidence.StableKey)
            .ToArrayAsync(cancellationToken);
        var observedDifficultyLookup = observedDifficulties.ToLookup(evidence => evidence.AssessmentTargetId);

        object[] ProjectKnowledge(Guid targetId, string role) => targetKnowledgeLookup[targetId]
            .Where(mapping => string.Equals(mapping.Role, role, StringComparison.Ordinal))
            .Select(mapping => targetKnowledgeAssets.GetValueOrDefault(mapping.DomainAssetVersionId) is { } asset
                ? new
                {
                    asset.StableId,
                    asset.DisplayName,
                    mapping.Confidence,
                    mapping.ReviewStatus,
                }
                : null)
            .Where(value => value is not null)
            .Cast<object>()
            .ToArray();

        items.AddRange(targets
            .Where(target => !target.ProductionEligible && AllowedReviewStatuses.Contains(target.ReviewStatus))
            .Select(target => new CurriculumEvidenceReviewItemDto(
            "target",
            target.Id,
            target.StableKey,
            "assessment_targets",
            target.ReviewStatus,
            target.Confidence,
            target.Confidence < 0.85m ? "high" : "medium",
            MappingType: null,
            AlignmentType: null,
            OriginalBasis: false,
            target.ProductionEligible,
            Reversible: true,
            BatchApprovalEligible: false,
            JsonSerializer.SerializeToElement(new
            {
                target.TargetStatement,
                target.ScopeType,
                target.QuestionItemId,
                target.QuestionBlockId,
                target.Status,
                primaryKnowledge = ProjectKnowledge(target.Id, "primary"),
                secondaryKnowledge = ProjectKnowledge(target.Id, "secondary"),
                estimatedDifficulty = questionDifficulties.GetValueOrDefault(target.QuestionItemId),
                observedDifficulty = observedDifficultyLookup[target.Id]
                     .Select(evidence => new
                     {
                         value = evidence.DifficultyObserved,
                         evidence.DifficultyDirection,
                         evidence.SampleScope,
                         evidence.SourceRegionId,
                     })
                     .ToArray(),
            }),
            ParseJsonElement(target.Metadata))));

        var alignments = await dbContext.CurriculumAlignments.AsNoTracking().ToArrayAsync(cancellationToken);
        items.AddRange(alignments
            .Where(alignment => !alignment.ProductionEligible && AllowedReviewStatuses.Contains(alignment.ReviewStatus))
            .Select(alignment => new CurriculumEvidenceReviewItemDto(
            "alignment",
            alignment.Id,
            alignment.StableKey,
            alignment.Confidence < 0.85m ? "low_confidence_mappings" : "retrospective_alignments",
            alignment.ReviewStatus,
            alignment.Confidence,
            alignment.Confidence < 0.85m || !alignment.OriginalBasis ? "high" : "medium",
            MappingType: "retrospective",
            alignment.AlignmentType,
            alignment.OriginalBasis,
            alignment.ProductionEligible,
            Reversible: true,
            BatchApprovalEligible: false,
            JsonSerializer.SerializeToElement(new
            {
                alignment.AssessmentTargetId,
                alignment.CurriculumAssetVersionId,
                alignment.SourceDocumentId,
                alignment.SourceRegionId,
                alignment.StandardVersion,
                alignment.Status,
                retrospective = !alignment.OriginalBasis,
            }),
            ParseJsonElement(alignment.Evidence))));

        var mappings = (await dbContext.DomainAssetMappings.AsNoTracking().ToArrayAsync(cancellationToken))
            .Where(IsMappingReviewEligible)
            .ToArray();
        var mappingAssetIds = mappings
            .SelectMany(mapping => new[] { mapping.SourceAssetVersionId, mapping.TargetAssetVersionId })
            .Distinct()
            .ToArray();
        var mappingAssetKeys = await dbContext.DomainAssetVersions
            .AsNoTracking()
            .Where(asset => mappingAssetIds.Contains(asset.Id))
            .ToDictionaryAsync(asset => asset.Id, asset => asset.StableId, cancellationToken);
        foreach (var mapping in mappings)
        {
            var complex = !string.Equals(mapping.MappingType, DomainAssetMappingTypes.Equivalent, StringComparison.Ordinal);
            var groupId = complex
                ? "complex_mappings"
                : mapping.Confidence < 0.85m ? "low_confidence_mappings" : "low_risk_mappings";
            var impactLevel = complex ? "high" : mapping.Confidence < 0.85m ? "medium" : "low";
            var item = new CurriculumEvidenceReviewItemDto(
                "alignment",
                mapping.Id,
                $"{mappingAssetKeys.GetValueOrDefault(mapping.SourceAssetVersionId, mapping.SourceAssetVersionId.ToString())}->{mappingAssetKeys.GetValueOrDefault(mapping.TargetAssetVersionId, mapping.TargetAssetVersionId.ToString())}",
                groupId,
                mapping.ReviewStatus,
                mapping.Confidence,
                impactLevel,
                mapping.MappingType,
                AlignmentType: null,
                OriginalBasis: false,
                ProductionEligible: false,
                Reversible: true,
                BatchApprovalEligible: false,
                JsonSerializer.SerializeToElement(new
                {
                    mapping.SourceAssetVersionId,
                    mapping.TargetAssetVersionId,
                    mapping.MappingType,
                    mapping.AutoApplied,
                }),
                ParseJsonElement(mapping.Evidence));
            items.Add(item with { BatchApprovalEligible = IsBatchApprovalEligible(item) });
        }

        return items;
    }

    private async Task<CurriculumEvidenceMutation> ApplyCurriculumEvidenceDecisionAsync(
        string candidateType,
        Guid candidateId,
        string decision,
        Guid? replacementAssetVersionId,
        CancellationToken cancellationToken)
    {
        if (candidateType is "requirement" or "profile" or "error_pattern")
        {
            return await ApplyAssetDecisionAsync(candidateType, candidateId, decision, cancellationToken);
        }

        if (candidateType == "target")
        {
            var target = await dbContext.AssessmentTargets.FirstOrDefaultAsync(row => row.Id == candidateId, cancellationToken)
                ?? throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
            if (target.ProductionEligible || !AllowedReviewStatuses.Contains(target.ReviewStatus))
            {
                throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
            }

            var before = JsonSerializer.SerializeToElement(new
            {
                entityKind = "assessment_target",
                status = target.Status,
                reviewStatus = target.ReviewStatus,
                productionEligible = target.ProductionEligible,
                updatedAt = target.UpdatedAt,
            });
            ApplyCandidateState(decision, out var status, out var reviewStatus);
            if (decision != "keep_pending")
            {
                target.Status = status;
                target.ReviewStatus = reviewStatus;
                target.ProductionEligible = false;
                target.UpdatedAt = DateTimeOffset.UtcNow;
            }

            var after = JsonSerializer.SerializeToElement(new
            {
                entityKind = "assessment_target",
                status = target.Status,
                reviewStatus = target.ReviewStatus,
                productionEligible = target.ProductionEligible,
                updatedAt = target.UpdatedAt,
            });
            return new CurriculumEvidenceMutation(before, after, ParseJsonElement(target.Metadata));
        }

        if (candidateType == "alignment")
        {
            var curriculumAlignment = await dbContext.CurriculumAlignments
                .FirstOrDefaultAsync(row => row.Id == candidateId, cancellationToken);
            if (curriculumAlignment is not null)
            {
                if (curriculumAlignment.ProductionEligible
                    || !AllowedReviewStatuses.Contains(curriculumAlignment.ReviewStatus))
                {
                    throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
                }

                var before = JsonSerializer.SerializeToElement(new
                {
                    entityKind = "curriculum_alignment",
                    status = curriculumAlignment.Status,
                    reviewStatus = curriculumAlignment.ReviewStatus,
                    productionEligible = curriculumAlignment.ProductionEligible,
                    curriculumAssetVersionId = curriculumAlignment.CurriculumAssetVersionId,
                });
                if (decision == "change_mapping")
                {
                    var replacementId = replacementAssetVersionId
                        ?? throw new ArgumentException("replacement_asset_version_id_required");
                    var replacement = await dbContext.DomainAssetVersions.AsNoTracking()
                        .FirstOrDefaultAsync(asset => asset.Id == replacementId, cancellationToken);
                    if (replacement is null
                        || replacement.AssetType != "requirement_facet"
                        || !IsAssetReviewEligible(replacement, "requirement"))
                    {
                        throw new KeyNotFoundException("replacement_curriculum_asset_not_found");
                    }

                    curriculumAlignment.CurriculumAssetVersionId = replacementId;
                    curriculumAlignment.Status = "candidate";
                    curriculumAlignment.ReviewStatus = DomainAssetReviewStatuses.PendingReview;
                    curriculumAlignment.ProductionEligible = false;
                }
                else if (decision != "keep_pending")
                {
                    ApplyCandidateState(decision, out var status, out var reviewStatus);
                    curriculumAlignment.Status = status;
                    curriculumAlignment.ReviewStatus = reviewStatus;
                    curriculumAlignment.ProductionEligible = false;
                }

                var after = JsonSerializer.SerializeToElement(new
                {
                    entityKind = "curriculum_alignment",
                    status = curriculumAlignment.Status,
                    reviewStatus = curriculumAlignment.ReviewStatus,
                    productionEligible = curriculumAlignment.ProductionEligible,
                    curriculumAssetVersionId = curriculumAlignment.CurriculumAssetVersionId,
                });
                return new CurriculumEvidenceMutation(before, after, ParseJsonElement(curriculumAlignment.Evidence));
            }

            var mapping = await dbContext.DomainAssetMappings.FirstOrDefaultAsync(row => row.Id == candidateId, cancellationToken)
                ?? throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
            if (!IsMappingReviewEligible(mapping))
            {
                throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
            }

            var mappingBefore = JsonSerializer.SerializeToElement(new
            {
                entityKind = "domain_asset_mapping",
                reviewStatus = mapping.ReviewStatus,
                targetAssetVersionId = mapping.TargetAssetVersionId,
                reviewedAt = NormalizeDatabaseTimestamp(mapping.ReviewedAt),
                autoApplied = mapping.AutoApplied,
            });
            if (decision == "change_mapping")
            {
                var replacementId = replacementAssetVersionId
                    ?? throw new ArgumentException("replacement_asset_version_id_required");
                if (replacementId == mapping.SourceAssetVersionId)
                {
                    throw new InvalidOperationException("mapping_cannot_target_source_asset");
                }

                var targetAssets = await dbContext.DomainAssetVersions.AsNoTracking()
                    .Where(asset => asset.Id == mapping.TargetAssetVersionId || asset.Id == replacementId)
                    .ToArrayAsync(cancellationToken);
                var currentTarget = targetAssets.FirstOrDefault(asset => asset.Id == mapping.TargetAssetVersionId);
                var replacement = targetAssets.FirstOrDefault(asset => asset.Id == replacementId);
                if (currentTarget is null
                    || replacement is null
                    || !IsMappingReplacementEligible(currentTarget, replacement))
                {
                    throw new KeyNotFoundException("replacement_target_asset_not_found");
                }

                mapping.TargetAssetVersionId = replacementId;
                mapping.ReviewStatus = DomainAssetReviewStatuses.PendingReview;
                mapping.ReviewedAt = null;
                mapping.AutoApplied = false;
            }
            else if (decision != "keep_pending")
            {
                mapping.ReviewStatus = decision == "approve"
                    ? DomainAssetReviewStatuses.Approved
                    : DomainAssetReviewStatuses.Rejected;
                mapping.ReviewedAt = DateTimeOffset.UtcNow;
                mapping.AutoApplied = false;
            }

            var mappingAfter = JsonSerializer.SerializeToElement(new
            {
                entityKind = "domain_asset_mapping",
                reviewStatus = mapping.ReviewStatus,
                targetAssetVersionId = mapping.TargetAssetVersionId,
                reviewedAt = NormalizeDatabaseTimestamp(mapping.ReviewedAt),
                autoApplied = mapping.AutoApplied,
            });
            return new CurriculumEvidenceMutation(mappingBefore, mappingAfter, ParseJsonElement(mapping.Evidence));
        }

        throw new ArgumentException("invalid_candidate_type", nameof(candidateType));
    }

    private async Task<CurriculumEvidenceMutation> ApplyAssetDecisionAsync(
        string candidateType,
        Guid candidateId,
        string decision,
        CancellationToken cancellationToken)
    {
        if (decision == "change_mapping")
        {
            throw new ArgumentException("change_mapping_requires_alignment_candidate");
        }

        var expectedAssetTypes = candidateType switch
        {
            "profile" => new[] { "exam_point" },
            "error_pattern" => new[] { "error_pattern" },
            _ => new[] { "curriculum_requirement", "requirement_facet" },
        };
        var asset = await dbContext.DomainAssetVersions.FirstOrDefaultAsync(
            row => row.Id == candidateId && expectedAssetTypes.Contains(row.AssetType),
            cancellationToken) ?? throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
        if (!IsAssetReviewEligible(asset, candidateType))
        {
            throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
        }

        var before = JsonSerializer.SerializeToElement(new
        {
            entityKind = "domain_asset_version",
            status = asset.Status,
            metadata = ParseJsonElement(asset.Metadata),
            updatedAt = asset.UpdatedAt,
        });
        if (decision != "keep_pending")
        {
            var reviewStatus = decision == "approve"
                ? DomainAssetReviewStatuses.Approved
                : DomainAssetReviewStatuses.Rejected;
            asset.Status = decision == "approve" ? DomainAssetStatuses.Reviewed : DomainAssetStatuses.Candidate;
            asset.Metadata = PatchAssetReviewMetadata(asset.Metadata, reviewStatus);
            asset.UpdatedAt = DateTimeOffset.UtcNow;
        }

        var after = JsonSerializer.SerializeToElement(new
        {
            entityKind = "domain_asset_version",
            status = asset.Status,
            metadata = ParseJsonElement(asset.Metadata),
            updatedAt = asset.UpdatedAt,
        });
        return new CurriculumEvidenceMutation(before, after, ParseJsonElement(asset.SourceEvidence));
    }

    private async Task RestoreCurriculumEvidenceSnapshotAsync(
        string candidateType,
        Guid candidateId,
        JsonElement before,
        JsonElement expectedAfter,
        CancellationToken cancellationToken)
    {
        var entityKind = before.GetProperty("entityKind").GetString();
        switch (entityKind)
        {
            case "domain_asset_version":
                {
                    var asset = await dbContext.DomainAssetVersions.FirstOrDefaultAsync(row => row.Id == candidateId, cancellationToken)
                        ?? throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
                    var current = expectedAfter.TryGetProperty("updatedAt", out _)
                        ? JsonSerializer.SerializeToElement(new
                        {
                            entityKind = "domain_asset_version",
                            status = asset.Status,
                            metadata = ParseJsonElement(asset.Metadata),
                            updatedAt = asset.UpdatedAt,
                        })
                        : JsonSerializer.SerializeToElement(new
                        {
                            entityKind = "domain_asset_version",
                            status = asset.Status,
                            metadata = ParseJsonElement(asset.Metadata),
                        });
                    if (ShouldRestoreSnapshot(expectedAfter, before, current))
                    {
                        asset.Status = GetRequiredProperty(before, "status", "Status").GetString()!;
                        asset.Metadata = before.GetProperty("metadata").GetRawText();
                        asset.UpdatedAt = before.TryGetProperty("updatedAt", out var updatedAt)
                            ? updatedAt.GetDateTimeOffset()
                            : asset.UpdatedAt;
                    }
                    break;
                }
            case "assessment_target":
                {
                    var target = await dbContext.AssessmentTargets.FirstOrDefaultAsync(row => row.Id == candidateId, cancellationToken)
                        ?? throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
                    var current = expectedAfter.TryGetProperty("updatedAt", out _)
                        ? JsonSerializer.SerializeToElement(new
                        {
                            entityKind = "assessment_target",
                            status = target.Status,
                            reviewStatus = target.ReviewStatus,
                            productionEligible = target.ProductionEligible,
                            updatedAt = target.UpdatedAt,
                        })
                        : JsonSerializer.SerializeToElement(new
                        {
                            entityKind = "assessment_target",
                            status = target.Status,
                            reviewStatus = target.ReviewStatus,
                            productionEligible = target.ProductionEligible,
                        });
                    if (ShouldRestoreSnapshot(expectedAfter, before, current))
                    {
                        target.Status = GetRequiredProperty(before, "status", "Status").GetString()!;
                        target.ReviewStatus = before.GetProperty("reviewStatus").GetString()!;
                        target.ProductionEligible = GetRequiredProperty(before, "productionEligible", "ProductionEligible").GetBoolean();
                        target.UpdatedAt = before.TryGetProperty("updatedAt", out var updatedAt)
                            ? updatedAt.GetDateTimeOffset()
                            : target.UpdatedAt;
                    }
                    break;
                }
            case "curriculum_alignment":
                {
                    var alignment = await dbContext.CurriculumAlignments.FirstOrDefaultAsync(row => row.Id == candidateId, cancellationToken)
                        ?? throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
                    var current = JsonSerializer.SerializeToElement(new
                    {
                        entityKind = "curriculum_alignment",
                        status = alignment.Status,
                        reviewStatus = alignment.ReviewStatus,
                        productionEligible = alignment.ProductionEligible,
                        curriculumAssetVersionId = alignment.CurriculumAssetVersionId,
                    });
                    if (ShouldRestoreSnapshot(expectedAfter, before, current))
                    {
                        alignment.Status = GetRequiredProperty(before, "status", "Status").GetString()!;
                        alignment.ReviewStatus = before.GetProperty("reviewStatus").GetString()!;
                        alignment.ProductionEligible = GetRequiredProperty(before, "productionEligible", "ProductionEligible").GetBoolean();
                        alignment.CurriculumAssetVersionId = GetRequiredProperty(before, "curriculumAssetVersionId", "CurriculumAssetVersionId").GetGuid();
                    }
                    break;
                }
            case "domain_asset_mapping":
                {
                    var mapping = await dbContext.DomainAssetMappings.FirstOrDefaultAsync(row => row.Id == candidateId, cancellationToken)
                        ?? throw new KeyNotFoundException("curriculum_evidence_candidate_not_found");
                    var current = JsonSerializer.SerializeToElement(new
                    {
                        entityKind = "domain_asset_mapping",
                        reviewStatus = mapping.ReviewStatus,
                        targetAssetVersionId = mapping.TargetAssetVersionId,
                        reviewedAt = NormalizeDatabaseTimestamp(mapping.ReviewedAt),
                        autoApplied = mapping.AutoApplied,
                    });
                    if (ShouldRestoreSnapshot(expectedAfter, before, current))
                    {
                        mapping.ReviewStatus = before.GetProperty("reviewStatus").GetString()!;
                        mapping.TargetAssetVersionId = GetRequiredProperty(before, "targetAssetVersionId", "TargetAssetVersionId").GetGuid();
                        mapping.AutoApplied = GetRequiredProperty(before, "autoApplied", "AutoApplied").GetBoolean();
                        var reviewedAt = GetRequiredProperty(before, "reviewedAt", "ReviewedAt");
                        mapping.ReviewedAt = reviewedAt.ValueKind == JsonValueKind.Null
                            ? null
                            : reviewedAt.GetDateTimeOffset();
                    }
                    break;
                }
            default:
                throw new InvalidOperationException($"unsupported_decision_snapshot:{candidateType}:{entityKind}");
        }
    }

    internal static void ValidateDecisionRequest(CurriculumEvidenceDecisionRequest request)
    {
        ValidateReviewer(request.Reviewer, request.Reason, request.ActorRole);
        if (request.CandidateId == Guid.Empty || string.IsNullOrWhiteSpace(request.CandidateType))
        {
            throw new ArgumentException("candidate_reference_required", nameof(request));
        }

        var decision = request.Decision?.Trim().ToLowerInvariant();
        if (decision is not ("approve" or "return" or "change_mapping" or "keep_pending"))
        {
            throw new ArgumentException("invalid_review_decision", nameof(request));
        }


        var candidateType = request.CandidateType.Trim().ToLowerInvariant();
        if (decision == "change_mapping" && candidateType != "alignment")
        {
            throw new ArgumentException("change_mapping_requires_alignment_candidate", nameof(request));
        }

        if (decision != "change_mapping" && request.ReplacementAssetVersionId.HasValue)
        {
            throw new ArgumentException("replacement_only_allowed_for_change_mapping", nameof(request));
        }
    }

    private static bool ShouldRestoreSnapshot(
        JsonElement expectedAfter,
        JsonElement before,
        JsonElement current)
    {
        if (SnapshotsMatch(expectedAfter, current))
        {
            return true;
        }

        if (SnapshotsMatch(before, current))
        {
            return false;
        }

        throw new InvalidOperationException("decision_state_changed_since_review");
    }

    private static DateTimeOffset? NormalizeDatabaseTimestamp(DateTimeOffset? value)
    {
        if (!value.HasValue)
        {
            return null;
        }

        var normalized = value.Value.ToUniversalTime();
        return new DateTimeOffset(normalized.Ticks - (normalized.Ticks % 10), TimeSpan.Zero);
    }

    private static void ValidateReviewer(string reviewer, string reason, string actorRole)
    {
        if (string.IsNullOrWhiteSpace(reviewer))
        {
            throw new ArgumentException("reviewer_required", nameof(reviewer));
        }

        if (string.IsNullOrWhiteSpace(reason))
        {
            throw new ArgumentException("reason_required", nameof(reason));
        }

        var role = actorRole?.Trim().ToLowerInvariant();
        if (role is not ("teacher" or "group_lead" or "administrator"))
        {
            throw new ArgumentException("invalid_actor_role", nameof(actorRole));
        }
    }

    private static void ApplyCandidateState(string decision, out string status, out string reviewStatus)
    {
        if (decision == "approve")
        {
            status = "reviewed";
            reviewStatus = DomainAssetReviewStatuses.Approved;
            return;
        }

        status = "rejected";
        reviewStatus = DomainAssetReviewStatuses.Rejected;
    }

    internal static CurriculumEvidenceDecisionResponse BuildDecisionResponse(ReviewQueueItem audit)
    {
        var payload = ParseJsonElement(audit.Payload);
        var undo = payload.GetProperty("undo");
        var state = undo.TryGetProperty("restored", out var restored)
            ? restored
            : payload.GetProperty("after");
        var reviewStatus = state.TryGetProperty("reviewStatus", out var value)
            ? value.GetString()
            : state.TryGetProperty("metadata", out var metadata)
                ? ReadString(metadata, "review_status", "reviewerStatus")
                : null;
        return new CurriculumEvidenceDecisionResponse(
            audit.Id,
            payload.GetProperty("candidateType").GetString()!,
            payload.GetProperty("candidateId").GetGuid(),
            payload.GetProperty("decision").GetString()!,
            reviewStatus ?? DomainAssetReviewStatuses.PendingReview,
            ProductionEligible: false,
            ActiveApply: false,
            payload);
    }

    private static CurriculumEvidenceReviewGroupSummary BuildGroupSummary(
        string groupId,
        IReadOnlyList<CurriculumEvidenceReviewItemDto> items)
    {
        var pending = items.Count(item => item.ReviewStatus == DomainAssetReviewStatuses.PendingReview);
        var approved = items.Count(item => item.ReviewStatus == DomainAssetReviewStatuses.Approved);
        var rejected = items.Count(item => item.ReviewStatus == DomainAssetReviewStatuses.Rejected);
        return new CurriculumEvidenceReviewGroupSummary(
            groupId,
            pending > 0 ? DomainAssetReviewStatuses.PendingReview : "reviewed",
            pending,
            approved,
            rejected,
            items.Count,
            groupId switch
            {
                "complex_mappings" => "Split, merge, broader, or narrower mappings require an individual reason.",
                "low_confidence_mappings" => "Confidence below the review threshold requires individual inspection.",
                "regional_profiles" => "Regional profiles require teacher review, especially across standard regimes.",
                _ => "Candidate evidence remains isolated from active C002 until separately governed.",
            });
    }

    private static int ImpactRank(string impactLevel) => impactLevel switch
    {
        "high" => 3,
        "medium" => 2,
        "low" => 1,
        _ => 0,
    };

    private static JsonElement ParseJsonElement(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(string.IsNullOrWhiteSpace(json) ? "{}" : json);
            return document.RootElement.Clone();
        }
        catch (JsonException)
        {
            return JsonSerializer.SerializeToElement(new { });
        }
    }

    private static JsonElement ParseJsonObject(string json)
    {
        var element = ParseJsonElement(json);
        return element.ValueKind == JsonValueKind.Object ? element : JsonSerializer.SerializeToElement(new { });
    }

    private static string? ReadString(JsonElement element, params string[] propertyNames)
    {
        foreach (var propertyName in propertyNames)
        {
            if (element.ValueKind == JsonValueKind.Object
                && element.TryGetProperty(propertyName, out var value)
                && value.ValueKind == JsonValueKind.String)
            {
                return value.GetString();
            }
        }

        return null;
    }

    private static IReadOnlyList<string> ReadStringArray(JsonElement element, string propertyName)
    {
        if (element.ValueKind != JsonValueKind.Object
            || !element.TryGetProperty(propertyName, out var value)
            || value.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        return value.EnumerateArray()
            .Where(item => item.ValueKind == JsonValueKind.String)
            .Select(item => item.GetString()?.Trim())
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .Select(item => item!)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }

    private static IReadOnlyList<Guid> ReadGuidArray(JsonElement element, string propertyName) =>
        ReadStringArray(element, propertyName)
            .Select(value => Guid.TryParse(value, out var id) ? id : (Guid?)null)
            .Where(value => value.HasValue)
            .Select(value => value!.Value)
            .Distinct()
            .ToArray();

    private static int? ReadInt(JsonElement element, string propertyName)
    {
        if (element.ValueKind != JsonValueKind.Object
            || !element.TryGetProperty(propertyName, out var value))
        {
            return null;
        }

        return value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var number)
            ? number
            : null;
    }

    private static string BuildStringArrayJsonFilter(string propertyName, string value) =>
        JsonSerializer.Serialize(new Dictionary<string, string[]>
        {
            [propertyName] = [value.Trim()],
        });

    private static string BuildStringJsonFilter(string propertyName, string value) =>
        JsonSerializer.Serialize(new Dictionary<string, string>
        {
            [propertyName] = value.Trim(),
        });

    private static decimal? ReadDecimal(JsonElement element, params string[] propertyNames)
    {
        foreach (var propertyName in propertyNames)
        {
            if (element.ValueKind == JsonValueKind.Object
                && element.TryGetProperty(propertyName, out var value)
                && value.TryGetDecimal(out var number))
            {
                return number;
            }
        }

        return null;
    }

    private static bool? ReadBoolean(JsonElement element, params string[] propertyNames)
    {
        foreach (var propertyName in propertyNames)
        {
            if (element.ValueKind != JsonValueKind.Object
                || !element.TryGetProperty(propertyName, out var value))
            {
                continue;
            }

            if (value.ValueKind == JsonValueKind.True)
            {
                return true;
            }

            if (value.ValueKind == JsonValueKind.False)
            {
                return false;
            }
        }

        return null;
    }

    private static string? ReadNestedString(JsonElement element, string objectName, string propertyName)
    {
        if (element.ValueKind != JsonValueKind.Object
            || !element.TryGetProperty(objectName, out var nested))
        {
            return null;
        }

        return ReadString(nested, propertyName);
    }

    private static bool HasImportKey(string json, string expected)
    {
        var element = ParseJsonElement(json);
        return string.Equals(ReadString(element, "importKey"), expected, StringComparison.Ordinal);
    }

    private static string PatchAssetReviewMetadata(string json, string reviewStatus)
    {
        var metadata = JsonNode.Parse(string.IsNullOrWhiteSpace(json) ? "{}" : json) as JsonObject
            ?? new JsonObject();
        metadata["review_status"] = reviewStatus;
        metadata["reviewerStatus"] = reviewStatus;
        metadata["production_eligible"] = false;
        metadata["productionEligible"] = false;
        return metadata.ToJsonString();
    }

    private static JsonElement GetRequiredProperty(
        JsonElement element,
        string preferredName,
        string legacyName)
    {
        if (element.TryGetProperty(preferredName, out var value)
            || element.TryGetProperty(legacyName, out value))
        {
            return value;
        }

        throw new InvalidOperationException($"decision_snapshot_property_missing:{preferredName}");
    }

    private static JsonNode? CanonicalizeSnapshotNode(JsonNode? node, string? propertyName = null)
    {
        if (node is JsonObject sourceObject)
        {
            var normalized = new JsonObject();
            foreach (var property in sourceObject)
            {
                var name = property.Key switch
                {
                    "EntityKind" => "entityKind",
                    "Status" => "status",
                    "ReviewStatus" => "reviewStatus",
                    "ProductionEligible" => "productionEligible",
                    "CurriculumAssetVersionId" => "curriculumAssetVersionId",
                    "TargetAssetVersionId" => "targetAssetVersionId",
                    "ReviewedAt" => "reviewedAt",
                    "UpdatedAt" => "updatedAt",
                    "AutoApplied" => "autoApplied",
                    _ => property.Key,
                };

                // reviewedAt is audit/restoration data, not a concurrency token.
                if (name == "reviewedAt")
                {
                    continue;
                }

                normalized[name] = CanonicalizeSnapshotNode(property.Value, name);
            }

            return normalized;
        }

        if (node is JsonArray sourceArray)
        {
            var normalized = new JsonArray();
            foreach (var value in sourceArray)
            {
                normalized.Add(CanonicalizeSnapshotNode(value));
            }

            return normalized;
        }

        if (node is JsonValue valueNode
            && propertyName is "reviewedAt" or "updatedAt"
            && valueNode.TryGetValue<string>(out var timestamp)
            && DateTimeOffset.TryParse(timestamp, out var parsed))
        {
            var utcTicks = parsed.ToUniversalTime().Ticks;
            var microsecondTicks = utcTicks - (utcTicks % 10);
            return JsonValue.Create(new DateTimeOffset(microsecondTicks, TimeSpan.Zero).ToString("O"));
        }

        return node?.DeepClone();
    }

    private sealed record CurriculumEvidenceMutation(
        JsonElement Before,
        JsonElement After,
        JsonElement Evidence);
}

internal sealed record ErrorPatternEvidenceInput(
    Guid EvidenceId,
    Guid AssessmentTargetId,
    Guid QuestionItemId,
    int ExamYear,
    string PatternCode);

internal sealed record ErrorPatternTaxonomyEntry(
    string Code,
    string DisplayName,
    string SemanticType,
    bool MisconceptionEligible);

internal sealed record MisconceptionPromotionDecision(
    string Status,
    string? TargetKnowledgeType,
    bool RequiresHumanReview,
    bool RequiresC002RImpactReport,
    bool RequiresRollbackSnapshot,
    bool AutoApplyAllowed);

internal sealed record ErrorPatternCandidate(
    DomainAssetVersion Asset,
    int EvidenceCount,
    int DistinctQuestionCount,
    int DistinctExamYearCount,
    IReadOnlyList<Guid> EvidenceTargetIds,
    string NormalizationMethod,
    string ReviewerStatus,
    bool ProductionEligible,
    string StabilityBasis,
    MisconceptionPromotionDecision Promotion);
