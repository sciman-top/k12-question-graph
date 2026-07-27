using System.Text.Json;
using K12QuestionGraph.Api.Domain;
using K12QuestionGraph.Api.Infrastructure.Json;

namespace K12QuestionGraph.Api.Questions;

public sealed record QuestionCreateRequest(
    string Subject,
    string Stage,
    string? Grade,
    string? QuestionType,
    decimal? DefaultScore,
    double? DifficultyEstimated,
    string? Status,
    Guid? PrimaryKnowledgeId,
    IReadOnlyList<QuestionBlockCreateRequest> Blocks,
    IReadOnlyList<QuestionAssetCreateRequest> Assets,
    JsonElement? Answer,
    JsonElement? Solution);

public sealed record QuestionBlockCreateRequest(
    string BlockType,
    int? SortOrder,
    JsonElement Content,
    Guid? SourceRegionId);

public sealed record QuestionUpdateRequest(
    string? QuestionType,
    decimal? DefaultScore,
    double? DifficultyEstimated,
    string? Status,
    Guid? PrimaryKnowledgeId,
    bool? ClearPrimaryKnowledge,
    IReadOnlyList<QuestionBlockUpdateRequest>? Blocks,
    JsonElement? Answer,
    JsonElement? Solution,
    string? PrimaryKnowledgeLabel,
    IReadOnlyList<string>? KnowledgeTags,
    string ReviewedBy,
    string Reason);

public sealed record QuestionBlockUpdateRequest(
    Guid? Id,
    string? BlockType,
    int? SortOrder,
    JsonElement? Content,
    Guid? SourceRegionId);

public sealed record QuestionAssetCreateRequest(
    Guid? FileAssetId,
    Guid? SourceRegionId,
    string AssetType,
    string? Purpose,
    JsonElement Metadata);

public sealed record QuestionAssetAssociationRequest(
    Guid? FileAssetId,
    Guid SourceRegionId,
    string? AssetType,
    string? Purpose,
    JsonElement Metadata,
    string ReviewedBy,
    string Reason);

public sealed record QuestionResponse(
    Guid Id,
    string Subject,
    string Stage,
    string? Grade,
    string? QuestionType,
    decimal? DefaultScore,
    double? DifficultyEstimated,
    Guid? PrimaryKnowledgeId,
    int? QuestionNo,
    string Status,
    IReadOnlyList<QuestionBlockResponse> Blocks,
    IReadOnlyList<QuestionAssetResponse> Assets,
    JsonElement CustomFields)
{
    public static QuestionResponse From(QuestionItem item, IReadOnlyList<QuestionBlock> blocks, IReadOnlyList<QuestionAsset> assets)
    {
        return new QuestionResponse(
            item.Id,
            item.Subject,
            item.Stage,
            item.Grade,
            item.QuestionType,
            item.DefaultScore,
            item.DifficultyEstimated,
            item.PrimaryKnowledgeId,
            QuestionCustomFieldHelpers.TryGetIntField(item.CustomFields, "questionNo"),
            item.Status,
            blocks.Select(QuestionBlockResponse.From).ToArray(),
            assets.Select(QuestionAssetResponse.From).ToArray(),
            JsonHelpers.ParseJsonElement(item.CustomFields));
    }
}

public sealed record QuestionRevisionResponse(QuestionResponse Question, Guid AuditId);

public sealed record QuestionBlockResponse(
    Guid Id,
    Guid QuestionItemId,
    string BlockType,
    int SortOrder,
    JsonElement Content,
    Guid? SourceRegionId)
{
    public static QuestionBlockResponse From(QuestionBlock block)
    {
        return new QuestionBlockResponse(
            block.Id,
            block.QuestionItemId,
            block.BlockType,
            block.SortOrder,
            JsonHelpers.ParseJsonElement(block.Content),
            block.SourceRegionId);
    }
}

