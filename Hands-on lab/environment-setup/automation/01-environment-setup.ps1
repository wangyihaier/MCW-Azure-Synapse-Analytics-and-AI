Import-Module ".\environment-automation"

$InformationPreference = "Continue"

# select a subscription
$subs = Get-AzSubscription | Select-Object -ExpandProperty Name
if($subs.GetType().IsArray -and $subs.length -gt 1){
        $subOptions = [System.Collections.ArrayList]::new()
        for($subIdx=0; $subIdx -lt $subs.length; $subIdx++){
                $opt = New-Object System.Management.Automation.Host.ChoiceDescription "&$([char](65 + $subIdx)) $($subs[$subIdx])", "Selects the $($subs[$subIdx]) subscription."   
                $subOptions.Add($opt)
        }
        $selectedSubIdx = $host.ui.PromptForChoice('Select the desired Azure Subscription for this lab','If you have a long list, see expanded choice details by entering ?', $subOptions.ToArray(),0)
        $selectedSubName = $subs[$selectedSubIdx]
        Write-Information "Selecting the $selectedSubName subscription"
        Select-AzSubscription -SubscriptionName $selectedSubName
}

$userName = ((az ad signed-in-user show) | ConvertFrom-JSON).UserPrincipalName
$sqlPassword = Read-Host -Prompt "Enter the SQL Administrator password you used in the deployment" -AsSecureString
$sqlPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($sqlPassword))
$resourceGroupName = "Synapse-MCW"
$uniqueId = Read-Host -Prompt "Enter the unique suffix you used in the deployment"

$subscriptionId = (Get-AzContext).Subscription.Id
$global:logindomain = (Get-AzContext).Tenant.Id

$templatesPath = ".\templates"
$datasetsPath = ".\datasets"
$pipelinesPath = ".\pipelines"
$sqlScriptsPath = ".\sql"
$workspaceName = "asaworkspace$($uniqueId)"
$dataLakeAccountName = "asadatalake$($uniqueId)"
$blobStorageAccountName = "asastore$($uniqueId)"
$keyVaultName = "asakeyvault$($uniqueId)"
$keyVaultSQLUserSecretName = "SQL-USER-ASA"
$sqlPoolName = "SQLPool01"
$sqlUserName = "asa.sql.admin"
$integrationRuntimeName = "AzureIntegrationRuntime01"
$sparkPoolName = "SparkPool01"
$amlWorkspaceName = "amlworkspace$($uniqueId)"

$global:synapseToken = ""
$global:synapseSQLToken = ""
$global:managementToken = ""

$global:tokenTimes = [ordered]@{
        Synapse = (Get-Date -Year 1)
        SynapseSQL = (Get-Date -Year 1)
        Management = (Get-Date -Year 1)
}

Write-Information "Assign Ownership on Synapse Workspace"
Assign-SynapseRole -WorkspaceName $workspaceName -RoleId "6e4bf58a-b8e1-4cc3-bbf9-d73143322b78" -PrincipalId "37548b2e-e5ab-4d2b-b0da-4d812f56c30e"  # Workspace Admin
Assign-SynapseRole -WorkspaceName $workspaceName -RoleId "7af0c69a-a548-47d6-aea3-d00e69bd83aa" -PrincipalId "37548b2e-e5ab-4d2b-b0da-4d812f56c30e"  # SQL Admin
Assign-SynapseRole -WorkspaceName $workspaceName -RoleId "c3a6d2f1-a26f-4810-9b0f-591308d5cbf1" -PrincipalId "37548b2e-e5ab-4d2b-b0da-4d812f56c30e"  # Apache Spark Admin

#add the permission to the datalake to workspace
$id = (Get-AzADServicePrincipal -DisplayName $workspacename).id
New-AzRoleAssignment -Objectid $id -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue;
New-AzRoleAssignment -SignInName $username -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue;

Write-Information "Setting Key Vault Access Policy"
Set-AzKeyVaultAccessPolicy -ResourceGroupName $resourceGroupName -VaultName $keyVaultName -UserPrincipalName $userName -PermissionsToSecrets set,delete,get,list

$ws = Get-Workspace $SubscriptionId $ResourceGroupName $WorkspaceName;
$upid = $ws.identity.principalid
Set-AzKeyVaultAccessPolicy -ResourceGroupName $resourceGroupName -VaultName $keyVaultName -ObjectId $upid -PermissionsToSecrets set,delete,get,list

Write-Information "Create SQL-USER-ASA Key Vault Secret"
$secretValue = ConvertTo-SecureString $sqlPassword -AsPlainText -Force
$secret = Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $keyVaultSQLUserSecretName -SecretValue $secretValue

