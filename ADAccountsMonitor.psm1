# ADAccountsMonitor.psm1
# $Environment is set before import, or inside this module
# For example:
# $Environment = 'DEV'

if ($Environment -match 'DEV') {
    $AccountList = @{
        'DOMAIN1' = @('account1','account2')
        'DOMAIN2' = @('account1','account2')
    }
} elseif ($Environment -match 'PROD') {
    $AccountList = @{
        'DOMAIN1' = @('account1','account2')
        'DOMAIN2' = @('account1','account2')
    }
}

Export-ModuleMember -Variable Environment,AccountList
