Import-Module ".\environment-automation"

$InformationPreference = "Continue"
     
$sqlPassword = Read-Host -Prompt "Enter the SQL Administrator password you used in the deployment"
$resourceGroupName = "Synapse-MCW"
$uniqueId = Read-Host -Prompt "Enter the unique suffix you used in the deployment"

$subscriptionId = (Get-AzContext).Subscription.Id

$templatesPath = ".\templates"
$sqlScriptsPath = ".\sql"
$workspaceName = "asaworkspace$($uniqueId)"
$dataLakeAccountName = "asadatalake$($uniqueId)"
$sqlUserName = "asa.sql.admin"
$sqlPoolName = "SQLPool01"

$dataLakeAccountKey = List-StorageAccountKeys -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -Name $dataLakeAccountName

$params = @{
    "PASSWORD" = $sqlPassword
    "DATALAKESTORAGEKEY" = $dataLakeAccountKey
    "DATALAKESTORAGEACCOUNTNAME" = $dataLakeAccountName
}

try
{
    Execute-SQLScriptFile-SqlCmd -SQLScriptsPath $sqlScriptsPath -WorkspaceName $workspaceName -SQLPoolName $sqlPoolName -SQLUserName $sqlUserName -SQLPassword $sqlPassword -FileName "02_sqlpool01_ml" -Parameters $params
}
catch 
{
    write-host $_.exception
}
