using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Hosting;

namespace K12QuestionGraph.Api.Tests;

internal static class WorkerTestHarness
{
    internal static readonly Lazy<string> PythonExecutable = new(ResolvePythonExecutable);

    internal static readonly Lazy<string> WorkerScript = new(
        () => Path.Combine(FindRepoRoot(), "workers", "document", "worker.py"));

    internal static string CreateTempDirectory()
    {
        var path = Path.Combine(Path.GetTempPath(), "kqg-worker-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    internal static void DeleteDirectoryBestEffort(string path)
    {
        try
        {
            Directory.Delete(path, recursive: true);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    internal static void WriteStubScript(string directory, string fileName, string code)
    {
        File.WriteAllText(Path.Combine(directory, fileName), code, new UTF8Encoding(false));
    }

    internal static void WriteMinimalDocx(string path, params string[] paragraphs)
    {
        var body = new StringBuilder();
        foreach (var paragraph in paragraphs)
        {
            body.Append("<w:p><w:r><w:t xml:space=\"preserve\">")
                .Append(System.Security.SecurityElement.Escape(paragraph))
                .Append("</w:t></w:r></w:p>");
        }

        var documentXml =
            "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
            "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" " +
            "xmlns:m=\"http://schemas.openxmlformats.org/officeDocument/2006/math\">" +
            $"<w:body>{body}</w:body></w:document>";

        using var archive = ZipFile.Open(path, ZipArchiveMode.Create);
        var entry = archive.CreateEntry("word/document.xml", CompressionLevel.Optimal);
        using var stream = entry.Open();
        using var writer = new StreamWriter(stream, new UTF8Encoding(false));
        writer.Write(documentXml);
    }

    private static string ResolvePythonExecutable()
    {
        foreach (var candidate in new[] { "python", "py" })
        {
            try
            {
                var startInfo = new ProcessStartInfo
                {
                    FileName = candidate,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                };
                startInfo.ArgumentList.Add("--version");
                using var process = Process.Start(startInfo);
                if (process is not null && process.WaitForExit(10_000) && process.ExitCode == 0)
                {
                    return candidate;
                }
            }
            catch (System.ComponentModel.Win32Exception)
            {
            }
            catch (InvalidOperationException)
            {
            }
        }

        throw new InvalidOperationException(
            "python executable not found on PATH; worker transport contract tests require python (Quick profile already depends on it via worker tests)");
    }

    private static string FindRepoRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null &&
            !File.Exists(Path.Combine(directory.FullName, "workers", "document", "worker.py")))
        {
            directory = directory.Parent;
        }

        return directory?.FullName
            ?? throw new InvalidOperationException($"repo root not found from {AppContext.BaseDirectory}");
    }
}

internal sealed class FakeHostEnvironment : IHostEnvironment
{
    public string ApplicationName { get; set; } = "kqg-tests";

    public string EnvironmentName { get; set; } = "Development";

    public string ContentRootPath { get; set; } = ".";

    public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
}