public sealed record QuestionAssetResponse(
    Guid Id,
    Guid QuestionItemId,
    Guid? FileAssetId,
    Guid? SourceRegionId,
    string? SourceRegionScreenshotUrl,
    string? SourceRegionPageScreenshotUrl,
    string AssetType,
    string Purpose,
    JsonElement Metadata)
{
    public static QuestionAssetResponse From(QuestionAsset asset)
    {
        var sourceRegionScreenshotUrl = asset.SourceRegionId.HasValue
            ? $"/source-regions/{asset.SourceRegionId.Value}/screenshot"
            : null;
        var sourceRegionPageScreenshotUrl = asset.SourceRegionId.HasValue
            ? $"/source-regions/{asset.SourceRegionId.Value}/page-screenshot"
            : null;

        return new QuestionAssetResponse(
            asset.Id,
            asset.QuestionItemId,
            asset.FileAssetId,
            asset.SourceRegionId,
            sourceRegionScreenshotUrl,
            sourceRegionPageScreenshotUrl,
            asset.AssetType,
            asset.Purpose,
            JsonHelpers.ParseJsonElement(asset.Metadata));
    }
}

public sealed record QuestionAssetRevisionResponse(QuestionAssetResponse Asset, Guid AuditId);

public sealed record QuestionAssetUnlinkResponse(Guid QuestionItemId, Guid AssetId, Guid? SourceRegionId, Guid AuditId);

public sealed record QuestionSourceReviewResponse(Guid QuestionItemId, IReadOnlyList<QuestionSourceRegionResponse> SourceRegions);

public sealed record QuestionSearchResponse(
    string Mode,
    bool ProductionEligible,
    int Total,
    int Page,
    int Limit,
    string KnowledgeStatus,
    int? KnowledgeVersion,
    IReadOnlyList<QuestionCardResponse> Items);

public sealed record QuestionCardResponse(
    Guid Id,
    string Subject,
    string Stage,
    string? Grade,
    string? QuestionType,
    decimal? DefaultScore,
    double? DifficultyEstimated,
    string Status,
    int? QuestionNo,
    KnowledgeNodeCardResponse? PrimaryKnowledge,
    string Preview,
    int BlockCount,
    int AssetCount,
    SourceSummaryResponse Sources,
    bool HasFormula,
    bool HasTable,
    bool HasImage);

public sealed record KnowledgeNodeCardResponse(
    Guid Id,
    string Code,
    string Title,
    int Level,
    string Status,
    int Version)
{
    public static KnowledgeNodeCardResponse From(KnowledgeNode node)
    {
        return new KnowledgeNodeCardResponse(
            node.Id,
            node.Code,
            node.Title,
            node.Level,
            node.Status,
            node.Version);
    }
}

public sealed record SourceSummaryResponse(
    IReadOnlyList<string> Titles,
    IReadOnlyList<string> Types,
    IReadOnlyList<string> Permissions,
    bool SharingAllowed,
    bool ContainsStudentPii,
    IReadOnlyList<string> AnonymizationStatuses,
    int RegionCount,
    int ScreenshotCount);

public sealed record QuestionSourceRegionResponse(
    Guid Id,
    Guid SourceDocumentId,
    string? SourceTitle,
    int PageNumber,
    decimal X,
    decimal Y,
    decimal Width,
    decimal Height,
    string CoordinateUnit,
    string? ScreenshotRelativePath,
    string? ScreenshotUrl,
    string PageScreenshotUrl,
    string RegionType)
{
    public static QuestionSourceRegionResponse From(SourceRegion region, SourceDocument? document)
    {
        var screenshotUrl = string.IsNullOrWhiteSpace(region.ScreenshotRelativePath)
            ? null
            : $"/source-regions/{region.Id}/screenshot";
        return new QuestionSourceRegionResponse(
            region.Id,
            region.SourceDocumentId,
            document?.SourceTitle,
            region.PageNumber,
            region.X,
            region.Y,
            region.Width,
            region.Height,
            region.CoordinateUnit,
            region.ScreenshotRelativePath,
            screenshotUrl,
            $"/source-regions/{region.Id}/page-screenshot",
            region.RegionType);
    }
}
