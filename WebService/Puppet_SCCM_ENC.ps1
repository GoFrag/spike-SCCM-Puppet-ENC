[cmdletBinding(SupportsShouldProcess=$false,ConfirmImpact='Low')]
param(
  [Parameter(Mandatory=$false,ValueFromPipeline=$true)]
  $HTTPEndPoint = 'http://localhost:8080/'
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# SCCM Database Settings
$DatabaseServer = '10.32.175.90'
$DatabaseName = 'CM_CEN'
$DatabaseUsername = 'sa'
$DatabasePassword = 'Puppet01!'
# SCCM Collection Settings
$EnvironmentCollectionPrefix = 'Puppet::Environment::'
$RoleCollectionPrefix = 'Puppet::Role::'
$ProfileCollectionPrefix = 'Puppet::Profile::'

function Get-MSSQLQuery {
  [cmdletBinding(SupportsShouldProcess=$false,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [Alias("Connection")]
    [object]$ConnectionObject,

    [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
    [string]$Query,
  
    [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
    [Alias("Timeout")]
    [int]$QueryTimeout = 120
  )
  Process {
    if ($ConnectionObject.State -ne "Closed")
    {
      Throw "Connection is not a closed state"
      return $null
	  }
    $ConnectionObject.Open()
    $cmd = new-object system.Data.SqlClient.SqlCommand($Query,$ConnectionObject)
    $cmd.CommandTimeout = $QueryTimeout
    $ds = New-Object system.Data.DataSet
    $da = New-Object system.Data.SqlClient.SqlDataAdapter($cmd)
    [void] $da.fill($ds)
    $ConnectionObject.Close()
    $ds.Tables    
  }
}
function Get-MSSQLConnection {
  [cmdletBinding(SupportsShouldProcess=$false,ConfirmImpact='Low')]
  param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
    [Alias("Server")]
    [string]$ServerInstance,

    [Parameter(Mandatory=$true,ValueFromPipeline=$false)]
    [string]$Database,

    [Parameter(ParameterSetName="IntegratedSecurity",Mandatory=$true,ValueFromPipeline=$false)]
    [switch]$IntegratedSecurity,
  
    [Parameter(ParameterSetName="SQLSecurity",Mandatory=$true,ValueFromPipeline=$false)]
    [string]$Username,
    [Parameter(ParameterSetName="SQLSecurity",Mandatory=$true,ValueFromPipeline=$false)]
    [string]$Password,
  
    [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
    [switch]$OpenConnection = $false,

    [Parameter(Mandatory=$false,ValueFromPipeline=$false)]
    [Alias("Timeout")]
    [int]$ConnectionTimeout = 30
  )
  Process {
    $conn = new-object System.Data.SqlClient.SQLConnection
    $ConnectionString = ""
    
    switch ($PsCmdlet.ParameterSetName)
    {
      "IntegratedSecurity" { $ConnectionString = "Server={0};Database={1};Integrated Security=SSPI;Connect Timeout={2}" -f $ServerInstance,$Database,$ConnectionTimeout; break; }
      "SQLSecurity"        { $ConnectionString = "Server={0};Database={1};User Id={2};Password={3};Connect Timeout={4}" -f $ServerInstance,$Database,$Username,$Password,$ConnectionTimeout; break; }
      default { Throw "Unknown ParameterSet"; return $null; }
    }
    if ($ConnectionString -ne "")
    {
      $conn.ConnectionString = $ConnectionString
      if ($OpenConnection) { $conn.Open() }
      
      $conn
    }
    else
    {
      Throw "Bad connection string"
      return $null;
	}
  }  
}

function Confirm-DBConnectivity() {
  try {
    $sqlConn = Get-MSSQLConnection -ServerInstance $DatabaseServer `
        -Database $DatabaseName -Username $DatabaseUsername -Password $DatabasePassword
    
    $dbQuery = Get-MSSQLQuery -ConnectionObject $sqlConn -Query "SELECT TOP 1 ResourceID FROM v_RA_System_ResourceNames"
    return $true
  }
  catch [System.Exception] {
     Write-Verbose $_
     return $false 
  }
}

function Get-NodeResponse($NodeName) {
  try
  {
    Write-Verbose "Querying $NodeName ..."
    $sqlConn = Get-MSSQLConnection -ServerInstance $DatabaseServer `
        -Database $DatabaseName -Username $DatabaseUsername -Password $DatabasePassword
    
    # Get the list of all collections for this node...
    $query = "SELECT" + `
             " v_FullCollectionMembership.CollectionID As 'CollectionID'," + `
             " v_Collection.Name As 'CollectionName'" + `
             " FROM v_FullCollectionMembership " + `
             " JOIN v_RA_System_ResourceNames on v_FullCollectionMembership.ResourceID = v_RA_System_ResourceNames.ResourceID" + ` 
             " JOIN v_Collection on v_FullCollectionMembership.CollectionID = v_Collection.CollectionID " + `
             " WHERE v_RA_System_ResourceNames.Resource_Names0 like '$($NodeName)'"
    
    $nodeEnv = ''
    $nodeProfiles = @{}
    $nodeRoles = @{}
    
    $dbResult = Get-MSSQLQuery -ConnectionObject $sqlConn -Query $query

    $dbResult.Rows | % {
      $collID = $_.CollectionID.ToString()
      $collName = $_.CollectionName.ToString()
      
      # Environment type collection
      if ($collName.StartsWith($EnvironmentCollectionPrefix)) {
        Write-Verbose "Found Environment collection $collName"
        $nodeEnv = $collName.SubString($EnvironmentCollectionPrefix.Length)
      }
      # Role type collection
      if ($collName.StartsWith($RoleCollectionPrefix)) {
        Write-Verbose "Found Role collection $collName"
        $nodeRoles.Add($collID,$collName)
      }
      # Profile type collection
      if ($collName.StartsWith($ProfileCollectionPrefix)) {
        Write-Verbose "Found Profile collection $collName"
        $nodeProfiles.Add($collID,$collName)
      }
    }
    
    if ($nodeEnv -eq '') {
      Write-Verbose "Unable to find any environments"
      return ""
    }
    
    $response = "---`nclasses:`n"
    
    $response += "environment: $nodeEnv`n"
  
    Write-Output $response  
  # ---
  # classes:
  #     common:
  #     puppet:
  #     ntp:
  #         ntpserver: 0.pool.ntp.org
  #     aptsetup:
  #         additional_apt_repos:
  #             - deb localrepo.example.com/ubuntu lucid production
  #             - deb localrepo.example.com/ubuntu lucid vendor
  # parameters:
  #     ntp_servers:
  #         - 0.pool.ntp.org
  #         - ntp.example.com
  #     mail_server: mail.example.com
  #     iburst: true
  # environment: production
   
  }
  catch [System.Exception] {
    Write-Verbose "ERROR: $($_)"
    return ""
  }
}

If (-not (Confirm-DBConnectivity)) {
  throw "Error while connecting to the Database"
}

#Write-Host "Result: $(Get-NodeResponse -NodeName 'WINDOWS001.sccm-demo.local')" -ForegroundColor Cyan

#throw "exiting"

$url = $HTTPEndPoint
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($url)
$listener.Start()

Write-Host "Listening at $url..."

while ($listener.IsListening)
{
    $context = $listener.GetContext()
    $requestUrl = $context.Request.Url
    $response = $context.Response

    Write-Verbose "> $requestUrl"

    $localPath = $requestUrl.LocalPath
    if ($localPath -eq '/kill') { $listener.Close(); break; }
    
    if ($localPath.StartsWith('/')) {
      $computerName = $localPath.SubString(1)
      
      # TODO Add simple Computername verification
      
      $content = (Get-NodeResponse -NodeName $computerName)
      $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
      $response.ContentLength64 = $buffer.Length
      $response.OutputStream.Write($buffer, 0, $buffer.Length)
    } else {
      $response.StatusCode = 404
    }
    
    $response.Close()

    $responseStatus = $response.StatusCode
    Write-Verbose "< $responseStatus"
}