param($req, $TriggerMetadata)

function Run-Function {
    param($req, $TriggerMetadata)
    # TODO: implement logic step by step
    Write-Information "Skeleton function called"
    Push-OutputBinding -Name res -Value ([HttpResponseContext]@{
        StatusCode = 200
        Body = @{ message = "Skeleton function executed" }
    })
}

Run-Function -req $req -TriggerMetadata $TriggerMetadata
