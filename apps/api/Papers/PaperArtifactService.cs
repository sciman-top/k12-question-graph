using System.IO.Compression;
using System.Text;
using System.Text.Json;
using K12QuestionGraph.Api.Application.Workflows;
using K12QuestionGraph.Api.Data;
using K12QuestionGraph.Api.Domain;
using Microsoft.EntityFrameworkCore;

namespace K12QuestionGraph.Api.Papers;

public sealed class PaperArtifactService
{
    private readonly KqgDbContext dbContext;
    private readonly IPaperWorkflowService workflowService;

    public PaperArtifactService(KqgDbContext dbContext, IPaperWorkflowService workflowService)
    {
        this.dbContext = dbContext;
        this.workflowService = workflowService;
    }

    public async Task<PaperArtifactResult?> GenerateAsync(
        Guid basketId,
        string format,
        string variant,
        CancellationToken cancellationToken)
    {
        var normalizedFormat = Normalize(format, "docx");
        if (normalizedFormat is not ("docx" or "pdf"))
        {
            return PaperArtifactResult.Blocked("unsupported_export_format", "仅支持 Word 或 PDF 导出。", normalizedFormat);
        }

        var preflight = await workflowService.RunExportPreflightAsync(basketId, normalizedFormat, cancellationToken);
        if (preflight is null)
        {
            return null;
        }

        if (string.Equals(preflight.Status, "blocked", StringComparison.OrdinalIgnoreCase))
        {
            return PaperArtifactResult.Blocked("preflight_blocked", preflight.TeacherMessage, normalizedFormat);
        }

        var basket = await dbContext.PaperBaskets.AsNoTracking().FirstAsync(x => x.Id == basketId, cancellationToken);
        var items = await dbContext.PaperBasketItems.AsNoTracking().Where(x => x.PaperBasketId == basketId).OrderBy(x => x.SortOrder).ToListAsync(cancellationToken);
        var questionIds = items.Select(x => x.QuestionItemId).ToArray();
        var questions = await dbContext.QuestionItems.AsNoTracking().Where(x => questionIds.Contains(x.Id)).ToDictionaryAsync(x => x.Id, cancellationToken);
        var blocks = await dbContext.QuestionBlocks.AsNoTracking().Where(x => questionIds.Contains(x.QuestionItemId)).OrderBy(x => x.SortOrder).ToListAsync(cancellationToken);
        var lines = items.Select(item =>
        {
            questions.TryGetValue(item.QuestionItemId, out var question);
            var preview = blocks.Where(x => x.QuestionItemId == item.QuestionItemId).Select(Preview).FirstOrDefault() ?? "题干待教师复核";
            return (No: item.QuestionNo, Score: item.Score, Text: preview, Answer: variant.Equals("student", StringComparison.OrdinalIgnoreCase) ? null : ReadCustom(question?.CustomFields, "answer"));
        }).ToArray();

        var fileName = $"{SanitizeFileName(basket.Title)}-{(variant.Equals("student", StringComparison.OrdinalIgnoreCase) ? "学生版" : "教师版")}.{normalizedFormat}";
        var docxBytes = BuildDocx(basket.Title, lines);
        byte[] bytes;
        if (normalizedFormat == "docx")
        {
            bytes = docxBytes;
        }
        else
        {
            try
            {
                bytes = await ConvertDocxToPdfAsync(docxBytes, cancellationToken);
            }
            catch (PaperArtifactGenerationException ex)
            {
                return PaperArtifactResult.Blocked(ex.Code, ex.Message, normalizedFormat);
            }
        }
        return new PaperArtifactResult("ready", normalizedFormat, fileName, bytes, null, "试卷工件已生成，可下载并继续人工复核。", ["export_preflight_passed", "generated_non_production_artifact", "student_variant_omits_answers"]);
    }

