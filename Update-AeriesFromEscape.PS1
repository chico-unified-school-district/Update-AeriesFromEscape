<#
.SYNOPSIS
Add Relevant Employees to Aeries from Escape
.DESCRIPTION
This Script Queries the Escape database for Employees that fit the criteria ('CUTA','CUMA',or 'CSEA' members) for Aeries access
and adds them to the Aeries UNG table in the format: Domain\Username
.EXAMPLE
Update-AeriesFromEscape.PS1 -DC $dc -ADCred $adCred -OU 'OU=Employees,OU=Users,DC=OurDistrict,DC=org' -SISServer SISServer -SISData SISDB -SISCred $SISCred `
 -EscapeServer EscServer -EscapeData EscDB -EscapeCred $EscapeCred
.EXAMPLE
Update-AeriesFromEscape.PS1 -DC $dc -ADCred $adCred -OU 'OU=Employees,OU=Users,DC=OurDistrict,DC=org' -SISServer SISServer -SISData SISDB -SISCred $SISCred `
 -EscapeServer EscServer -EscapeData EscDB -EscapeCred $EscapeCred -WhatIf -Verbose
.INPUTS
.OUTPUTS
.NOTES
$AeriesQuery = "SELECT DISTINCT * FROM UGN WHERE UTY = `'adteacher`' OR  UTY = `'aduser`' ORDER BY SID"
$AeriesQuery = "SELECT * FROM UGN WHERE UTY = `'adteacher`' OR  UTY = `'aduser`' ORDER BY SID"
.LINK
# Requires -Version 5.0 ? Does it? Not Really.
#>
[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)]
 [Alias('DC')]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$DomainController,
 # PSSession to Domain Controller and Use Active Directory CMDLETS
 [Parameter(Mandatory = $True)]
 [Alias('ADCred')]
 [System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)]
 [Alias('OU')]
 [string]$StaffOrgUnit,
 # Student Information Server
 [Parameter(Mandatory = $true)]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$SISServer,
 [Parameter(Mandatory = $true)]
 [string]$SISDatabase,
 [Parameter(Mandatory = $true)]
 [System.Management.Automation.PSCredential]$SISCredential,
 # Escape Employee Server
 [Parameter(Mandatory = $true)]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$EscapeServer,
 [Parameter(Mandatory = $true)]
 [string]$EscapeDatabase,
 [Parameter(Mandatory = $true)]
 [System.Management.Automation.PSCredential]$EscapeCredential,
 # Run a 'Whatif' on commands - no data will be changed
 [Alias('wi')]
	[switch]$WhatIf
)

# Variables ==================================
$infoClr = 'Green'
$actionClr = 'Yellow'
$alertClr = 'Red'
# ============================================
function Complete-Processing {
 process {
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.SID, $_.EM) -Fore $infoClr
 }
}
function Format-UGNInsert {
 begin {}
 process {

 }
}
function Get-ADData {
 Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $DomainController) -Fore $infoClr
 $adSession = New-PSSession -ComputerName $DomainController -Credential $ADCredential
 Import-PSSession -Session $adSession -Module ActiveDirectory -CommandName 'Get-ADUser' -AllowClobber | Out-Null
 $employeeParams = @{
  filter     = { (employeeID -like "*") -and (mail -like "*@*") }
  Properties = 'mail', 'homepage', 'employeeID', 'extensionAttribute1'
  SearchBase = $StaffOrgUnit
 }
 # $results = ('{0},{1}' -f Ge$id)DUser @employeeParams | Where-Object { $_.employeeId -match '^\d{4,}$$MyInvocation.MyCommand.Name ,' }
 Write-Host ('{0},Count: {1}' -f $MyInvocation.MyCommand.Name, $results.count) -Fore $infoClr
 $results
}

function Get-EmployeeData {
 $escParams = @{
  Server     = $EscapeServer
  Database   = $EscapeDatabase
  Credential = $EscapeCredential
  Query      = Get-Content -Path ./sql/escape-aeries-users2.sql -Raw
 }
 Write-Host ('{0},{1}\{2}' -f $MyInvocation.MyCommand.Name, $EscapeServer, $EscapeDatabase) -Fore $infoClr
 $results = Invoke-SqlCmd @escParams
 Write-Host ('{0},Count: {1}' -f $MyInvocation.MyCommand.Name, $results.count) -Fore $infoClr
 $results
}

