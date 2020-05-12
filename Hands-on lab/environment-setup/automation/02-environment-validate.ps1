Remove-Module environment-automation
Import-Module "environment-automation"

$InformationPreference = "Continue"

#
# TODO: Keep all required configuration in C:\LabFiles\AzureCreds.ps1 file
. C:\LabFiles\AzureCreds.ps1

$userName = $AzureUserName                # READ FROM FILE
$password = $AzurePassword                # READ FROM FILE
$clientId = $TokenGeneratorClientId       # READ FROM FILE
$sqlPassword = $AzureSQLPassword          # READ FROM FILE

$securePassword = $password | ConvertTo-SecureString -AsPlainText -Force
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $userName, $SecurePassword

Connect-AzAccount -Credential $cred | Out-Null

$resourceGroupName = (Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "*L400*" }).ResourceGroupName
$uniqueId =  (Get-AzResourceGroup -Name $resourceGroupName).Tags["DeploymentId"]
$subscriptionId = (Get-AzContext).Subscription.Id
$tenantId = (Get-AzContext).Tenant.Id

$templatesPath = "templates"
$datasetsPath = "datasets"
$pipelinesPath = "pipelines"
$sqlScriptsPath = "sql"
$workspaceName = "asaworkspace$($uniqueId)"
$dataLakeAccountName = "asadatalake$($uniqueId)"
$blobStorageAccountName = "asastore$($uniqueId)"
$keyVaultName = "asakeyvault$($uniqueId)"
$keyVaultSQLUserSecretName = "SQL-USER-ASA"
$sqlPoolName = "SQLPool01"
$integrationRuntimeName = "AzureIntegrationRuntime01"
$sparkPoolName = "SparkPool01"
$amlWorkspaceName = "amlworkspace$($uniqueId)"


$ropcBodyCore = "client_id=$($clientId)&username=$($userName)&password=$($password)&grant_type=password"
$global:ropcBodySynapse = "$($ropcBodyCore)&scope=https://dev.azuresynapse.net/.default"
$global:ropcBodyManagement = "$($ropcBodyCore)&scope=https://management.azure.com/.default"
$global:ropcBodySynapseSQL = "$($ropcBodyCore)&scope=https://sql.azuresynapse.net/.default"

$global:synapseToken = ""
$global:synapseSQLToken = ""
$global:managementToken = ""

$global:tokenTimes = [ordered]@{
        Synapse = (Get-Date -Year 1)
        SynapseSQL = (Get-Date -Year 1)
        Management = (Get-Date -Year 1)
}

$overallStateIsValid = $true

$asaArtifacts = [ordered]@{

        "wwi02_sale_small_workload_01_asa" = @{ 
                Category = "datasets"
                Valid = $false
        }
        "wwi02_sale_small_workload_02_asa" = @{ 
                Category = "datasets"
                Valid = $false
        }
        "ASAMCW - Exercise 7 - Execute Business Analyst Queries" = @{
                Category = "pipelines"
                Valid = $false
        }
        "ASAMCW - Exercise 7 - Execute Data Analyst and CEO Queries" = @{
                Category = "pipelines"
                Valid = $false
        }
        "ASAMCW - Exercise 6 - Machine Learning" = @{
                Category = "notebooks"
                Valid = $false
        }
     
        "sqlpool01" = @{
                Category = "linkedServices"
                Valid = $false
        }      
        "sqlpool01_workload01" = @{
                Category = "linkedServices"
                Valid = $false
        }
        "sqlpool01_workload02" = @{
                Category = "linkedServices"
                Valid = $false
        }
        "$($blobStorageAccountName)" = @{
                Category = "linkedServices"
                Valid = $false
        }
        "$($dataLakeAccountName)" = @{
                Category = "linkedServices"
                Valid = $false
        }
        "$($keyVaultName)" = @{
                Category = "linkedServices"
                Valid = $false
        }
}

