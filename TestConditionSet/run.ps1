
param($req)

# Debug: log de ontvangen body
Write-Host "RAW BODY: $($req.Body | Out-String)"
# Importeer StructMatcher module
Import-Module "$PSScriptRoot/../PS-Modules/StructMatcher/StructMatcher.psm1"

# Gebruik de body direct als object
$body = $req.Body
$conditionSet = $body.conditionSet
$personData = $body.personData

# Test alle condition sets
$result = $null
foreach ($set in $conditionSet) {
    $output = Test-ConditionSet -rules $set -data $personData
    if ($output) {
        $result = $output
        break
    }
}

if ($result) {
    Push-OutputBinding -Name res -Value ([HttpResponseContext]@{
        StatusCode = 200
        Body = $result
    })
} else {
    Push-OutputBinding -Name res -Value ([HttpResponseContext]@{
        StatusCode = 200
        Body = 'Geen match gevonden.'
    })
}
