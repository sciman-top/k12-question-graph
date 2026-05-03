$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$suitePath = Join-Path $repoRoot 'configs\ai-evals\d003-structured-output-evals.sample.json'

function Get-JsonProperty($Object, [string] $Name) {
    if ($null -eq $Object) {
        return $null
    }
    return $Object.PSObject.Properties[$Name]
}

function Test-JsonKind($Value, [string] $Type) {
    switch ($Type) {
        'null' { return $null -eq $Value }
        'string' { return $Value -is [string] }
        'boolean' { return $Value -is [bool] }
        'integer' { return $Value -is [byte] -or $Value -is [int16] -or $Value -is [int] -or $Value -is [int64] }
        'number' { return $Value -is [byte] -or $Value -is [int16] -or $Value -is [int] -or $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal] }
        'array' { return $Value -is [System.Array] }
        'object' { return $null -ne $Value -and -not ($Value -is [System.Array]) -and ($Value -is [pscustomobject]) }
        default { throw "unsupported schema type: $Type" }
    }
}

function Test-TypeAllowed($Schema, $Value, [string] $Path) {
    $typeProperty = Get-JsonProperty $Schema 'type'
    if ($null -eq $typeProperty) {
        return
    }

    $allowedTypes = @($typeProperty.Value)
    foreach ($allowedType in $allowedTypes) {
        if (Test-JsonKind -Value $Value -Type ([string]$allowedType)) {
            return
        }
    }

    throw "$Path expected type $($allowedTypes -join '|')"
}

function Test-StructuredOutput($Schema, $Value, [string] $Path) {
    Test-TypeAllowed -Schema $Schema -Value $Value -Path $Path

    $enumProperty = Get-JsonProperty $Schema 'enum'
    if ($null -ne $enumProperty) {
        $matches = @($enumProperty.Value) | Where-Object { [string]$_ -eq [string]$Value }
        if (@($matches).Count -lt 1) {
            throw "$Path value '$Value' is not in enum"
        }
    }

    $minimumProperty = Get-JsonProperty $Schema 'minimum'
    if ($null -ne $minimumProperty -and $null -ne $Value -and [decimal]$Value -lt [decimal]$minimumProperty.Value) {
        throw "$Path is below minimum $($minimumProperty.Value)"
    }

    $maximumProperty = Get-JsonProperty $Schema 'maximum'
    if ($null -ne $maximumProperty -and $null -ne $Value -and [decimal]$Value -gt [decimal]$maximumProperty.Value) {
        throw "$Path is above maximum $($maximumProperty.Value)"
    }

    $typeProperty = Get-JsonProperty $Schema 'type'
    $schemaTypes = if ($null -ne $typeProperty) { @($typeProperty.Value) } else { @() }

    if (($schemaTypes -contains 'object' -or (Get-JsonProperty $Schema 'properties')) -and (Test-JsonKind -Value $Value -Type 'object')) {
        if ($null -eq $Value) {
            return
        }

        $propertiesProperty = Get-JsonProperty $Schema 'properties'
        $schemaProperties = if ($null -ne $propertiesProperty) { $propertiesProperty.Value } else { $null }
        $requiredProperty = Get-JsonProperty $Schema 'required'
        if ($null -ne $requiredProperty) {
            foreach ($requiredName in @($requiredProperty.Value)) {
                if ($null -eq (Get-JsonProperty $Value ([string]$requiredName))) {
                    throw "$Path missing required property '$requiredName'"
                }
            }
        }

        $additionalPropertiesProperty = Get-JsonProperty $Schema 'additionalProperties'
        if ($null -ne $additionalPropertiesProperty -and $additionalPropertiesProperty.Value -eq $false -and $null -ne $schemaProperties) {
            foreach ($actualProperty in $Value.PSObject.Properties) {
                if ($null -eq (Get-JsonProperty $schemaProperties $actualProperty.Name)) {
                    throw "$Path has additional property '$($actualProperty.Name)'"
                }
            }
        }

        if ($null -ne $schemaProperties) {
            foreach ($schemaProperty in $schemaProperties.PSObject.Properties) {
                $actualProperty = Get-JsonProperty $Value $schemaProperty.Name
                if ($null -ne $actualProperty) {
                    Test-StructuredOutput -Schema $schemaProperty.Value -Value $actualProperty.Value -Path "$Path.$($schemaProperty.Name)"
                }
            }
        }
    }

    if (($schemaTypes -contains 'array') -and (Test-JsonKind -Value $Value -Type 'array')) {
        if ($null -eq $Value) {
            return
        }

        $minItemsProperty = Get-JsonProperty $Schema 'minItems'
        if ($null -ne $minItemsProperty -and @($Value).Count -lt [int]$minItemsProperty.Value) {
            throw "$Path has fewer than $($minItemsProperty.Value) items"
        }

        $maxItemsProperty = Get-JsonProperty $Schema 'maxItems'
        if ($null -ne $maxItemsProperty -and @($Value).Count -gt [int]$maxItemsProperty.Value) {
            throw "$Path has more than $($maxItemsProperty.Value) items"
        }

        $itemsProperty = Get-JsonProperty $Schema 'items'
        if ($null -ne $itemsProperty) {
            $index = 0
            foreach ($item in @($Value)) {
                Test-StructuredOutput -Schema $itemsProperty.Value -Value $item -Path "$Path[$index]"
                $index++
            }
        }
    }
}

