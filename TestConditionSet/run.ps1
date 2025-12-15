param($req)


# Detecteer of $req.Body al een object is (hashtable/PSCustomObject), of een string
if ($req.Body -is [string]) {
    $rawBody = $req.Body
    Write-Host "RAW BODY (string): $rawBody"
    try {
        $body = $rawBody | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $errMsg = $_.Exception.Message
        Write-Host "FOUT: Kan body niet parsen als JSON: $errMsg"
        Write-Host "Ruwe body ontvangen: $rawBody"
        Push-OutputBinding -Name res -Value ([HttpResponseContext]@{
            StatusCode = 400
            Body = @{ 
                Error = "Ongeldige JSON in body"
                Details = $errMsg
                RawBody = $rawBody
            }
        })
        return
    }
} else {
    $body = $req.Body
    Write-Host "RAW BODY (object): $($body | Out-String)"
}

# Haal conditionSet en maxPersons uit de geparste body
$conditionSet = $body.conditionSet
if ($null -eq $conditionSet) {
    $conditionSet = @()
} elseif ($conditionSet -isnot [System.Collections.IEnumerable] -or $conditionSet -is [string]) {
    $conditionSet = @($conditionSet)
}

$maxPersons = 0
if ($body -and $body.maxPersons -ne $null) {
    $maxPersons = [int]$body.maxPersons
    Write-Host "maxPersons ontvangen: $($body.maxPersons) (type: $($body.maxPersons.GetType().FullName))"
} else {
    Write-Host "maxPersons NIET aanwezig in body"
}

# Importeer StructMatcher module
Import-Module "$PSScriptRoot/../PS-Modules/StructMatcher/StructMatcher.psm1"


# Sta toe dat conditionSet een enkele set of een array is
$conditionSet = $body.conditionSet
if ($null -eq $conditionSet) {
    $conditionSet = @()
} elseif ($conditionSet -isnot [System.Collections.IEnumerable] -or $conditionSet -is [string]) {
    $conditionSet = @($conditionSet)
}


# Zoek alle JSON-bestanden in de root van TestPersons (of submap indien gewenst)
$testPersonsPath = "$PSScriptRoot/../TestPersons/blaat"
$personFiles = Get-ChildItem -Path $testPersonsPath -Filter *.json -File

# Beperk het aantal te checken bestanden indien maxPersons > 0
if ($maxPersons -gt 0) {
    $personFiles = $personFiles | Select-Object -First $maxPersons
}
Write-Host "Found $($personFiles.Count) person files to process."

$results = @()
foreach ($personFile in $personFiles) {
    try {
        # Write-Host "Processing file: $($personFile.Name)"
        $personData = Get-Content $personFile.FullName -Raw | ConvertFrom-Json
        # Write-Host "PersonType: $($personData.PrimaryContract.Custom.PersonType)"
        # Write-Host "PersonLocation: $($personData.PrimaryContract.Location.Code)"
        foreach ($set in $conditionSet) {
            # Write-Host "Applying condition set: $($set|ConvertTo-Json -Depth 5)"
            $output = Test-ConditionSet -rules $set -data $personData
            if ($output) {
                Write-Host "MATCH for $($personFile.Name): $($personData.DisplayName) with result: $($set.result)"
                $results += [PSCustomObject]@{
                    File = $personFile.Name
                    DisplayName = $personData.DisplayName
                    Match = $output
                }
            # } else {
            #     Write-Host "NO MATCH for $($personFile.Name) with set: $($set|ConvertTo-Json -Depth 5)"
            }
        }
    } catch {
        $results += [PSCustomObject]@{
            File = $personFile.Name
            Error = $_.Exception.Message
        }
    }
}

Push-OutputBinding -Name res -Value ([HttpResponseContext]@{
    StatusCode = 200
    Body = $results
})
