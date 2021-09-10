<#
    .DESCRIPTION
    Deployment script creating an IoT Hub, Device Provisioning Service,
    and Time Series Insights.
    Run it using the command: pwsh .\deployment.ps
#>

. ".\functions.ps1"

az login

$startTime = $(get-date)

# Allow installing extensions without prompt
az config set extension.use_dynamic_install=yes_without_prompt

# Get the details for the currently logged-in user
$principalObjectId=$(az ad signed-in-user show --query objectId --output tsv)

$resourceGroup="anomaly-detection-rg"
$location="northeurope"
$iotHub="anomaly-detection-hub"
$iotHubSku="S1"
$iotHubSharedAccessPolicy="iothubowner"
$iotHubAsaConsumerGroup="asaconsumergroup"


#----------------------------------------------------------------------------------------------------
# Create a resource group
az group create --name $resourceGroup --location $location

#----------------------------------------------------------------------------------------------------
# Create an IoT Hub
# See: https://docs.microsoft.com/en-us/azure/iot-dps/quick-setup-auto-provision#create-an-iot-hub
#      https://docs.microsoft.com/en-us/cli/azure/iot/hub?view=azure-cli-latest#az_iot_hub_create

az iot hub create `
    --name $iotHub `
    --resource-group $resourceGroup `
    --location $location `
    --sku $iotHubSku

# Create an event hub consumer group for Azure Stream Analytics input
# See: https://docs.microsoft.com/en-us/cli/azure/iot/hub/consumer-group?view=azure-cli-latest#az_iot_hub_consumer_group_create

az iot hub consumer-group create `
    --hub-name $iotHub `
    --name $iotHubAsaConsumerGroup


# Read IoT Hub connection string
$iotHubConnection=$(az iot hub connection-string show -n $iotHub --output tsv)

# Read the "iothubowner" Shared Access Policy key of the IoT Hub
$iotHubPolicySharedAccessKey=$(az iot hub policy show --hub-name $iotHub --name $iotHubSharedAccessPolicy --query primaryKey --output tsv)

# Read IoT Hub resource id
$iotHubResourceId=$(az iot hub show --name $iotHub --query id --output tsv)


#----------------------------------------------------------------------------------------------------
# Create an Azure IoT Hub device provisioning service (DPS)
# See: https://docs.microsoft.com/en-us/cli/azure/iot/dps?view=azure-cli-latest#az_iot_dps_create

$dps="anomaly-detection-dps"
$dpsSku="S1"

az iot dps create `
    --name $dps `
    --resource-group $resourceGroup `
    --location $location `
    --sku $dpsSku

az iot dps linked-hub create `
    --dps-name $dps `
    --resource-group $resourceGroup `
    --location $location `
    --connection-string $iotHubConnection

#----------------------------------------------------------------------------------------------------
# Create DPS Enrollment Group
# See: https://docs.microsoft.com/en-us/cli/azure/iot/dps/enrollment-group?view=azure-cli-latest#az_iot_dps_enrollment_group_create

# Create primary and secondary keys
$primaryKey=Get-RandomKey
$secondaryKey=Get-RandomKey

# DPS Enrollment Group name
$enrollmentId="AnomalyDetection"

az iot dps enrollment-group create `
    -g $resourceGroup `
    --dps-name $dps `
    --enrollment-id $enrollmentId `
    --primary-key $primaryKey `
    --secondary-key $secondaryKey

# Read DPS ID Scope
$idScope=$(az iot dps show --name $dps --resource-group $resourceGroup --query properties.idScope --output tsv)


#----------------------------------------------------------------------------------------------------
# Create an Azure Time Series Insights Gen2
# See: https://docs.microsoft.com/en-us/azure/time-series-insights/how-to-create-environment-using-cli

# Create an Azure storage account for tsi environment's cold store

$randomString=Get-RandomLowercaseAndNumbers 16
$tsiStorage="storage"+$randomString

az storage account create -g $resourceGroup -n $tsiStorage --https-only
$storageKey=$(az storage account keys list -g $resourceGroup -n $tsiStorage --query [0].value --output tsv)

#----------------------------------------------------------------------------------------------------
# Create the Azure Time Series Insights Environment
# See: https://docs.microsoft.com/en-us/cli/azure/tsi/environment/gen2?view=azure-cli-latest#az_tsi_environment_gen2_create

$tsiEnvName="time-series-insights"
$tsiPropertyId="iothub-connection-device-id"
$tsiSkuName="L1"

az tsi environment gen2 create `
    --name $tsiEnvName `
    --location $location `
    --resource-group $resourceGroup `
    --sku name=$tsiSkuName capacity=1 `
    --time-series-id-properties name=$tsiPropertyId type=String `
    --warm-store-configuration data-retention=P7D `
    --storage-configuration account-name=$tsiStorage management-key=$storageKey

#----------------------------------------------------------------------------------------------------
# Create an event source under the Azure Time Series Insights Environment
# See: https://docs.microsoft.com/en-us/cli/azure/tsi/event-source/iothub?view=azure-cli-latest

