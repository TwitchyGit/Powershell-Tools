# ADAccountsMonitor.psm1

# Top level: environment
# Second level: AD DNS domain
# Value: array of account strings DOMAIN\SamAccountName

$ConfAccountSets = @{
    DEV = @{
        'dev.domain1.local' = @(
            'DEV1\svc_app1'
            'DEV1\svc_app2'
            'DEV1\svc_batch1'
        )
        'dev.domain2.local' = @(
            'DEV2\svc_web1'
            'DEV2\svc_db1'
        )
    }
    PROD = @{
        'prod.domain1.local' = @(
            'PROD1\svc_app1'
            'PROD1\svc_app2'
        )
        'prod.domain2.local' = @(
            'PROD2\svc_batch1'
            'PROD2\svc_db1'
        )
    }
}

Export-ModuleMember -Variable ConfAccountSets
