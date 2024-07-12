<#
 .Synopsis
  Offers a set of standard PowerShell cmdlets for use in other scripts.

 .Description
  Offers a set of cmdlets for working with the Zendesk API via PowerShell, using Azure Key Vault for storing the API key.

 .Example
    # The Connect-ZenApi cmdlet builds a (plaintext) credential object with the basic auth header and the base API URI, for use with other cmdlets
    $AuthToken = Connect-ZenApi -ZendeskEmail "foo@bar.com" `
    -ZendeskDomain "yourtenanthere.zendesk.com"   `
    -KeyVaultName "MyKeyVault" `
    -SecretName "TopSecret"

    New-ZenTicketNote -AuthToken $AuthToken `
    -Ticket '420' `
    -Note "Hello world!" `
    -NoteType "Internal"


#>

# Import required module for retrieving the API key from Key Vault
Import-Module Az.KeyVault

function Connect-ZenApi {
    param(
        [Parameter (Mandatory=$true)]
        [string]$ZendeskEmail,
        [Parameter (Mandatory=$true)]
        [validatePattern('^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$')] #some FQDN validation via RegEx
        [string]$ZendeskDomain,
        [Parameter (Mandatory=$true)]
        [string]$KeyVaultName,
        [Parameter (Mandatory=$true)]
        [string]$SecretName
    )

    # Get the plaintext API key from Azure Key Vault
    try{
        [string]$ZendeskApiKey = (Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $SecretName).SecretValue | ConvertFrom-SecureString -AsPlainText
        Write-Verbose "Successfully retrieved secret from Key Vault"
    }
    catch{
        Write-Error "Failed to retrieve secret from Key Vault"
    }

    # Append /token to the email because it's required when using API token auth
    $ZendeskEmail = $ZendeskEmail + "/token"
    # Build the basic auth token
    $Base64AuthInfo = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($ZendeskEmail):$($ZendeskApiKey)")))"

    # Build auth headers used for web requests
    $Headers = @{
        "Authorization" = $Base64AuthInfo
        "Content-Type" = "application/json"
    }

    # Now build API URL
    [string]$ZendeskApiBaseUrl = "https://$ZendeskDomain/api/v2"

    $TicketsEndpoint = "/tickets.json"
    Write-Verbose "Attempting to connect to $ZendeskApiBaseUrl$TicketsEndpoint"
    $Req = Invoke-RestMethod -Uri $ZendeskApiBaseUrl$TicketsEndpoint -Headers $Headers -Method Get -ErrorAction Stop

    if($null -ne $req){
        Write-Host "Connected" -ForegroundColor Green
        # Return the URL and the headers in a hashtable for re-use in other functions
        $AuthObj = @{
            "Uri" = $ZendeskApiBaseUrl
            "AuthHeaders" = $Headers
        }
        Write-Output $AuthObj
    }
    else{
        Write-Error "Failed to connect to Zendesk API" -ForegroundColor Red
        Write-Verbose "Failed to connect to $ZendeskApiBaseUrl"
    }
}

function New-ZenTicketNote {
    param (
        [Parameter (Mandatory=$true)]
        [int]$Ticket,
        [Parameter (Mandatory=$true)]
        [string]$Note,
        [Parameter (Mandatory=$true)]
        [ValidateSet('Public','Internal')]
        [string]$NoteType,
        [Parameter (Mandatory=$true)]
        [hashtable]$AuthToken
    )

    # Check for the auth token header environment variable
    if ($Null -eq $AuthToken){
        Throw "No authentication token - Please call the Connect-ZenApi cmdlet first"
    }
    else{
        # Set the API endpoint, will be appended to the base API URL when invoking the rest method
        $Endpoint = "/tickets/$ticket.json"

        # Build URI from the base API URI from the auth token and the appropriate endpoint
        $Uri = $AuthToken.Uri + $Endpoint

        # Convert the string to a boolean for the API
        [bool]$NoteTypeBool = $false
        if($NoteType -eq "Public"){
            $NoteTypeBool = $true
        }
        else{
            $NoteTypeBool = $false
        }

        # Build JSON payload
        $Payload = @{
            ticket = @{
                comment = @{
                    body = $Note
                    public = $NoteTypeBool            
                }
            } 
        }| ConvertTo-Json



        try {
            Write-Verbose "Attempting web request..."
            $Req = Invoke-RestMethod -Uri $Uri -Headers $AuthToken.AuthHeaders -Method Put -Body $Payload -ErrorAction Stop
            Write-Verbose "Updated ticket $Ticket with subject `"$($req.ticket.subject)`""
        }
        catch{
            Write-Error "Error updating ticket notes: $_"
        }
    }




}

function New-ZenTicket {
    param (
        [Parameter (Mandatory=$true)]
        [string]$Subject,
        [Parameter (Mandatory=$true)]
        [ValidateSet('Low','Normal','High','Urgent')]
        [string]$Priority,
        [Parameter (Mandatory=$true)]
        [string]$Note,
        [Parameter (Mandatory=$true)]
        [ValidateSet('Public','Internal')]
        [string]$NoteType,
        [Parameter (Mandatory=$false)]
        [string]$FormId,
        [Parameter (Mandatory=$true)]
        [hashtable]$AuthToken,
        [Parameter (Mandatory=$false)]
        [switch]$ReturnTicket
    )


    # Set the API endpoint, will be appended to the base API URL when invoking the rest method
    $Endpoint = "/tickets.json"

    # Check for the auth token header environment variable
    if ($Null -eq $AuthToken){
        Throw "No authentication token - Please call the Connect-ZenApi cmdlet first"
    }
    else{
        # Convert the string to a boolean for the API
        [bool]$NoteTypeBool = $false
        if($NoteType -eq "Public"){
            $NoteTypeBool = $true
        }
        else{
            $NoteTypeBool = $false
        }

        # Build JSON payload
        $Payload = @{
            ticket = @{
                comment = @{
                    body = $Note
                    public = $NoteTypeBool         
                }
                priority = $Priority.ToLower()
                subject = $Subject
                ticket_form_id = $FormId
            } 
        }| ConvertTo-Json

        # Build URI from the base API URI from the auth token and the appropriate endpoint
        $Uri = $AuthToken.Uri + $Endpoint

        try {
            Write-Verbose "Attempting web request..."
            $Req = Invoke-RestMethod -Uri $Uri -Headers $AuthToken.AuthHeaders -Method Post -Body $Payload -ErrorAction Stop
            Write-Verbose "Created ticket $Ticket with subject `"$($req.ticket.subject)`""

            #Output the webrequest output if passthru is true
            if($ReturnTicket){
                $Req
            }
        }
        catch{
            Write-Error "Error creating ticket: $_"
        }
    }
    
}

