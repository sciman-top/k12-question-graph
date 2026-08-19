using System.Globalization;
using System.Text.RegularExpressions;
using ClosedXML.Excel;
using K12QuestionGraph.Api.Application.Workflows;

namespace K12QuestionGraph.Api.Scores;

public sealed class ScoreSpreadsheetImportAdapter
{
    private static readonly Regex ItemHeader = new(
        "^(?:q|question|第)?\\s*(?<number>\\d+)(?:题)?(?:[_\\s-]*(?:score|得分))?(?:\\s*[\\(（]\\s*(?<max>\\d+(?:\\.\\d+)?)\\s*分?\\s*[\\)）])?$",
        RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    public async Task<ScoreImportServiceRequest> ParseAsync(
        Stream workbookStream,
        string fileName,
        bool containsStudentPii,
        CancellationToken cancellationToken)
    {
        if (workbookStream.Length > 8 * 1024 * 1024)
        {
            throw new ScoreSpreadsheetImportException("file_too_large", "成绩表超过 8 MB，已阻断导入。", 413);
        }

        await using var buffer = new MemoryStream();
        await workbookStream.CopyToAsync(buffer, cancellationToken);
        buffer.Position = 0;
        XLWorkbook workbook;
        try
        {
            workbook = new XLWorkbook(buffer);
        }
        catch (Exception ex) when (ex is ArgumentException or InvalidDataException or IOException or FileFormatException)
        {
            throw new ScoreSpreadsheetImportException("xlsx_invalid", "无法读取 Excel 文件，请确认文件未损坏且包含成绩工作表。", 400, ex);
        }

        using (workbook)
        {
            var worksheet = workbook.Worksheets.FirstOrDefault();
            if (worksheet is null)
            {
                throw new ScoreSpreadsheetImportException("worksheet_missing", "Excel 中没有可读取的工作表。", 400);
            }

            var used = worksheet.RangeUsed();
            if (used is null || used.RowCount() < 2)
            {
                throw new ScoreSpreadsheetImportException("rows_required", "Excel 至少需要一行表头和一行成绩。", 400);
            }

            var headerRow = used.FirstRow();
            var headers = headerRow.CellsUsed()
                .Select(cell => (Column: cell.Address.ColumnNumber, Name: cell.GetString().Trim()))
                .Where(x => !string.IsNullOrWhiteSpace(x.Name))
                .ToArray();
            var studentHeader = headers.FirstOrDefault(x => IsStudentHeader(x.Name));
            var totalHeader = headers.FirstOrDefault(x => IsTotalHeader(x.Name));
            if (studentHeader.Column == 0 || totalHeader.Column == 0)
            {
                throw new ScoreSpreadsheetImportException("required_headers_missing", "Excel 必须包含 student_code/学号 和 total_score/总分字段。", 400);
            }

            var itemHeaders = headers
                .Select(x => (x.Column, Match: ItemHeader.Match(x.Name), x.Name))
                .Where(x => x.Match.Success)
                .Select(x =>
                {
                    var questionNo = $"Q{int.Parse(x.Match.Groups["number"].Value, CultureInfo.InvariantCulture)}";
                    var maxText = x.Match.Groups["max"].Value;
                    var maxScore = decimal.TryParse(maxText, NumberStyles.Number, CultureInfo.InvariantCulture, out var parsed)
                        ? parsed
                        : 0m;
                    return (x.Column, QuestionNo: questionNo, FieldName: x.Name, MaxScore: maxScore);
                })
                .GroupBy(x => x.QuestionNo, StringComparer.OrdinalIgnoreCase)
                .Select(group => group.First())
                .OrderBy(x => int.Parse(x.QuestionNo[1..], CultureInfo.InvariantCulture))
                .ToArray();
            if (itemHeaders.Length == 0 || itemHeaders.Any(x => x.MaxScore <= 0))
            {
                throw new ScoreSpreadsheetImportException("item_max_score_required", "每个小题表头必须声明满分，例如 Q1(5分) 或 第1题(5分)。", 400);
            }

            var rows = new List<ScoreImportRowRequest>();
            foreach (var row in used.RowsUsed().Skip(1))
            {
                var values = headers.ToDictionary(
                    x => x.Name,
                    x => CellValue(row.Cell(x.Column)),
                    StringComparer.OrdinalIgnoreCase);
                if (values.Values.All(string.IsNullOrWhiteSpace))
                {
                    continue;
                }

                rows.Add(new ScoreImportRowRequest(row.RowNumber(), values));
            }

            if (rows.Count == 0)
            {
                throw new ScoreSpreadsheetImportException("rows_required", "Excel 中没有可导入的成绩行。", 400);
            }

            var assessmentKey = $"xlsx-score-{DateTimeOffset.UtcNow:yyyyMMddHHmmss}-{Guid.NewGuid():N}";
            return new ScoreImportServiceRequest(
                assessmentKey,
                Path.GetFileNameWithoutExtension(fileName),
                "physics",
                "junior_middle_school",
                "",
                "xlsx-auto-template-v1",
                "Excel 自动识别模板",
                Path.GetFileName(fileName),
                containsStudentPii,
                false,
                itemHeaders.Sum(x => x.MaxScore),
                new ScoreImportFieldMapping(
                    studentHeader.Name,
                    totalHeader.Name,
                    itemHeaders.ToDictionary(x => x.QuestionNo, x => x.FieldName, StringComparer.OrdinalIgnoreCase)),
                itemHeaders.ToDictionary(x => x.QuestionNo, x => x.MaxScore, StringComparer.OrdinalIgnoreCase),
                rows);
        }
    }

    private static bool IsStudentHeader(string header) => Normalize(header) is "studentcode" or "studentkey" or "学号" or "学生编号";

    private static bool IsTotalHeader(string header) => Normalize(header) is "totalscore" or "总分" or "总成绩";

    private static string Normalize(string value) =>
        value.Trim().Replace("_", string.Empty, StringComparison.Ordinal)
            .Replace("-", string.Empty, StringComparison.Ordinal)
            .Replace(" ", string.Empty, StringComparison.Ordinal)
            .ToLowerInvariant();

    private static string CellValue(IXLCell cell) => cell.DataType == XLDataType.Number
        ? cell.GetDouble().ToString(CultureInfo.InvariantCulture)
        : cell.GetString().Trim();
}

public sealed class ScoreSpreadsheetImportException : Exception
{
    public ScoreSpreadsheetImportException(string code, string message, int statusCode, Exception? innerException = null)
        : base(message, innerException)
    {
        Code = code;
        StatusCode = statusCode;
    }

    public string Code { get; }

    public int StatusCode { get; }
}
