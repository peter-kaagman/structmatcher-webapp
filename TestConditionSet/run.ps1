param($req, $TriggerMetadata)

function Run-Function {
    param($req, $TriggerMetadata)
    Write-Information "Skeleton function called"
    if ($null -ne $req.Body) {
        Write-Information "Body ontvangen"
    } else {
        Write-Information "Geen body ontvangen"
        # Raise error or handle accordingly
        Push-OutputBinding -Name res -Value ([HttpResponseContext]@{
            StatusCode = 400
            Body = @{ message = "Geen body ontvangen" }
        })
        return
    }

    Push-OutputBinding -Name res -Value ([HttpResponseContext]@{
        StatusCode = 200
        Body = @{ message = "Skeleton function werkt" }
    })
}

Run-Function -req $req -TriggerMetadata $TriggerMetadata