function Get-ConfidenceValues($Value) {
    $values = New-Object System.Collections.Generic.List[decimal]
    if ($null -eq $Value) {
        return $values
    }

    if ($Value -is [System.Array]) {
        foreach ($item in $Value) {
            foreach ($confidence in Get-ConfidenceValues $item) {
                $values.Add($confidence)
            }
        }
        return $values
    }

    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if ($property.Name -eq 'confidence' -and $null -ne $property.Value) {
                $values.Add([decimal]$property.Value)
            }
            foreach ($confidence in Get-ConfidenceValues $property.Value) {
                $values.Add($confidence)
            }
        }
    }

    return $values
}

Push-Location $repoRoot
try {
    $suite = Get-Content -LiteralPath $suitePath -Raw | ConvertFrom-Json

    if ($suite.mode -ne 'draft_test') { throw "D003 eval suite must stay in draft_test mode" }
    if ($suite.allowRealModelCalls) { throw "D003 eval suite must not allow real model calls" }
    if ($suite.productionEligible) { throw "D003 eval suite must not be production eligible" }
    if (@($suite.cases).Count -lt 1) { throw "D003 eval suite has no cases" }

    $caseResults = New-Object System.Collections.Generic.List[object]
    foreach ($case in $suite.cases) {
        if ([string]::IsNullOrWhiteSpace($case.caseId)) { throw "eval case missing caseId" }
        if ([string]::IsNullOrWhiteSpace($case.taskType)) { throw "eval case $($case.caseId) missing taskType" }
        if ([string]::IsNullOrWhiteSpace($case.schemaPath)) { throw "eval case $($case.caseId) missing schemaPath" }
        if ($case.expectedReviewStatus -ne 'pending_review') { throw "eval case $($case.caseId) must stay pending_review" }

        $schemaPath = Join-Path $repoRoot $case.schemaPath
        if (-not (Test-Path -LiteralPath $schemaPath)) {
            throw "schema does not exist for eval case $($case.caseId): $($case.schemaPath)"
        }

        $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        Test-StructuredOutput -Schema $schema -Value $case.expectedOutput -Path "$($case.caseId).expectedOutput"

        $confidences = @(Get-ConfidenceValues $case.expectedOutput)
        if ($confidences.Count -gt 0) {
            foreach ($confidence in $confidences) {
                if ($confidence -lt 0 -or $confidence -gt 1) {
                    throw "eval case $($case.caseId) confidence out of range"
                }
            }
            if ($confidences[0] -lt [decimal]$case.minConfidence) {
                throw "eval case $($case.caseId) primary confidence below minimum"
            }
        }

        $caseResults.Add([ordered]@{
            caseId = [string]$case.caseId
            taskType = [string]$case.taskType
            schemaPath = [string]$case.schemaPath
            reviewStatus = [string]$case.expectedReviewStatus
            confidenceValues = $confidences.Count
        })
    }

    [ordered]@{
        status = 'pass'
        suiteId = [string]$suite.suiteId
        mode = [string]$suite.mode
        allowRealModelCalls = [bool]$suite.allowRealModelCalls
        productionEligible = [bool]$suite.productionEligible
        evalRepeatable = $true
        cases = $caseResults
    } | ConvertTo-Json -Depth 6
}
finally {
    Pop-Location
}
