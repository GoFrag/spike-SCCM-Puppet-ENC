# The SCCM Module is not in the usual Autoload location
Import-Module 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1'

# Set the location to the SCCM Site of this server
$sccmSite = (Get-PSDrive | ? { $_.Provider -like '*CMSite'} | Select -First 1).Name + ':'
Set-Location -Path $sccmSite

$puppetenc = (@"
{
  "config_mgr": {
    "environments_folder": "Puppet ENC\\Puppet Environments",
    "roles_folder": "Puppet ENC\\Puppet Roles",
    "profiles_folder": "Puppet ENC\\Puppet Profiles",
    "root_limiting_collection": "All Systems",

    "environments_collection_prefix": "Puppet::Environment::",
    "roles_collection_prefix": "Puppet::Role::",
    "profiles_collection_prefix": "Puppet::Profile::"
  },
  
  "environments": [ "production","test" ],
  
  "roles": [
    {
      "name": "QueryServer",
      "profiles" : [ "IISWebServer","ConsulAgent" ]
    },
    {
      "name": "CommandServer",
      "profiles" : [ "IISWebServer","ConsulAgent" ]
    },
    {
      "name": "EventStoreServer",
      "profiles" : [ "EventStoreService","ConsulAgent" ]
    },
    {
      "name": "ConsulMaster",
      "profiles" : [ "ConsulService" ]
    },
    {
      "name": "QueryServerLoadBalancer",
      "profiles" : [ "HAProxyService","ConsulAgent" ]
    },
    {
      "name": "CommandServerLoadBalancer",
      "profiles" : [ "HAProxyService","ConsulAgent" ]
    }
  ],
  
  "profiles": [
    {
      "name": "IISWebServer",
      "modules": [ ]
    },
    {
      "name": "ConsulAgent",
      "modules": [ ]
    },
    {
      "name": "ConsulService",
      "modules": [ ]
    },
    {
      "name": "EventStoreService",
      "modules": [ ]
    },
    {
      "name": "HAProxyService",
      "modules": [ ]
    }
  ]
}
"@ | ConvertFrom-JSON -ErrorAction Stop)

#+++++++++++++++++ DO STUFF!!

Function New-RandomSchedule()
{
  "01/01/2000 $((Get-Random -Min 0 -Max 23).ToString('00')):$((Get-Random -Min 0 -Max 59).ToString('00')):00"
}

Write-Host "Processing Collections..."

# Create the environments
$puppetenc.environments | % {
  $EnvName = $_
  $CollectionName = "$($puppetenc.config_mgr.environments_collection_prefix)$EnvName"
  
  $thisColl = Get-CMDeviceCollection -Name $CollectionName
  if ($thisColl -eq $null) {
    Write-Host "Creating collection $CollectionName ..."

    $Schedule = New-CMSchedule -Start (New-RandomSchedule) -RecurInterval Days -RecurCount 1    
    $thisColl = New-CMDeviceCollection -Name $CollectionName -LimitingCollectionName $puppetenc.config_mgr.root_limiting_collection -RefreshType Periodic -RefreshSchedule $Schedule
    
    Move-CMObject -InputObject $thisColl -FolderPath "$sccmSite\DeviceCollection\$($puppetenc.config_mgr.environments_folder)" | Out-Null    
  }
}

# Create the roles first
$puppetenc.roles | % {
  $Role = $_.name
  $CollectionName = "$($puppetenc.config_mgr.roles_collection_prefix)$Role"
  
  $thisColl = Get-CMDeviceCollection -Name $CollectionName
  if ($thisColl -eq $null) {
    Write-Host "Creating collection $CollectionName ..."

    $Schedule = New-CMSchedule -Start (New-RandomSchedule) -RecurInterval Days -RecurCount 1    
    $thisColl = New-CMDeviceCollection -Name $CollectionName -LimitingCollectionName $puppetenc.config_mgr.root_limiting_collection -RefreshType Periodic -RefreshSchedule $Schedule
    
    Move-CMObject -InputObject $thisColl -FolderPath "$sccmSite\DeviceCollection\$($puppetenc.config_mgr.roles_folder)" | Out-Null    
  }
}

# Create the profiles second
$puppetenc.profiles | % {
  $PupProfile = $_.name
  $CollectionName = "$($puppetenc.config_mgr.profiles_collection_prefix)$PupProfile"
  
  $thisColl = Get-CMDeviceCollection -Name $CollectionName
  if ($thisColl -eq $null) {
    Write-Host "Creating collection $CollectionName ..."

    $Schedule = New-CMSchedule -Start (New-RandomSchedule) -RecurInterval Days -RecurCount 1    
    $thisColl = New-CMDeviceCollection -Name $CollectionName -LimitingCollectionName $puppetenc.config_mgr.root_limiting_collection -RefreshType Periodic -RefreshSchedule $Schedule
    
    Move-CMObject -InputObject $thisColl -FolderPath "$sccmSite\DeviceCollection\$($puppetenc.config_mgr.profiles_folder)" | Out-Null    
  }
}

Write-Host "Processing Collection Memberships..."
# Associate profiles to roles
$puppetenc.roles | % {
  $Role = $_.name
  $RoleCollectionName = "$($puppetenc.config_mgr.roles_collection_prefix)$Role"
  
  $roleColl = Get-CMDeviceCollection -Name $CollectionName
  if ($roleColl -eq $null) { throw "Missing Role"}

  $_.profiles | % { 
    $PupProfile = $_
    $ProfileCollectionName = "$($puppetenc.config_mgr.profiles_collection_prefix)$PupProfile"

    $includeRule = Get-CMDeviceCollectionIncludeMembershipRule -CollectionName $ProfileCollectionName -IncludeCollectionName $RoleCollectionName

    if ($includeRule -eq $null) {
      Write-Host "Adding $Role to $PupProfile"
      Add-CMDeviceCollectionIncludeMembershipRule -CollectionName $ProfileCollectionName -IncludeCollectionName $RoleCollectionName | Out-Null
    }
  }
}

