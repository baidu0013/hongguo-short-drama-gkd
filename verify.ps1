param(
    [string]$RulePath = (Join-Path $PSScriptRoot 'gkd.json5'),
    [string]$SourcePath
)
$ErrorActionPreference = 'Stop'

function Read-Json5([string]$Path) {
    $result = & npx --yes --package=json5@2.2.3 json5 $Path
    if ($LASTEXITCODE -ne 0) { throw "JSON5 parsing failed: $Path" }
    return ($result | ConvertFrom-Json -Depth 100)
}

function Require([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

$sourceHashBefore = if ($SourcePath) { (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash }
$sub = Read-Json5 $RulePath
Require ($sub.id -eq 1967090753 -and $sub.id -is [long]) 'Unexpected subscription ID.'
Require ($sub.version -is [long] -and $sub.version -ge 1) 'Version must be a positive integer.'
Require ($sub.name -eq '红果短剧广告规则') 'Unexpected subscription name.'
Require ($sub.apps.Count -eq 1) 'Expected one app.'
Require ($null -eq $sub.groups) 'App groups must be nested under apps.'
if ($sub.updateUrl) {
    $url = [uri]$sub.updateUrl
    Require ($url.IsAbsoluteUri -and $url.Scheme -eq 'https') 'updateUrl must be absolute HTTPS.'
}
$app = $sub.apps[0]
Require ($app.id -ceq 'com.phoenix.read') 'Unexpected app ID.'
Require (($app.groups.key -join ',') -ceq '0,1,2,4,5') 'Unexpected group keys or order.'
Require (($app.groups.key | Select-Object -Unique).Count -eq $app.groups.Count) 'Duplicate group key.'
$ruleCount = 0
foreach ($group in $app.groups) {
    Require ($group.rules.Count -gt 0) "No rules in group $($group.key)."
    foreach ($rule in $group.rules) {
        Require ($rule.matches.Count -gt 0) "No matches in group $($group.key)."
        $ruleCount++
    }
}
$retry = @($app.groups | Where-Object key -EQ 5)[0]
Require ($retry.actionDelay -eq 1000 -and $retry.actionCd -eq 1000) 'Retry timing changed.'
Require ($null -eq $retry.actionMaximum -and $null -eq $retry.rules[0].actionMaximum) 'Unexpected retry quota.'
Require ($retry.rules.Count -eq 1 -and $retry.rules[0].action -ceq 'swipe') 'Expected one retry swipe rule.'
Require ($retry.rules[0].matches.Count -eq 1) 'Expected one retry selector.'
$selector = '[text="上滑继续观看短剧" || text="上滑继续看短剧"][visibleToUser=true]'
Require ($retry.rules[0].matches[0] -ceq $selector) 'Retry selector changed.'
Require (($app | ConvertTo-Json -Depth 100) -notmatch 'ttlive_player_render_view') 'Unexpected player-based matching.'
Write-Output "PASS: JSON5 parsed; subscription ID=$($sub.id), version=$($sub.version), 1 app, $($app.groups.Count) groups, $ruleCount rules."
Write-Output 'PASS: both visible-text variants, delay/cooldown, no retry quota, no player selector.'

if ($SourcePath) {
    $source = Read-Json5 $SourcePath
    $sourceJson = $source | ConvertTo-Json -Depth 100 -Compress
    $appJson = $app | ConvertTo-Json -Depth 100 -Compress
    Require ($sourceJson -ceq $appJson) 'apps[0] differs from the original app rule.'
    $sourceHashAfter = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
    Require ($sourceHashBefore -ceq $sourceHashAfter) 'Source file changed during verification.'
    Write-Output "PASS: apps[0] equals original app; source SHA256=$sourceHashAfter."
}
Write-Output "ARTIFACT SHA256=$((Get-FileHash -LiteralPath $RulePath -Algorithm SHA256).Hash)"
Write-Output 'LIMIT: offline parsing/basic structure only; no device, selector-engine or live subscription test.'
