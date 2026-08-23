Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    发布收口边界不变量的唯一实现,供 roadmap、live-pilot-closeout、evidence-index
    三个 guard 共同调用。此前同一组事实在三个脚本里各写一份,且数值随计划演进漂移。

.DESCRIPTION
    统一断言:
    - REAL005 当前证据必须保持 closureStatus=not_closed 且 fullClosureAllowed=false;
    - P001-P006 在 backlog 中必须保持待办(传入 $BacklogById 时才检查);
    - 发布卡必须保持 No-Go;CurrentClosureStatus 必须保留 REAL005 = not_closed。
    任一 guard 触发即视为发布收口状态漂移,fail-closed。
#>
function Test-ReleaseCloseoutInvariants {
    [CmdletBinding()]
    param(
        [hashtable] $BacklogById,
        [Parameter(Mandatory = $true)] [psobject] $Real005Evidence,
        [Parameter(Mandatory = $true)] [string] $ReleaseCardText,
        [Parameter(Mandatory = $true)] [string] $ClosureSummaryText
    )

    if ($null -ne $BacklogById) {
        foreach ($id in @('P001', 'P002', 'P003', 'P004', 'P005', 'P006')) {
            if (-not $BacklogById.ContainsKey($id) -or [string]$BacklogById[$id].status -ne '待办') {
                throw "$id must remain open until onsite/manual evidence closes it"
            }
        }
    }

    if ([string]$Real005Evidence.closureStatus -ne 'not_closed' -or $Real005Evidence.fullClosureAllowed -ne $false) {
        throw 'REAL005 must remain not_closed with fullClosureAllowed=false'
    }

    if ($ReleaseCardText -notmatch 'No-Go') {
        throw 'release card must remain No-Go'
    }

    if ($ClosureSummaryText -notmatch 'REAL005\s*=\s*not_closed') {
        throw 'current closure status must preserve REAL005 not_closed'
    }
}

Export-ModuleMember -Function Test-ReleaseCloseoutInvariants
