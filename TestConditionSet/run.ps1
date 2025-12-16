Write-Information "Function gestart"
param($req)


# Detecteer of $req.Body al een object is (hashtable/PSCustomObject), of een string
Write-Information "Stap: body check"
if ($req.Body -is [string]) {
    Write-Information "Stap: body is string"
    $rawBody = $req.Body
    Write-Information "RAW BODY (string): $rawBody"
    try {
        $body = $rawBody | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $errMsg = $_.Exception.Message
        Write-Information "FOUT: Kan body niet parsen als JSON: $errMsg"
        Write-Information "Ruwe body ontvangen: $rawBody"
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
    Write-Information "Stap: body is object"
    $body = $req.Body
    Write-Information "RAW BODY (object): $($body | Out-String)"
}

# Debug: parsing conditionSet en maxPersons
try {
    $conditionSet = $body.conditionSet
    if ($null -eq $conditionSet) {
        $conditionSet = @()
    } elseif ($conditionSet -isnot [System.Collections.IEnumerable] -or $conditionSet -is [string]) {
        $conditionSet = @($conditionSet)
    }
    $maxPersons = 0
    if ($body -and $body.maxPersons -ne $null) {
        $maxPersons = [int]$body.maxPersons
        Write-Information "maxPersons ontvangen: $($body.maxPersons) (type: $($body.maxPersons.GetType().FullName))"
    } else {
        Write-Information "maxPersons NIET aanwezig in body"
    }
} catch {
    Write-Information "FOUT bij parsing van conditionSet/maxPersons: $_"
    throw $_
}


# Importeer StructMatcher module
Write-Information "Stap: importeer StructMatcher module"
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
Write-Information "Stap: hybride pad check (lokaal of Azure)"
$localPath = "$PSScriptRoot/../TestPersons/blaat"
if (Test-Path $localPath) {
    Write-Information "Stap: lokaal pad gevonden"
    Write-Information "Lokaal: gebruik $localPath"
    $personFiles = Get-ChildItem -Path $localPath -Filter *.json -File
    if ($maxPersons -gt 0) {
        $personFiles = $personFiles | Select-Object -First $maxPersons
    }
    Write-Information "Found $($personFiles.Count) person files to process."
    foreach ($personFile in $personFiles) {
        Write-Information "Stap: verwerk lokaal bestand $($personFile.Name)"
        try {
            Write-Information "Stap: parse lokaal JSON bestand"
            $personData = Get-Content $personFile.FullName -Raw | ConvertFrom-Json
            foreach ($set in $conditionSet) {
                Write-Information "Stap: test conditionSet op lokaal bestand $($personFile.Name)"
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
            Write-Information "FOUT bij verwerken lokaal bestand $($personFile.Name): $_"
            $results += [PSCustomObject]@{
                File = $personFile.Name
                Error = $_.Exception.Message
            }
        }
    }
} else {
    Write-Information "Stap: geen lokaal pad, probeer Azure Blob Storage"
    Write-Information "Azure: lees uit Blob Storage container 'persons'"
    Write-Information "Stap: haal connection string op"
    $connectionString = $env:AzureWebJobsStorage
    Write-Information "AzureWebJobsStorage: $connectionString"
    if (-not $connectionString) {
        Write-Information "FOUT: AzureWebJobsStorage niet gevonden"
        throw "AzureWebJobsStorage environment variable niet gevonden."
    }
    # Parse connection string for account name and key
    Write-Information "Stap: parse accountName en accountKey"
    $accountName = ($connectionString -split ";") | Where-Object { $_ -like "AccountName=*" } | ForEach-Object { $_.Split("=")[1] }
    $accountKey = ($connectionString -split ";") | Where-Object { $_ -like "AccountKey=*" } | ForEach-Object { $_.Split("=")[1] }
    $container = 'persons'
    Write-Information "Stap: bouw blobServiceUrl"
    $blobServiceUrl = "https://$accountName.blob.core.windows.net/$container?restype=container&comp=list"
    $headers = @{}
    Write-Information "Stap: bouw headers en auth voor blobServiceUrl"
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
    Write-Information "Stap: doe REST call voor blob lijst"
    $response = Invoke-RestMethod -Uri $blobServiceUrl -Method Get -Headers $headers
    Write-Information "Stap: verwerk blob lijst response"
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
    Write-Information "Found $($blobNames.Count) blobs to process."
    foreach ($blobName in $blobNames) {
        Write-Information "Stap: download blob $blobName"
        try {
            Write-Information "Stap: doe REST call voor blob $blobName"
            $blobUrl = "https://$accountName.blob.core.windows.net/$container/$blobName"
            $headers['Authorization'] = Get-BlobAuthHeader -method 'GET' -url $blobUrl -accountName $accountName -accountKey $accountKey
            $blobContent = Invoke-RestMethod -Uri $blobUrl -Method Get -Headers $headers
            Write-Information "Stap: parse JSON van blob $blobName"
            $personData = $blobContent | ConvertFrom-Json
            foreach ($set in $conditionSet) {
                Write-Information "Stap: test conditionSet op blob $blobName"
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
            Write-Information "FOUT bij verwerken blob $blobName: $_"
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