$eventSourceName="ioteventsource"
$consumerGroupName="`$Default"

az tsi event-source iothub create `
    -g $resourceGroup `
    --environment-name $tsiEnvName `
    --name $eventSourceName `
    --consumer-group-name $consumerGroupName `
    --iot-hub-name $iotHub `
    --location $location `
    --key-name $iotHubSharedAccessPolicy `
    --shared-access-key $iotHubPolicySharedAccessKey `
    --event-source-resource-id $iotHubResourceId

#----------------------------------------------------------------------------------------------------
# Create a data access policy granting access to the signed in user
# See: https://docs.microsoft.com/en-us/cli/azure/tsi/access-policy?view=azure-cli-latest

az tsi access-policy create `
    --name "roleAssignment" `
    --environment-name $tsiEnvName `
    --description "TSI owner" `
    --principal-object-id $principalObjectId `
    --roles Reader Contributor `
    --resource-group $resourceGroup


#----------------------------------------------------------------------------------------------------
# Create a Stream Analytics job
# See: https://docs.microsoft.com/en-us/cli/azure/stream-analytics/job?view=azure-cli-latest#az_stream_analytics_job_create

$streamJob="streamjob"

az stream-analytics job create `
    --name $streamJob `
    --resource-group $resourceGroup `
    --location $location 

#----------------------------------------------------------------------------------------------------
# Create an input for the Stream Analytics job
# See: https://docs.microsoft.com/en-us/cli/azure/stream-analytics/input?view=azure-cli-latest#az_stream_analytics_input_create

$datasource=@"
{
    'type': 'Microsoft.Devices/IotHubs',
    'properties': {
        'iotHubNamespace': \"$iotHub\",
        'sharedAccessPolicyName': \"$iotHubSharedAccessPolicy\",
        'sharedAccessPolicyKey': \"$iotHubPolicySharedAccessKey\",
        'consumerGroupName': \"$iotHubAsaConsumerGroup\",
        'endpoint': 'messages/events'
        }
}
"@.Replace("'",'\"').Replace("`n",'')

$serialization=@"
{
    'type': 'Json',
    'properties': {
        'encoding': 'UTF8'
    }
}
"@.Replace("'",'\"').Replace("`n",'')

az stream-analytics input create `
    --resource-group $resourceGroup `
    --job-name $streamJob `
    --name input `
    --type Stream `
    --datasource $datasource `
    --serialization $serialization

#---------------------------------------------------------------------------------------------------
# Create an output for the Stream Analytics job
# See: https://docs.microsoft.com/en-us/cli/azure/stream-analytics/output?view=azure-cli-latest#az_stream_analytics_output_create

# Create an Event Hub as the output
# See: https://docs.microsoft.com/en-us/cli/azure/eventhubs/namespace?view=azure-cli-latest#az_eventhubs_namespace_create
#      https://docs.microsoft.com/en-us/cli/azure/eventhubs/eventhub?view=azure-cli-latest#az_eventhubs_eventhub_create
#      https://docs.microsoft.com/en-us/cli/azure/eventhubs/namespace/authorization-rule?view=azure-cli-latest#az_eventhubs_namespace_authorization_rule_create
#      https://docs.microsoft.com/en-us/cli/azure/stream-analytics/job?view=azure-cli-latest#az_stream_analytics_job_create

$randomString=Get-RandomLowercaseAndNumbers 16
$eventHubsNamespace="ehns"+$randomString
$eventHubName="asaeventhub"
$eventHubNameForFunc="faeventhub"
$eventHubSharedAccessPolicy="eventHubSharedAccessPolicy"

az eventhubs namespace create `
    --resource-group $resourceGroup `
    --name $eventHubsNamespace `
    --location $location `
    --sku Standard

# Create two event hubs for two outputs: asaeventhub for stream analytics and faeventhub for azure functions

az eventhubs eventhub create `
    --resource-group $resourceGroup `
    --namespace-name $eventHubsNamespace `
    --name $eventHubName `
    --message-retention 1

az eventhubs eventhub create `
    --resource-group $resourceGroup `
    --namespace-name $eventHubsNamespace `
    --name $eventHubNameForFunc `
    --message-retention 1

az eventhubs namespace authorization-rule create `
    --resource-group $resourceGroup `
    --namespace-name $eventHubsNamespace `
    --name $eventHubSharedAccessPolicy `
    --rights Manage Send Listen

