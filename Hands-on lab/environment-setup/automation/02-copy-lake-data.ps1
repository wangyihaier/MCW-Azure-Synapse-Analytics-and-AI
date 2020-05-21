cd "C:\github\codingbandit\MCW-Azure-Synapse-Analytics-end-to-end-solution\Hands-on lab\environment-setup\automation"

Install-Module -Name Az -AllowClobber
Install-Module -Name Azure.Storage -AllowClobber

$InformationPreference = "Continue"

# TODO: Keep all required configuration in C:\LabFiles\AzureCreds.ps1 file
. C:\LabFiles\AzureCreds.ps1

$userName = $AzureUserName                # READ FROM FILE
$password = $AzurePassword                # READ FROM FILE
$clientId = $TokenGeneratorClientId       # READ FROM FILE
$sqlPassword = $AzureSQLPassword          # READ FROM FILE
$resourceGroupName = $AzureResourceGroupName #READ FROM FILE
$uniqueId = $UniqueSuffix                 #READ FROM FILE

$securePassword = $password | ConvertTo-SecureString -AsPlainText -Force
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $userName, $SecurePassword

Connect-AzAccount -Credential $cred | Out-Null

$dataLakeAccountName = "asadatalake$($uniqueId)"

$publicDataUrl = "https://solliancepublicdata.blob.core.windows.net/"
$dataLakeStorageUrl = "https://"+ $dataLakeAccountName + ".dfs.core.windows.net/"
$dataLakeStorageBlobUrl = "https://"+ $dataLakeAccountName + ".blob.core.windows.net/"

$dataLakeStorageAccountKey = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $dataLakeAccountName)[0].Value
$dataLakeContext = New-AzureStorageContext -StorageAccountName $dataLakeAccountName -StorageAccountKey $dataLakeStorageAccountKey
$destinationSasKey = New-AzureStorageContainerSASToken -Container "wwi-02" -Context $dataLakeContext -Permission rwdl

$azCopyLink = (curl https://aka.ms/downloadazcopy-v10-windows -MaximumRedirection 0 -ErrorAction silentlycontinue).headers.location
Invoke-WebRequest $azCopyLink -OutFile "C:\LabFiles\azCopy.zip"
Expand-Archive "C:\LabFiles\azCopy.zip" -DestinationPath "C:\LabFiles" -Force

$azCopyCommand = (Get-ChildItem -Path C:\LabFiles -Recurse azcopy.exe).Directory.FullName
$Env:Path += ";"+ $azCopyCommand

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

$rawData = "./rawdata/json-data"
$destination = $dataLakeStorageUrl +"wwi-02/product-json" + $destinationSasKey
azcopy copy $rawData $destination --recursive

