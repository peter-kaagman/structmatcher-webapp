Write-Information "Function gestart"
param($req)


# Detecteer of $req.Body al een object is (hashtable/PSCustomObject), of een string
Write-Information "Stap: body check"
if ($req.Body -is [string]) {
    Write-Information "Stap: body is string"
    $rawBody = $req.Body
    Write-Information ("RAW BODY (string): {0}" -f $rawBody)

    param($req, $TriggerMetadata)

    function Run-Function {
        param($req, $TriggerMetadata)

        Write-Information "Stap: body check"
        if ($req.Body -is [string]) {
            Write-Information "Stap: body is string"
            $rawBody = $req.Body
            Write-Information ("RAW BODY (string): {0}" -f $rawBody)
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
            Write-Information ("RAW BODY (object): {0}" -f ($body | Out-String))
        }

        try {
            $conditionSet = $body.conditionSet
            if ($null -eq $conditionSet) {
                $conditionSet = @()
            } elseif ($conditionSet -isnot [System.Collections.IEnumerable] -or $conditionSet -is [string]) {
                $conditionSet = @($conditionSet)
            }
            $maxPersons = 0
            if ($null -ne $body -and $null -ne $body.maxPersons) {
                $maxPersons = [int]$body.maxPersons
                $msg = "maxPersons ontvangen: {0} (type: {1})" -f $body.maxPersons, $body.maxPersons.GetType().FullName
                Write-Information $msg
            } else {
                Write-Information "maxPersons NIET aanwezig in body"
            }
        } catch {
            $msg = "FOUT bij parsing van conditionSet/maxPersons: {0}" -f $_
            Write-Information $msg
            throw $_
        }

        Write-Information "Stap: importeer StructMatcher module"
        Import-Module "$PSScriptRoot/../PS-Modules/StructMatcher/StructMatcher.psm1" -Verbose

        $conditionSet = $body.conditionSet
        if ($null -eq $conditionSet) {
            $conditionSet = @()
        } elseif ($conditionSet -isnot [System.Collections.IEnumerable] -or $conditionSet -is [string]) {
            $conditionSet = @($conditionSet)
        }

        $results = @()
        Write-Information "Stap: hybride pad check (lokaal of Azure)"
        $localPath = "$PSScriptRoot/../TestPersons/blaat"
        if (Test-Path $localPath) {
            Write-Information ("Stap: lokaal pad gevonden")
            Write-Information ("Lokaal: gebruik {0}" -f $localPath)
            $personFiles = Get-ChildItem -Path $localPath -Filter *.json -File
            if ($maxPersons -gt 0) {
                $personFiles = $personFiles | Select-Object -First $maxPersons
            }
            Write-Information ("Found {0} person files to process." -f $personFiles.Count)
            foreach ($personFile in $personFiles) {
                Write-Information ("Stap: verwerk lokaal bestand {0}" -f $personFile.Name)
                try {
                    Write-Information ("Stap: parse lokaal JSON bestand")
                    $personData = Get-Content $personFile.FullName -Raw | ConvertFrom-Json
                    foreach ($set in $conditionSet) {
                        Write-Information ("Stap: test conditionSet op lokaal bestand {0}" -f $personFile.Name)
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
                    Write-Information ("FOUT bij verwerken lokaal bestand {0}: {1}" -f $personFile.Name, $_)
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
            Write-Information "Stap: parse accountName en accountKey"
            $accountName = ($connectionString -split ";") | Where-Object { $_ -like "AccountName=*" } | ForEach-Object { $_.Split("=")[1] }
            $accountKey = ($connectionString -split ";") | Where-Object { $_ -like "AccountKey=*" } | ForEach-Object { $_.Split("=")[1] }
            $container = 'persons'
            Write-Information "Stap: bouw blobServiceUrl"
            $blobServiceUrl = "https://${accountName}.blob.core.windows.net/${container}?restype=container&comp=list"
            $headers = @{}
            Write-Information "Stap: bouw headers en auth voor blobServiceUrl"
            function Get-BlobAuthHeader {
                param($method, $url, $accountName, $accountKey)
                $now = [DateTime]::UtcNow.ToString("R")
                $stringToSign = "$method`n`n`n`n`n`n`n`n`n`n`n`n$now`n/${accountName}/${container}?comp=list&restype=container"
                $hmac = New-Object System.Security.Cryptography.HMACSHA256
                $hmac.Key = [Convert]::FromBase64String($accountKey)
                $signature = [Convert]::ToBase64String($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($stringToSign)))
                $authHeader = "SharedKey {0}:{1}" -f $accountName, $signature
                return $authHeader
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
            Write-Information ("Found {0} blobs to process." -f $blobNames.Count)
            foreach ($blobName in $blobNames) {
                Write-Information ("Stap: download blob {0}" -f $blobName)
                try {
                    Write-Information ("Stap: doe REST call voor blob {0}" -f $blobName)
                    $blobUrl = "https://${accountName}.blob.core.windows.net/${container}/$blobName"
                    $headers['Authorization'] = Get-BlobAuthHeader -method 'GET' -url $blobUrl -accountName $accountName -accountKey $accountKey
                    $blobContent = Invoke-RestMethod -Uri $blobUrl -Method Get -Headers $headers
                    Write-Information ("Stap: parse JSON van blob {0}" -f $blobName)
                    $personData = $blobContent | ConvertFrom-Json
                    foreach ($set in $conditionSet) {
                        Write-Information ("Stap: test conditionSet op blob {0}" -f $blobName)
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
                    $msg = "FOUT bij verwerken blob {0}: {1}" -f $blobName, $_
                    Write-Information $msg
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
    }

    Run-Function -req $req -TriggerMetadata $TriggerMetadata