Write-Information "Create KeyVault linked service $($keyVaultName)"

$result = Create-KeyVaultLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $keyVaultName
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Create Integration Runtime $($integrationRuntimeName)"

$result = Create-IntegrationRuntime -TemplatesPath $templatesPath -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -Name $integrationRuntimeName -CoreCount 16 -TimeToLive 60
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Create Data Lake linked service $($dataLakeAccountName)"

$dataLakeAccountKey = List-StorageAccountKeys -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -Name $dataLakeAccountName
$result = Create-DataLakeLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $dataLakeAccountName  -Key $dataLakeAccountKey
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Create Blob Storage linked service $($blobStorageAccountName)"

$blobStorageAccountKey = List-StorageAccountKeys -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -Name $blobStorageAccountName
$result = Create-BlobStorageLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $blobStorageAccountName  -Key $blobStorageAccountKey
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Start the $($sqlPoolName) SQL pool if needed."

$result = Get-SQLPool -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -SQLPoolName $sqlPoolName
if ($result.properties.status -ne "Online") {
    Control-SQLPool -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -SQLPoolName $sqlPoolName -Action resume
    Wait-ForSQLPool -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -SQLPoolName $sqlPoolName -TargetStatus Online
}

Write-Information "Setup $($sqlPoolName)"

$params = @{
        "PASSWORD" = $sqlPassword
        "DATALAKESTORAGEKEY" = $dataLakeAccountKey
        "DATALAKESTORAGEACCOUNTNAME" = $dataLakeAccountName
}

try
{
   $result = Execute-SQLScriptFile-SqlCmd -SQLScriptsPath $sqlScriptsPath -WorkspaceName $workspaceName -SQLPoolName "master" -SQLUserName $sqlUserName -SQLPassword $sqlPassword -FileName "00_master_setup" -Parameters $params
}
catch 
{
    write-host $_.exception
}

try
{
    $result = Execute-SQLScriptFile-SqlCmd -SQLScriptsPath $sqlScriptsPath -WorkspaceName $workspaceName -SQLPoolName $sqlPoolName -SQLUserName $sqlUserName -SQLPassword $sqlPassword -FileName "01_sqlpool01_mcw" -Parameters $params
}
catch 
{
    write-host $_.exception
}


$result

Write-Information "Create linked service for SQL pool $($sqlPoolName) with user asa.sql.admin"

$linkedServiceName = $sqlPoolName.ToLower()
$result = Create-SQLPoolKeyVaultLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $linkedServiceName -DatabaseName $sqlPoolName `
                 -UserName "asa.sql.admin" -KeyVaultLinkedServiceName $keyVaultName -SecretName $keyVaultSQLUserSecretName
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Create linked service for SQL pool $($sqlPoolName) with user asa.sql.workload01"

$linkedServiceName = "$($sqlPoolName.ToLower())_workload01"
$result = Create-SQLPoolKeyVaultLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $linkedServiceName -DatabaseName $sqlPoolName `
                 -UserName "asa.sql.workload01" -KeyVaultLinkedServiceName $keyVaultName -SecretName $keyVaultSQLUserSecretName
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId

Write-Information "Create linked service for SQL pool $($sqlPoolName) with user asa.sql.workload02"

