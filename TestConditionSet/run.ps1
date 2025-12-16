param($req, $TriggerMetadata)

function RunFunction {
    param($req, $TriggerMetadata)
    Write-Information "Skeleton function called"
    if ($null -ne $req.Body) {
        Write-Information "Body ontvangen"
        if ($req.Body -is [string]) {
            Write-Information "Body is string"
            $rawBody = $req.Body
            Write-Information ("RAW BODY (string): {0}" -f $rawBody)
        } elseif ($req.Body -is [PSObject]) {
            Write-Information "Body is object"
            $body = $req.Body
            Write-Information ("RAW BODY (object): {0}" -f ($body | Out-String))
        } else {
            Write-Information "Body is van onbekend type: {0}" -f $req.Body.GetType().FullName
            # Handle unknown body type accordingly
            Push-OutputBinding -Name res -Value ([HttpResponseContext]@{
                StatusCode = 400
                Body = @{ message = "Onbekend body type ontvangen: $($req.Body.GetType().FullName)" }
            })
            return
        }
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

RunFunction -req $req -TriggerMetadata $TriggerMetadata