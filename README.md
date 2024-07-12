# Summary

This is a custom PowerShell module for using the Zendesk API.

# Cmdlets

* Connect-ZenApi
* New-ZenTicketNote

# Example Usage
    # The Connect-ZenApi cmdlet builds a (plaintext) credential object with the basic auth header and the base API URI, for use with other cmdlets

    $AuthToken = Connect-ZenApi -ZendeskEmail "foo@bar.com" `
    -ZendeskDomain "yourtenanthere.zendesk.com"   `
    -KeyVaultName "MyKeyVault" `
    -SecretName "TopSecret"

    New-ZenTicketNote -AuthToken $AuthToken `
    -Ticket '420' `
    -Note "Hello world!" `
    -NoteType "Internal"


# API Reference
https://developer.zendesk.com/api-reference/
