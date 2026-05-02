# apps/api

ASP.NET Core API created by `A002`.

Run:

```powershell
dotnet run --project apps/api
```

Health check:

```powershell
Invoke-RestMethod http://localhost:5275/health
```

The API reads data, file store, backup, and log roots from the `KqgPaths` configuration section instead of relying on the current working directory.
