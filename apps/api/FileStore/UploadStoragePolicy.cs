namespace K12QuestionGraph.Api.FileStore;

internal sealed record UploadStorageIdentity(
    string OriginalFileName,
    string ContentType,
    string StorageExtension);

internal static class UploadStoragePolicy
{
    public const long MaxUploadBytes = 128L * 1024 * 1024;

    private const int MaxOriginalFileNameLength = 260;
    private const int MaxContentTypeLength = 128;
    private const int MaxStorageExtensionLength = 16;

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
            fileName = "upload.bin";
        }

        var normalizedContentType = RemoveControlCharacters(contentType ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(normalizedContentType) || normalizedContentType.Length > MaxContentTypeLength)
        {
            normalizedContentType = "application/octet-stream";
        }

        return new UploadStorageIdentity(
            TruncateValidUtf16(fileName, MaxOriginalFileNameLength),
            normalizedContentType,
            NormalizeStorageExtension(fileName));
    }

    private static string NormalizeStorageExtension(string fileName)
    {
        var extension = Path.GetExtension(fileName);
        if (extension.Length is < 2 or > MaxStorageExtensionLength)
        {
            return ".bin";
        }

        for (var index = 1; index < extension.Length; index += 1)
        {
            if (!char.IsAsciiLetterOrDigit(extension[index]))
            {
                return ".bin";
            }
        }

        return extension.ToLowerInvariant();
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
}
