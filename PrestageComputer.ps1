param($ComputerName,$OSName,$OSVersion,$IPAddress,$DNSServer = '.')

$ErrorActionPreference = 'Stop'

# In order for SCCM to create a System DDR it requires the following minimum information
# - Name (duh!)
# - OperationSystem Name and Version
# - DNS Name
# - An DNS entry which is resolvable to an IP (Not necessarily a host that is up though)


#$DomainController = '.'
$DomainName = 'sccm-demo.local'

# Check if already exists
$thisComputer = $null
try 
{
  $thisComputer = Get-ADComputer -Identity $ComputerName -ErrorAction 'Stop'
} catch {
  $thisComputer = $null
}

if ($thisComputer -ne $null) {
  Write-Host "$ComputerName already exists"
  exit 0
}

# Create the AD Computer Object
Write-Host "Creating AD object for $ComputerName ..."
$DNSHostName = "$($ComputerName).$($DomainName)"
$thisComputer = New-ADComputer -Name $ComputerName `
  -DNSHostname $DNSHostName -Enabled $true `
  -OperatingSystem $OSName -OperatingSystemVersion $OSVersion -Confirm:$false

Write-Host "Creating DNS Entry for $ComputerName ..."
Add-DnsServerResourceRecordA -Zone $DomainName -Name $computername -IPv4Address $IPAddress -ComputerName $DNSServer