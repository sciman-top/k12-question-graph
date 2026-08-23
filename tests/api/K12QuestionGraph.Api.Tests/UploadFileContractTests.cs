using System.Net;
using System.Net.Http.Json;
using K12QuestionGraph.Api.FileStore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace K12QuestionGraph.Api.Tests;

/// <summary>
/// tools/import-c002-source-materials.ps1 上传契约的回归护栏。
/// 该脚本 POST multipart 到 /files 并直接读取顶层 id、relativePath、sha256、
/// isDuplicate 与 sourceDocument 元数据；端点或响应形状漂移会当场打断教师导入主链。
/// </summary>
public sealed class UploadFileContractTests : IClassFixture<UploadFileContractTests.UploadFactory>
{
    private readonly UploadFactory factory;

    public UploadFileContractTests(UploadFactory factory)
    {
        this.factory = factory;
    }

    [Fact]
    public async Task PostFilesRoute_ExistsAndRejectsMissingFile()
    {
        // 不触数据库即可证明路由仍存在且表单可解析：404/405 意味着契约已丢失，
        // 400 missing_file 才是契约仍在的响应。
        using var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-KQG-Admin-Key", UploadFactory.ApiKey);
        using var form = new MultipartFormDataContent();
        using var emptyFields = new StringContent("irrelevant");

        form.Add(emptyFields, "sourceTitle");
        var response = await client.PostAsync("/files", form);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var payload = await response.Content.ReadFromJsonAsync<Dictionary<string, string>>();
        Assert.NotNull(payload);
        Assert.Equal("missing_file", payload["error"]);
    }

    [Fact]
    public void FileAssetResponse_KeepsUploadContractMembersUsedByImportTool()
    {
        var responseMembers = new[]
        {
            "Id", "RelativePath", "Sha256", "IsDuplicate", "SourceDocument"
        };
        var sourceDocumentMembers = new[]
        {
            "Id", "SourceType", "SourceTitle", "Region", "Year", "GradeOrScope",
            "EditionOrVersion", "MaterialBatchKey", "OwnerScope", "LicenseOrPermission",
            "SharingAllowed", "ContainsStudentPii", "AnonymizationStatus", "ExternalAiAllowed",
            "MayUseForKnowledgeExtraction", "MayUseForExamPointExtraction", "MayUseForTrendAnalysis"
        };
        foreach (var member in responseMembers)
        {
            Assert.True(
                typeof(FileAssetResponse).GetProperty(member) is not null,
                $"FileAssetResponse.{member} is required by tools/import-c002-source-materials.ps1");
        }

        foreach (var member in sourceDocumentMembers)
        {
            Assert.True(
                typeof(SourceDocumentResponse).GetProperty(member) is not null,
                $"SourceDocumentResponse.{member} is required by tools/import-c002-source-materials.ps1");
        }
    }

    public sealed class UploadFactory : WebApplicationFactory<Program>
    {
        internal const string ApiKey = "upload-contract-test-secret";

        protected override void ConfigureWebHost(IWebHostBuilder builder)
        {
            builder.UseEnvironment("Development");
            builder.ConfigureAppConfiguration((_, configuration) =>
                configuration.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["AdminInternalGuard:ApiKey"] = ApiKey,
                    ["AdminInternalGuard:AllowUnguardedDraftTest"] = "false",
                    ["AdminInternalGuard:TrustedRole"] = "admin",
                    ["AdminInternalGuard:TrustedOperatorId"] = "upload-contract-test",
                    ["AdminInternalRoleAudit:Enabled"] = "false"
                }));
        }
    }
}
