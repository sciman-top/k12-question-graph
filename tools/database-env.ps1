$ErrorActionPreference = 'Stop'

function Resolve-KqgDatabasePassword {
    param(
        [AllowNull()]
        [string] $DatabasePassword
    )

    if (-not [string]::IsNullOrWhiteSpace($DatabasePassword)) {
        return $DatabasePassword
    }

    foreach ($target in @('Process', 'User', 'Machine')) {
        $value = [Environment]::GetEnvironmentVariable('PGPASSWORD', $target)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return ''
}

function Use-KqgDatabasePassword {
    param(
        [AllowNull()]
        [string] $DatabasePassword
    )

    $resolved = Resolve-KqgDatabasePassword -DatabasePassword $DatabasePassword
    if (-not [string]::IsNullOrWhiteSpace($resolved)) {
        $env:PGPASSWORD = $resolved
    }

    return $resolved
}

function Resolve-KqgConnectionString {
    param(
        [AllowNull()]
        [string] $ConnectionString
    )

    if (-not [string]::IsNullOrWhiteSpace($ConnectionString)) {
        return $ConnectionString
    }

    foreach ($target in @('Process', 'User', 'Machine')) {
        $value = [Environment]::GetEnvironmentVariable('KQG_CONNECTION_STRING', $target)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }

    return ''
}
