using System.IO.Compression;

namespace K12QuestionGraph.Api.FileStore;

internal sealed record UploadStorageIdentity(
    string OriginalFileName,
    string ContentType,
    string StorageExtension);

internal sealed class UnsupportedUploadTypeException(string code) : IOException(code)
{
    public string Code { get; } = code;
}

internal static class UploadStoragePolicy
{
    public const long MaxUploadBytes = 128L * 1024 * 1024;

    private const int MaxOriginalFileNameLength = 260;
    private const int MaxContentTypeLength = 128;

    private static readonly IReadOnlyDictionary<string, AllowedUploadType> AllowedTypes =
        new Dictionary<string, AllowedUploadType>(StringComparer.OrdinalIgnoreCase)
        {
            [".pdf"] = new("application/pdf", ["application/pdf"]),
            [".docx"] = new(
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                ["application/vnd.openxmlformats-officedocument.wordprocessingml.document"]),
            [".png"] = new("image/png", ["image/png"]),
            [".jpg"] = new("image/jpeg", ["image/jpeg"]),
            [".jpeg"] = new("image/jpeg", ["image/jpeg"]),
            [".bmp"] = new("image/bmp", ["image/bmp", "image/x-ms-bmp"]),
            [".tif"] = new("image/tiff", ["image/tiff"]),
            [".tiff"] = new("image/tiff", ["image/tiff"])
        };

    public static void ValidateDeclaredLength(long sizeBytes)
    {
        if (sizeBytes <= 0)
        {
            throw new InvalidDataException("Upload stream must not be empty.");
        }

        if (sizeBytes > MaxUploadBytes)
        {
            throw new InvalidDataException($"Upload stream exceeds the {MaxUploadBytes} byte limit.");
        }
    }

    public static UploadStorageIdentity Normalize(string? originalFileName, string? contentType)
    {
        var fileName = RemoveControlCharacters(Path.GetFileName(originalFileName ?? string.Empty)).Trim();
        if (string.IsNullOrWhiteSpace(fileName))
        {
            throw new UnsupportedUploadTypeException("upload_file_name_required");
        }

        var extension = Path.GetExtension(fileName).ToLowerInvariant();
        if (!AllowedTypes.TryGetValue(extension, out var allowedType))
        {
            throw new UnsupportedUploadTypeException("unsupported_upload_extension");
        }

        var normalizedContentType = NormalizeContentType(contentType);
        if (normalizedContentType.Length > MaxContentTypeLength ||
            !allowedType.AcceptedContentTypes.Contains(normalizedContentType, StringComparer.OrdinalIgnoreCase))
        {
            throw new UnsupportedUploadTypeException("upload_content_type_mismatch");
        }

        return new UploadStorageIdentity(
            TruncateValidUtf16(fileName, MaxOriginalFileNameLength),
            allowedType.CanonicalContentType,
            extension);
    }

    public static void ValidateContent(string path, UploadStorageIdentity identity)
    {
        try
        {
            switch (identity.StorageExtension)
            {
                case ".pdf":
                    ValidatePrefix(path, "%PDF-"u8, "upload_signature_mismatch");
                    break;
                case ".docx":
                    ValidateDocx(path);
                    break;
                case ".png":
                    ValidatePrefix(path, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "upload_signature_mismatch");
                    break;
                case ".jpg":
                case ".jpeg":
                    ValidatePrefix(path, [0xFF, 0xD8, 0xFF], "upload_signature_mismatch");
                    break;
                case ".bmp":
                    ValidatePrefix(path, "BM"u8, "upload_signature_mismatch");
                    break;
                case ".tif":
                case ".tiff":
                    ValidateTiff(path);
                    break;
                default:
                    throw new UnsupportedUploadTypeException("unsupported_upload_extension");
            }
        }
        catch (UnsupportedUploadTypeException)
        {
            throw;
        }
        catch (InvalidDataException)
        {
            throw new UnsupportedUploadTypeException("upload_container_invalid");
        }
    }

    private static void ValidateDocx(string path)
    {
        using var archive = ZipFile.OpenRead(path);
        var entryNames = archive.Entries.Select(entry => entry.FullName).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (!entryNames.Contains("[Content_Types].xml") ||
            !entryNames.Contains("_rels/.rels") ||
            !entryNames.Contains("word/document.xml"))
        {
            throw new UnsupportedUploadTypeException("docx_structure_invalid");
        }
    }

    private static void ValidateTiff(string path)
    {
        Span<byte> header = stackalloc byte[4];
        using var stream = File.OpenRead(path);
        if (stream.Read(header) != header.Length ||
            !(header.SequenceEqual(new byte[] { 0x49, 0x49, 0x2A, 0x00 }) ||
                header.SequenceEqual(new byte[] { 0x4D, 0x4D, 0x00, 0x2A })))
        {
            throw new UnsupportedUploadTypeException("upload_signature_mismatch");
        }
    }

    private static void ValidatePrefix(string path, ReadOnlySpan<byte> expected, string errorCode)
    {
        Span<byte> actual = stackalloc byte[expected.Length];
        using var stream = File.OpenRead(path);
        if (stream.Read(actual) != actual.Length || !actual.SequenceEqual(expected))
        {
            throw new UnsupportedUploadTypeException(errorCode);
        }
    }

    private static string NormalizeContentType(string? contentType)
    {
        var normalized = RemoveControlCharacters(contentType ?? string.Empty).Trim();
        var separator = normalized.IndexOf(';');
        return (separator >= 0 ? normalized[..separator] : normalized).Trim().ToLowerInvariant();
    }

    private static string RemoveControlCharacters(string value) =>
        new(value.Where(character => !char.IsControl(character)).ToArray());

    private static string TruncateValidUtf16(string value, int maxLength)
    {
        if (value.Length <= maxLength)
        {
            return value;
        }

        var length = maxLength;
        if (char.IsHighSurrogate(value[length - 1]) && char.IsLowSurrogate(value[length]))
        {
            length -= 1;
        }

        return value[..length];
    }

    private sealed record AllowedUploadType(
        string CanonicalContentType,
        IReadOnlyList<string> AcceptedContentTypes);
}
