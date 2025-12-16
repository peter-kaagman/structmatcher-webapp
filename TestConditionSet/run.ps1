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
# Importeer Az.Storage module
Import-Module Az.Storage 


# Sta toe dat conditionSet een enkele set of een array is
$conditionSet = $body.conditionSet
if ($null -eq $conditionSet) {
    $conditionSet = @()
} elseif ($conditionSet -isnot [System.Collections.IEnumerable] -or $conditionSet -is [string]) {
    $conditionSet = @($conditionSet)
}



# Hybride: lokaal of uit Azure Blob Storage
$results = @()
$localPath = "$PSScriptRoot/../TestPersons/blaat"
if (Test-Path $localPath) {
    Write-Host "Lokaal: gebruik $localPath"
    $personFiles = Get-ChildItem -Path $localPath -Filter *.json -File
    if ($maxPersons -gt 0) {
        $personFiles = $personFiles | Select-Object -First $maxPersons
    }
    Write-Host "Found $($personFiles.Count) person files to process."
    foreach ($personFile in $personFiles) {
        try {
            $personData = Get-Content $personFile.FullName -Raw | ConvertFrom-Json
            foreach ($set in $conditionSet) {
                $output = Test-ConditionSet -rules $set -data $personData
                if ($output) {
                    $results += [PSCustomObject]@{
                        File = $personFile.Name
                        DisplayName = $personData.DisplayName
                        Match = $output
                    }
                }
            }
        } catch {
            $results += [PSCustomObject]@{
                File = $personFile.Name
                Error = $_.Exception.Message
            }
        }
    }
} else {
    Write-Host "Azure: lees uit Blob Storage container 'persons'"
    # Vereist: Azure.Storage.Blobs module in requirements.psd1
    $connectionString = $env:AzureWebJobsStorage
    Write-Host "AzureWebJobsStorage: $connectionString"
    if (-not $connectionString) {
        throw "AzureWebJobsStorage environment variable niet gevonden."
    }
    $ctx = New-AzStorageContext -ConnectionString $connectionString
    $blobs = Get-AzStorageBlob -Container 'persons' -Context $ctx | Where-Object { $_.Name -like '*.json' }
    if ($maxPersons -gt 0) {
        $blobs = $blobs | Select-Object -First $maxPersons
    }
    Write-Host "Found $($blobs.Count) blobs to process."
    foreach ($blob in $blobs) {
        try {
            $blobContent = (Get-AzStorageBlobContent -Blob $blob.Name -Container 'persons' -Context $ctx -Force -Destination ([System.IO.Path]::GetTempFileName())).Content
            $json = Get-Content $blobContent -Raw
            $personData = $json | ConvertFrom-Json
            foreach ($set in $conditionSet) {
                $output = Test-ConditionSet -rules $set -data $personData
                if ($output) {
                    $results += [PSCustomObject]@{
                        File = $blob.Name
                        DisplayName = $personData.DisplayName
                        Match = $output
                    }
                }
            }
        } catch {
            $results += [PSCustomObject]@{
                File = $blob.Name
                Error = $_.Exception.Message
            }
        }
    }
}

Push-OutputBinding -Name res -Value ([HttpResponseContext]@{
    StatusCode = 200
    Body = $results
})