# function Get-SisUGNData {
#  $sisParams = @{
#   Server     = $SISServer
#   Database   = $SISDatabase
#   Credential = $SISCredential
#  }
#  $sql = 'SELECT * FROM UGN'
#  Write-Host ('{0},{1}\{2},{3}' -f $MyInvocation.MyCommand.Name, $sisServer, $SISDatabase, $sql) -Fore $infoClr
#  $results = Invoke-SqlCmd @sisParams -Query $sql
#  Write-Host ('{0},Count: {1}' -f $MyInvocation.MyCommand.Name, $results.count) -Fore $infoClr
#  $results
# }

function Format-UserObj {
 begin {
  function Select-UTY ($code) {
   switch ($code) {
    CUMA2AR { 'aduser' }
    U { 'adteacher' }
    U { 'adteacher' }
    P { 'adteacher' }
    default { 'aduser' }
   }
  }
  function Select-U8 ($code) {
   switch ($code) {
    CUMA { 'A' }
    CUTA { 'T' }
    CSEA { 'C' }
    default { 'C' }
   }
  }
  function Select-Type ($code) {
   switch ($code) {
    CUMA2AR { @{UTY = 'aduser'; U8 = 'A' } } # Admin
    CUTA1AP { @{UTY = 'adteacher'; U8 = 'T' } } # Teachers
    CSEA2AR { @{UTY = 'aduser'; U8 = 'C' } } # Office Staff
    2AS { @{UTY = 'aduser'; U8 = 'C' } } # Office Subs
    1AS { @{UTY = 'adteacher'; U8 = 'T' } } # Teacher Subs
    U { @{UTY = 'adteacher'; U8 = 'T' } } # Student Teachers
    default { @{UTY = 'aduser'; U8 = 'C' } } # default
   }
  }
 }
 process {
  if ($_.empId -is [int]) {
   [int]$id = $_.empId
   # Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name , $id)
   $obj = $_ | Select-ADObject
   New-Object -TypeName PSObject -Property @{
    EM         = $obj.mail
    GEM        = $obj.homepage
    SID        = $id
    UN         = $obj.samAccountName
    SY         = 'AERIES.NET'
    TY         = 1
    bargUnitId = $_.BargUnitId
    U8         = (Select-Type ($_.)).U8
    UTY        = Select-UTY $_.EmploymentTypeCode
    HT         = -1
    FN         = $_.NameFirst.replace("'", "''") # Fix sinlge quote
    LN         = $_.NameLast.replace("'", "''") # Fix sinlge quote
   }
  }
 }
}

function Select-ADObject {
 process {
  if ($_.empId -is [int]) {
   [int]$id = $_.empId
   Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $id, $_.EmailWork)
   $global:adData.Where({ [int]$_.employeeId -eq $id })
  }
 }
}

function Submit-SQLOperation {
 param(
  [string]$Server,
  [string]$Database,
  [System.Management.Automation.PSCredential]$Credential,
  [string]$Query,
  [switch]$WhatIf
 )
 $msgData = $MyInvocation.MyCommand.Name, $Server, $Database, $Credential.Username, ($Query -split '\n')[0]
 Write-Host ('{0},[{1}\{2} as {3}],[{4}]' -f $msgData) -Fore $actionClr
 if (-not$WhatIf) {
  Invoke-SqlCmd -ServerInstance $Server -Database $Database -Credential $Credential -Query $Query
 }
}

function Select-MissingUGN {
 begin {
  $params = @{
   Server     = $SISServer
   Database   = $SISDatabase
   Credential = $SISCredential
   Query      = 'SELECT SID FROM UGN;'
  }
  $sisUGNData = Submit-SQLOperation @params
 }
 process {
  if ($sisUGNData.SID -notcontains $_.SID) {
   Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.SID)
   $_
  }
 }
}

filter Select-MissingSTF {
 if ($global:sisSTFData.ID -notcontains $_.empId) { $_ }
}

# ====================================================================
# Imported Functions
. .\lib\Clear-SessionData.ps1
. .\lib\Load-Module.ps1
. .\lib\Show-BlockInfo.ps1
. .\lib\Show-TestRun.ps1

Show-BlockInfo Main
Clear-SessionData
Show-TestRun

'SqlServer' | Load-Module

$employeeData = Get-EmployeeData
$global:adData = Get-ADData
# $global:sisUGNData = Get-SisUGNData
# $global:sisSTFData = Get-SisSTFData

$employeeData | Format-UserObj | Select-MissingUGN | Complete-Processing

# $employeeData | Select-MissingUGN | Format-UGNInsert | Add-UGNEntry

# $employeeData | Select-MissingSTF | Format-STFInsert | Add-STFEntry

# may not need as it's a legacy problem solved by this script

# $employeeData | Select-ErrantSTF | Format-STFUpdate | Update-STFEntry

# $employeeData | Select-MissingSSO | Format-SSOInsert | Add-SSOEntry