foreach ($asaArtifactName in $asaArtifacts.Keys) {
        try {
                Write-Information "Checking $($asaArtifactName) in $($asaArtifacts[$asaArtifactName]["Category"])"
                $result = Get-ASAObject -WorkspaceName $workspaceName -Category $asaArtifacts[$asaArtifactName]["Category"] -Name $asaArtifactName
                $asaArtifacts[$asaArtifactName]["Valid"] = $true
                Write-Information "OK"
        }
        catch { 
                Write-Warning "Not found!"
                $overallStateIsValid = $false
        }
}

# the $asaArtifacts contains the current status of the workspace


        $users = [ordered]@{
                "CEO" = @{ Valid = $false }
                "DataAnalystMiami" = @{ Valid = $false }
                "DataAnalystSanDiego" = @{ Valid = $false }
                "asa.sql.workload01" = @{ Valid = $false }
                "asa.sql.workload02" = @{ Valid = $false }               
                "$($userName)" = @{ Valid = $false }
        }

$query = @"
select name from sys.sysusers
"@
        $result = Execute-SQLQuery -WorkspaceName $workspaceName -SQLPoolName $sqlPoolName -SQLQuery $query

        foreach ($dataRow in $result.data) {
                $name = $dataRow[0]

                if ($users[$name]) {
                        Write-Information "Found user $($name)."
                        $users[$name]["Valid"] = $true
                }
        }

        foreach ($name in $users.Keys) {
                if (-not $users[$name]["Valid"]) {
                        Write-Warning "User $($name) was not found."
                        $overallStateIsValid = $false
                }
        }
}

Write-Information "Checking Spark pool $($sparkPoolName)"
$sparkPool = Get-SparkPool -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkspaceName $workspaceName -SparkPoolName $sparkPoolName
if ($sparkPool -eq $null) {
        Write-Warning "    The Spark pool $($sparkPoolName) was not found"
        $overallStateIsValid = $false
} else {
        Write-Information "OK"
}
       
Write-Information "Checking datalake account $($dataLakeAccountName)..."
$dataLakeAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $dataLakeAccountName
if ($dataLakeAccount -eq $null) {
        Write-Warning "    The datalake account $($dataLakeAccountName) was not found"
        $overallStateIsValid = $false
} else {
        Write-Information "OK"

        Write-Information "Checking data lake file system wwi-02"
        $dataLakeFileSystem = Get-AzDataLakeGen2Item -Context $dataLakeAccount.Context -FileSystem "wwi-02"
        if ($dataLakeFileSystem -eq $null) {
                Write-Warning "    The data lake file system wwi-02 was not found"
                $overallStateIsValid = $false
        } else {
                Write-Information "OK"

                $dataLakeItems = [ordered]@{
                        "sale-small" = "folder path"                        
                        "sale-small\Year=2018" = "folder path"
                        "sale-small\Year=2019" = "folder path"
                        "product-json" = "folder path"
                        "sales-small/Year=2010/Quarter=Q4/Month=12/Day=20101231/sale-small-20101231-snappy.parquet" = "file path"
                        "customer-info/customer-info.csv" = "file path"                       
                        "campaign-analytics\campaignanalytics.csv" = "file path"
                        "data-generators/generator-product/generator-product.csv" = "file path"
                }
        
                foreach ($dataLakeItemName in $dataLakeItems.Keys) {
        
                        Write-Information "Checking data lake $($dataLakeItems[$dataLakeItemName]) $($dataLakeItemName)..."
                        $dataLakeItem = Get-AzDataLakeGen2Item -Context $dataLakeAccount.Context -FileSystem "wwi-02" -Path $dataLakeItemName
                        if ($dataLakeItem -eq $null) {
                                Write-Warning "    The data lake $($dataLakeItems[$dataLakeItemName]) $($dataLakeItemName) was not found"
                                $overallStateIsValid = $false
                        } else {
                                Write-Information "OK"
                        }
        
                }  
        }      
}


if ($overallStateIsValid -eq $true) {
    Write-Information "Validation Passed"
}
else {
    Write-Warning "Validation Failed - see log output"
}


