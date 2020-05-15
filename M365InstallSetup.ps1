#Create Collections
$CreateDeviceCollectionAvailable = $true
$CreateDeviceCollectionRequired = $true
$CreateUserCollectionAvailable = $true
#Create Deployments
$CreateDeviceCollectionAvailableDeployments = $true
$CreateDeviceCollectionRequiredDeployments = $true
$CreateUserCollectionAvailableDeployments = $true

#Limiting Collections
$DeviceLimitingCollection = "All Desktop and Server Clients"
$UserLimitingCollection = "All Users and User Groups"

$Apps = @(
    @{CollectionName = 'Microsoft 365 Access'}
    @{CollectionName = 'Microsoft 365 Office - Monthly Enterprise Channel'}
    @{CollectionName = 'Microsoft 365 Office - Semi-Annual Enterprise Channel'}
    @{CollectionName = 'Microsoft 365 Office - Semi-Annual Enterprise Channel Preview'}
    @{CollectionName = 'Microsoft 365 Project Professional 2019'}
    @{CollectionName = 'Microsoft 365 Project Standard 2019'}
    @{CollectionName = 'Microsoft 365 Visio Professional 2019'}
    @{CollectionName = 'Microsoft 365 Visio Standard 2019'}
)

$DeviceCollectionTableAvailable = @(
    @{CollectionName = 'Microsoft 365 Access - Available'}
    @{CollectionName = 'Microsoft 365 Office - Monthly Enterprise Channel - Available'}
    @{CollectionName = 'Microsoft 365 Office - Semi-Annual Enterprise Channel - Available'}
    @{CollectionName = 'Microsoft 365 Office - Semi-Annual Enterprise Channel Preview - Available'}
    @{CollectionName = 'Microsoft 365 Project Professional 2019 - Available'}
    @{CollectionName = 'Microsoft 365 Project Standard 2019 - Available'}
    @{CollectionName = 'Microsoft 365 Visio Professional 2019 - Available'}
    @{CollectionName = 'Microsoft 365 Visio Standard 2019 - Available'}
)

$DeviceCollectionTableRequired = @(
    @{CollectionName = 'Microsoft 365 Access - Required'}
    @{CollectionName = 'Microsoft 365 Office - Monthly Enterprise Channel - Required'}
    @{CollectionName = 'Microsoft 365 Office - Semi-Annual Enterprise Channel - Required'}
    @{CollectionName = 'Microsoft 365 Office - Semi-Annual Enterprise Channel Preview - Required'}
    @{CollectionName = 'Microsoft 365 Project Professional 2019 - Required'}
    @{CollectionName = 'Microsoft 365 Project Standard 2019 - Required'}
    @{CollectionName = 'Microsoft 365 Visio Professional 2019 - Required'}
    @{CollectionName = 'Microsoft 365 Visio Standard 2019 - Required'}
)

$UserCollectionTable = @(
    @{CollectionName = 'Microsoft 365 Access - User'}
    @{CollectionName = 'Microsoft 365 Office - Monthly Enterprise Channel - User'}
    @{CollectionName = 'Microsoft 365 Office - Semi-Annual Enterprise Channel - User'}
    @{CollectionName = 'Microsoft 365 Office - Semi-Annual Enterprise Channel Preview - User'}
    @{CollectionName = 'Microsoft 365 Project Professional 2019 - User'}
    @{CollectionName = 'Microsoft 365 Project Standard 2019 - User'}
    @{CollectionName = 'Microsoft 365 Visio Professional 2019 - User'}
    @{CollectionName = 'Microsoft 365 Visio Standard 2019 - User'}
)

If ($CreateDeviceCollectionAvailable) {
    foreach ($Collection in $DeviceCollectionTableAvailable)
        {
        New-CMCollection -CollectionType Device -LimitingCollectionName $DeviceLimitingCollection -Name $Collection.CollectionName -RefreshType None
        }
    }

If ($CreateDeviceCollectionRequired) {
    foreach ($Collection in $DeviceCollectionTableRequired)
        {
        New-CMCollection -CollectionType Device -LimitingCollectionName $DeviceLimitingCollection -Name $Collection.CollectionName -RefreshType None
        }
    }

If ($CreateUserCollectionAvailable) {
    foreach ($Collection in $UserCollectionTable)
        {
        New-CMCollection -CollectionType Device -LimitingCollectionName $DeviceLimitingCollection -Name $Collection.CollectionName -RefreshType None
        }
    }


New-CMApplicationDeployment -Name "Microsoft 365 Access" -CollectionName "Microsoft 365 Access - User" -DeployPurpose Available -UserNotification DisplaySoftwareCenterOnly