    internal static byte[] BuildDocx(string title, IReadOnlyList<(int No, decimal Score, string Text, string? Answer)> lines)
    {
        static string Xml(string value) => System.Security.SecurityElement.Escape(value) ?? string.Empty;
        var body = new StringBuilder();
        body.Append($"<w:p><w:r><w:t>{Xml(title)}</w:t></w:r></w:p>");
        foreach (var line in lines)
        {
            body.Append($"<w:p><w:r><w:t>{line.No}. {Xml(line.Text)}（{line.Score:0.##}分）</w:t></w:r></w:p>");
            if (line.Answer is not null) body.Append($"<w:p><w:r><w:t>答案：{Xml(line.Answer)}</w:t></w:r></w:p>");
        }
        var document = $"<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>{body}<w:sectPr/></w:body></w:document>";
        using var output = new MemoryStream();
        using (var zip = new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: true))
        {
            Add(zip, "[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>");
            Add(zip, "_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>");
            Add(zip, "word/document.xml", document);
        }
        return output.ToArray();
    }

    internal static async Task<byte[]> ConvertDocxToPdfAsync(byte[] docxBytes, CancellationToken cancellationToken)
    {
        var converter = ResolveLibreOffice();
        if (converter is null)
        {
            throw new PaperArtifactGenerationException("pdf_converter_unavailable", "当前主机未安装 LibreOffice，PDF 导出已阻断；Word 仍可下载。");
        }

        var tempDirectory = Path.Combine(Path.GetTempPath(), $"kqg-paper-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempDirectory);
        var inputPath = Path.Combine(tempDirectory, "paper.docx");
        var outputPath = Path.Combine(tempDirectory, "paper.pdf");
        try
        {
            await File.WriteAllBytesAsync(inputPath, docxBytes, cancellationToken);
            var startInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = converter,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            startInfo.ArgumentList.Add("--headless");
            startInfo.ArgumentList.Add("--convert-to");
            startInfo.ArgumentList.Add("pdf");
            startInfo.ArgumentList.Add("--outdir");
            startInfo.ArgumentList.Add(tempDirectory);
            startInfo.ArgumentList.Add(inputPath);
            using var process = System.Diagnostics.Process.Start(startInfo)
                ?? throw new PaperArtifactGenerationException("pdf_converter_start_failed", "无法启动 PDF 转换器，PDF 导出已阻断。");
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(30));
            try
            {
                await process.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                process.Kill(entireProcessTree: true);
                throw new PaperArtifactGenerationException("pdf_converter_timeout", "PDF 转换超过 30 秒，已安全终止。");
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }

                throw;
            }

            if (process.ExitCode != 0 || !File.Exists(outputPath))
            {
                throw new PaperArtifactGenerationException("pdf_converter_failed", "LibreOffice 未能生成 PDF，已保留 Word 导出路径。");
            }

            return await File.ReadAllBytesAsync(outputPath, cancellationToken);
        }
        finally
        {
            try { Directory.Delete(tempDirectory, recursive: true); } catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        }
    }

    private static void Add(ZipArchive zip, string name, string content) { using var writer = new StreamWriter(zip.CreateEntry(name).Open(), new UTF8Encoding(false)); writer.Write(content); }
    private static string Preview(QuestionBlock block) => ReadCustom(block.Content, "text") ?? ReadCustom(block.Content, "answer") ?? block.Content;
    private static string? ReadCustom(string? json, string key)
    {
        if (string.IsNullOrWhiteSpace(json)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty(key, out var value)) return null;
            if (value.ValueKind == JsonValueKind.String) return value.GetString();
            if (value.ValueKind == JsonValueKind.Object)
            {
                foreach (var nestedKey in new[] { "value", "text", "answer" })
                {
                    if (value.TryGetProperty(nestedKey, out var nested) && nested.ValueKind == JsonValueKind.String) return nested.GetString();
                }
            }
            return value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined ? null : value.ToString();
        }
        catch (JsonException) { return null; }
    }
    private static string Normalize(string? value, string fallback) => string.IsNullOrWhiteSpace(value) ? fallback : value.Trim().ToLowerInvariant();
    private static string SanitizeFileName(string value) => string.Join("", value.Select(ch => Path.GetInvalidFileNameChars().Contains(ch) ? '_' : ch));
    private static string? ResolveLibreOffice()
    {
        var candidates = new[]
        {
            Environment.GetEnvironmentVariable("KQG_SOFFICE_PATH"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "LibreOffice", "program", "soffice.com"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "LibreOffice", "program", "soffice.exe")
        };
        return candidates.FirstOrDefault(path => !string.IsNullOrWhiteSpace(path) && File.Exists(path));
    }
}

public sealed class PaperArtifactGenerationException : Exception
{
    public PaperArtifactGenerationException(string code, string message) : base(message) => Code = code;
    public string Code { get; }
}

public sealed record PaperArtifactResult(string Status, string Format, string? FileName, byte[]? Bytes, string? ErrorCode, string TeacherMessage, IReadOnlyList<string> AuditTrail)
{
    public static PaperArtifactResult Blocked(string code, string message, string format) => new("blocked", format, null, null, code, message, ["export_blocked", "no_partial_artifact"]);
}