$linkedServiceName = "$($sqlPoolName.ToLower())_workload02"
$result = Create-SQLPoolKeyVaultLinkedService -TemplatesPath $templatesPath -WorkspaceName $workspaceName -Name $linkedServiceName -DatabaseName $sqlPoolName `
                 -UserName "asa.sql.workload02" -KeyVaultLinkedServiceName $keyVaultName -SecretName $keyVaultSQLUserSecretName
Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId


Write-Information "Create data sets"

$datasets = @{
        asamcw_product_asa = $sqlPoolName.ToLower()
        asamcw_product_csv = $dataLakeAccountName
        asamcw_wwi_salesmall_workload1_asa = "$($sqlPoolName.ToLower())_workload01"      
        asamcw_wwi_salesmall_workload2_asa = "$($sqlPoolName.ToLower())_workload02" 
}

foreach ($dataset in $datasets.Keys) 
{
        Write-Information "Creating dataset $($dataset)"
        $result = Create-Dataset -DatasetsPath $datasetsPath -WorkspaceName $workspaceName -Name $dataset -LinkedServiceName $datasets[$dataset]
        Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId
}

Write-Information "Create pipelines for Exercise 7"

$params = @{}
$workloadPipelines = [ordered]@{
        copy_products_pipeline = "ASAMCW - Exercise 2 - Copy Product Information"
        execute_business_analyst_queries = "ASAMCW - Exercise 7 - ExecuteBusinessAnalystQueries"
        execute_data_analyst_and_ceo_queries = "ASAMCW - Exercise 7 - ExecuteDataAnalystAndCEOQueries"
}

foreach ($pipeline in $workloadPipelines.Keys) 
{
    try
    {
        Write-Information "Creating workload pipeline $($workloadPipelines[$pipeline])"
        $result = Create-Pipeline -PipelinesPath $pipelinesPath -WorkspaceName $workspaceName -Name $workloadPipelines[$pipeline] -FileName $workloadPipelines[$pipeline] -Parameters $params
        Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId
    }
    catch
    {
        write-host $_.exception;
    }
}

Write-Information "Creating Spark notebooks..."

$notebooks = [ordered]@{
        "ASAMCW - Exercise 6 - Machine Learning" = ".\notebooks\ASAMCW - Exercise 6 - Machine Learning.ipynb"      
}

$cellParams = [ordered]@{
        "#DATALAKEACCOUNTNAME#" = $dataLakeAccountName
        "#DATALAKEACCOUNTKEY#" = $dataLakeAccountKey
        "#SQL_POOL_NAME#" = $sqlPoolName
        "#SUBSCRIPTION_ID#" = $subscriptionId
        "#RESOURCE_GROUP_NAME#" = $resourceGroupName
        "#AML_WORKSPACE_NAME#" = $amlWorkspaceName
}

foreach ($notebookName in $notebooks.Keys) 
{
        $notebookFileName = "$($notebooks[$notebookName])"
        Write-Information "Creating notebook $($notebookName) from $($notebookFileName)"
        
        $result = Create-SparkNotebook -TemplatesPath $templatesPath -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName `
                -WorkspaceName $workspaceName -SparkPoolName $sparkPoolName -Name $notebookName -NotebookFileName $notebookFileName -CellParams $cellParams
        $result = Wait-ForOperation -WorkspaceName $workspaceName -OperationId $result.operationId
        $result
}


$publicDataUrl = "https://solliancepublicdata.blob.core.windows.net/"
$dataLakeStorageUrl = "https://"+ $dataLakeAccountName + ".dfs.core.windows.net/"
$dataLakeStorageBlobUrl = "https://"+ $dataLakeAccountName + ".blob.core.windows.net/"
$dataLakeStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $dataLakeAccountName)[0].Value
$dataLakeContext = New-AzureStorageContext -StorageAccountName $dataLakeAccountName -StorageAccountKey $dataLakeStorageAccountKey
$destinationSasKey = New-AzureStorageContainerSASToken -Container "wwi-02" -Context $dataLakeContext -Permission rwdl

Write-Information "Copying single files from the public data account..."
$singleFiles = @{
        parquet_query_file = "wwi-02/sale-small/Year=2010/Quarter=Q4/Month=12/Day=20101231/sale-small-20101231-snappy.parquet"
        customer_info = "wwi-02/customer-info/customerinfo.csv"
        campaign_analytics = "wwi-02/campaign-analytics/campaignanalytics.csv"
        products = "wwi-02/data-generators/generator-product/generator-product.csv"
        model = "wwi-02/ml/onnx-hex/product_seasonality_classifier.onnx.hex"
}

foreach ($singleFile in $singleFiles.Keys) {
        $source = $publicDataUrl + $singleFiles[$singleFile]
        $destination = $dataLakeStorageBlobUrl + $singleFiles[$singleFile] + $destinationSasKey
        Write-Information "Copying file $($source) to $($destination)"
        azcopy copy $source $destination 
}

Write-Information "Copying sample sales raw data directories from the public data account..."
$dataDirectories = @{
        data2018 = "wwi-02/sale-small,wwi-02/sale-small/Year=2018/"
        data2019 = "wwi-02/sale-small,wwi-02/sale-small/Year=2019/"
}

foreach ($dataDirectory in $dataDirectories.Keys) {

        $vals = $dataDirectories[$dataDirectory].tostring().split(",");

        $source = $publicDataUrl + $vals[1];

        $path = $vals[0];

        $destination = $dataLakeStorageBlobUrl + $path + $destinationSasKey
        Write-Information "Copying directory $($source) to $($destination)"
        azcopy copy $source $destination --recursive=true
}

Write-Information "Copying sample JSON data from the repository..."
$rawData = "./rawdata/json-data"
$destination = $dataLakeStorageUrl +"wwi-02/product-json" + $destinationSasKey
azcopy copy $rawData $destination --recursive

Write-Information "Setup machine learning tables in SQL Pool"
$params = @{
    "PASSWORD" = $sqlPassword
    "DATALAKESTORAGEKEY" = $dataLakeStorageAccountKey
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

Write-Information "Environment setup has completed."