az eventhubs namespace authorization-rule show `
    --resource-group $resourceGroup `
    --namespace-name $eventHubsNamespace `
    --name $eventHubSharedAccessPolicy

$eventHubSharedAccessPolicyKey=$(az eventhubs namespace authorization-rule keys list --resource-group $resourceGroup --namespace-name $eventHubsNamespace --name $eventHubSharedAccessPolicy --query primaryKey --output tsv)

# Read Event Hub resource id
$eventHubResourceId=$(az eventhubs eventhub show --resource-group $resourceGroup --namespace-name $eventHubsNamespace --name $eventHubName --query id --output tsv)

$datasource1=@"
{
    'type': 'Microsoft.ServiceBus/EventHub',
    'properties': {
        'serviceBusNamespace': \"$eventHubsNamespace\",
        'sharedAccessPolicyName': \"$eventHubSharedAccessPolicy\",
        'sharedAccessPolicyKey': \"$eventHubSharedAccessPolicyKey\",
        'eventHubName': \"$eventHubName\"
        }
}
"@.Replace("'",'\"').Replace("`n",'')

$datasource2=@"
{
    'type': 'Microsoft.ServiceBus/EventHub',
    'properties': {
        'serviceBusNamespace': \"$eventHubsNamespace\",
        'sharedAccessPolicyName': \"$eventHubSharedAccessPolicy\",
        'sharedAccessPolicyKey': \"$eventHubSharedAccessPolicyKey\",
        'eventHubName': \"$eventHubNameForFunc\"
        }
}
"@.Replace("'",'\"').Replace("`n",'')

$serialization=@"
{
    'type': 'Json',
    'properties': {
        'encoding': 'UTF8',
        'format': 'Array'
    }
}
"@.Replace("'",'\"').Replace("`n",'')

# Create two outputs

az stream-analytics output create `
    --resource-group $resourceGroup `
    --job-name $streamJob `
    --name output1 `
    --datasource $datasource1 `
    --serialization $serialization

az stream-analytics output create `
    --resource-group $resourceGroup `
    --job-name $streamJob `
    --name output2 `
    --datasource $datasource2 `
    --serialization $serialization

# Create a query
# See: https://docs.microsoft.com/en-us/cli/azure/stream-analytics/transformation?view=azure-cli-latest#az_stream_analytics_transformation_create

$query=@"
WITH AnomalyDetectionStep AS
(
    SELECT
        IoTHub.ConnectionDeviceId AS id,
        EventEnqueuedUtcTime AS time,
        CAST(temperature AS float) AS temp,
        AnomalyDetection_SpikeAndDip(CAST(temperature AS float), 94, 240, 'spikesanddips')
            OVER(PARTITION BY id LIMIT DURATION(second, 1200)) AS SpikeAndDipScores
    FROM input
    WHERE temperature IS NOT NULL
)
SELECT
    id AS 'iothub-connection-device-id',
    time,
    CAST(GetRecordPropertyValue(SpikeAndDipScores, 'IsAnomaly') AS bigint) as temperature_anomaly,
    CAST(GetRecordPropertyValue(SpikeAndDipScores, 'Score') AS float) AS temperature_anomaly_score
INTO output1
FROM AnomalyDetectionStep;

SELECT 
    id AS 'device-id',
    time,
    temp as temperature,
    CAST(GetRecordPropertyValue(SpikeAndDipScores, 'IsAnomaly') AS bigint) as temperature_anomaly,
    CAST(GetRecordPropertyValue(SpikeAndDipScores, 'Score') AS float) AS temperature_anomaly_score,
    ISFIRST(mi, 1) OVER (PARTITION BY id WHEN CAST(GetRecordPropertyValue(SpikeAndDipScores, 'IsAnomaly') AS bigint) = 1) as first 
INTO output2
FROM AnomalyDetectionStep
WHERE CAST(GetRecordPropertyValue(SpikeAndDipScores, 'IsAnomaly') AS bigint) = 1
"@
$query=$query -replace "`n"," "
$query=$query -replace "\s+"," "

az stream-analytics transformation create `
    --resource-group $resourceGroup `
    --job-name $streamJob `
    --name query `
    --transformation-query $query

# Start a streaming job
az stream-analytics job start --resource-group $resourceGroup --name $streamJob


#----------------------------------------------------------------------------------------------------
# Add an Event Hub as an event source under the Azure Time Series Insights Environment
# See: https://docs.microsoft.com/en-us/cli/azure/tsi/event-source/eventhub?view=azure-cli-latest

$eventSourceName="eventhubeventsource"
$consumerGroupName="`$Default"

az tsi event-source eventhub create `
    --resource-group $resourceGroup `
    --environment-name $tsiEnvName `
    --consumer-group-name $consumerGroupName `
    --namespace $eventHubsNamespace `
    --event-hub-name $eventHubName `
    --event-source-name $eventSourceName `
    --event-source-resource-id $eventHubResourceId `
    --location $location `
    --key-name $eventHubSharedAccessPolicy `
    --shared-access-key $eventHubSharedAccessPolicyKey


$elapsedTime = $(get-date) - $startTime
$totalTime = "{0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks)

"`r`n=================================================="
"`r`nTotal elapsed time: " + $totalTime + "`r`n"
"`r`nSave the following properties:"
"`r`nDPS ID Scope: " + $idScope
"DPS Primary Key: " + $primaryKey + "`r`n"