function Get-ZenTicket{
    param (
        [Parameter (Mandatory=$true)]
        [int]$Ticket, #Ticket ID
        [Parameter (Mandatory=$true)]
        [hashtable]$AuthToken
    )

    if ($Null -eq $AuthToken){
        Throw "No authentication token - Please call the Connect-ZenApi cmdlet first"
    }
    else{


        try {
            Write-Verbose "Attempting web request..."
            $Req = Invoke-RestMethod -Uri $Uri -Headers $AuthToken.AuthHeaders -Method Get -ErrorAction Stop
            Write-Verbose "Found $Ticket with subject `"$($req.ticket.subject)`""
            Write-Output $Req
        }
        catch{
            Write-Error "Failed to get ticket: $_"
        }
    }
}


function Set-ZenTicket{
    param (
        [Parameter (Mandatory=$true)]
        [int]$Ticket, #Ticket ID
        [Parameter (Mandatory=$true)]
        [hashtable]$AuthToken,
        [Parameter (Mandatory=$false)]
        [string]$EmailCC,
        [Parameter (Mandatory=$false)]
        [string]$Subject
    )

    # Check for the auth token header environment variable
    if ($Null -eq $AuthToken){
        Throw "No authentication token - Please call the Connect-ZenApi cmdlet first"
    }
    else{
        # API endpoint for a given ticket ID
        $Endpoint = "/tickets/$Ticket.json"

        # Build URI from the base API URI from the auth token and the appropriate endpoint
        $Uri = $AuthToken.Uri + $Endpoint

        # Convert the string to a boolean for the API
        [bool]$NoteTypeBool = $false
        if($NoteType -eq "Public"){
            $NoteTypeBool = $true
        }
        else{
            $NoteTypeBool = $false
        }

        # Build JSON payload
        $Payload = @{
            ticket = @{
                comment = @{
                    body = $Note
                    public = $NoteTypeBool            
                }
            } 
        }| ConvertTo-Json
    
        try {
            Write-Verbose "Attempting web request..."
            $Req = Invoke-RestMethod -Uri $Uri -Headers $AuthToken.AuthHeaders -Body $Payload -Method Put -ErrorAction Stop
            Write-Verbose "Found $Ticket with subject `"$($req.ticket.subject)`""
            Write-Output $Req
        }
        catch{
            Write-Error "Failed to get ticket: $_"
        }
    }
}

Export-ModuleMember -Function Connect-ZenApi, New-ZenTicketNote, New-ZenTicket, Get-ZenTicket
<#

$AuthToken = Connect-ZenApi -ZendeskEmail "sa_zendeskapi@curiobrands.com" `
-ZendeskDomain "curiobrandshelpdesk.zendesk.com"   `
-KeyVaultName "KV-ZendeskAutomation-001" `
-SecretName "Zendesk-API-Token"

$Result = New-ZenTicket -Subject "Test Alert" `
-Priority "Normal" `
-Note "This is a test" `
-NoteType Internal `
-FormId 24475834900379 `
-AuthToken $AuthToken `
-ReturnTicket

#>
