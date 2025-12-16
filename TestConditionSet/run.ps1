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
Import-Module "$PSScriptRoot/../PS-Modules/StructMatcher/StructMatcher.psm1" -Verbose


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
    # Parse connection string for account name and key
    $accountName = ($connectionString -split ";") | Where-Object { $_ -like "AccountName=*" } | ForEach-Object { $_.Split("=")[1] }
    $accountKey = ($connectionString -split ";") | Where-Object { $_ -like "AccountKey=*" } | ForEach-Object { $_.Split("=")[1] }
    $container = 'persons'
    $blobServiceUrl = "https://$accountName.blob.core.windows.net/$container?restype=container&comp=list"
    $headers = @{}
    # Build Shared Key authorization header
    function Get-BlobAuthHeader {
        param($method, $url, $accountName, $accountKey)
        $uri = [System.Uri]$url
        $now = [DateTime]::UtcNow.ToString("R")
        $canonicalizedResource = "/$accountName/$container"
        $stringToSign = "$method`n`n`n`n`n`n`n`n`n`n`n`n$now`n$canonicalizedResource?comp=list&restype=container"
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = [Convert]::FromBase64String($accountKey)
        $signature = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))
        "SharedKey $accountName:$signature"
    }
    $headers['x-ms-date'] = [DateTime]::UtcNow.ToString("R")
    $headers['x-ms-version'] = '2020-10-02'
    $headers['Authorization'] = Get-BlobAuthHeader -method 'GET' -url $blobServiceUrl -accountName $accountName -accountKey $accountKey
    $response = Invoke-RestMethod -Uri $blobServiceUrl -Method Get -Headers $headers
    $blobNames = @()
    if ($response.EnumerationResults.Blobs.Blob -is [Array]) {
        $blobNames = $response.EnumerationResults.Blobs.Blob | Where-Object { $_.Name -like '*.json' } | ForEach-Object { $_.Name }
    } elseif ($response.EnumerationResults.Blobs.Blob) {
        if ($response.EnumerationResults.Blobs.Blob.Name -like '*.json') {
            $blobNames = @($response.EnumerationResults.Blobs.Blob.Name)
        }
    }
    if ($maxPersons -gt 0) {
        $blobNames = $blobNames | Select-Object -First $maxPersons
    }
    Write-Host "Found $($blobNames.Count) blobs to process."
    foreach ($blobName in $blobNames) {
        try {
            $blobUrl = "https://$accountName.blob.core.windows.net/$container/$blobName"
            $headers['Authorization'] = Get-BlobAuthHeader -method 'GET' -url $blobUrl -accountName $accountName -accountKey $accountKey
            $blobContent = Invoke-RestMethod -Uri $blobUrl -Method Get -Headers $headers
            $personData = $blobContent | ConvertFrom-Json
            foreach ($set in $conditionSet) {
                $output = Test-ConditionSet -rules $set -data $personData
                if ($output) {
                    $results += [PSCustomObject]@{
                        File = $blobName
                        DisplayName = $personData.DisplayName
                        Match = $output
                    }
                }
            }
        } catch {
            $results += [PSCustomObject]@{
                File = $blobName
                Error = $_.Exception.Message
            }
        }
    }
}

Push-OutputBinding -Name res -Value ([HttpResponseContext]@{
    StatusCode = 200
    Body = $results
})
