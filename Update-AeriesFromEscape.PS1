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
 [Alias('DCs')]
 [string[]]$DomainControllers,
 [Parameter(Mandatory = $True)]
 [Alias('ADCred')]
 [System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)]
 [Alias('OU')]
 [string]$StaffOrgUnit,
 # Student Information Server
 [Parameter(Mandatory = $true)]
 [string]$SISServer,
 [Parameter(Mandatory = $true)]
 [string]$SISDatabase,
 [Parameter(Mandatory = $true)]
 [System.Management.Automation.PSCredential]$SISCredential,
 # Escape Employee Server
 [Parameter(Mandatory = $true)]
 [string]$EscapeServer,
 [Parameter(Mandatory = $true)]
 [string]$EscapeDatabase,
 [Parameter(Mandatory = $true)]
 [System.Management.Automation.PSCredential]$EscapeCredential,
 # Run a 'Whatif' on commands - no data will be changed
 [switch]$InsertUGN,
 [switch]$InsertSTF,
 [switch]$InsertSSO,
 [Alias('wi')]
	[switch]$WhatIf
)

# Variables ==================================
$infoClr = 'Green'
$actionClr = 'Yellow'
$alertClr = 'Red'
# ============================================
function Add-UGNEntry {
 begin {}
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.empId, $_.samid) -Fore $actionClr
  Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.name, (($_.sqlInsertUGN -split '\n')[0]))
  Write-Debug 'Proceed?'
  Update-SIS $_.sqlInsertUGN
  $_
 }
}

function Add-SSOEntry {
 begin {}
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.empId, $_.samid) -Fore $actionClr
  Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.name, (($_.sqlInsertSSO -split '\n')[0]))
  Write-Debug 'Proceed?'
  Update-SIS $_.sqlInsertSSO
  $_
 }
}

function Add-STFEntry {
 begin {}
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.empId, $_.samid) -Fore $actionClr
  Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.name, (($_.sqlInsertSTF -split '\n')[0]))
  Write-Debug 'Proceed?'
  Update-SIS $_.sqlInsertSTF
  $_
 }
}

function Complete-Processing {
 begin {
  $i = 0
 }
 process {
  # Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.email) -Fore $infoClr
  $i++
  $msgData = $MyInvocation.MyCommand.Name, $i, $_.code , $_.empId, $_.email, $_.type, $_.UTY, $_.U8, $_.jobDesc
  Write-host ('{0},{1},{2},{3},{4},{5},{6},{7},{8}' -f $msgData) -Fore $infoClr
 }
}

function Get-UID {
 begin {
  $sisParams = @{
   Server     = $SISServer
   Database   = $SISDatabase
   Credential = $SISCredential
  }
 }
 process {
  Write-Host ( '{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.gmail ) -Fore $infoClr
  $sql = "SELECT TOP 1 UID FROM UGN WHERE SID = {0}" -f $_.empId
  $uid = (Invoke-SqlCmd @sisParams -Query $sql).UID
  if ($WhatIf -and ([int64]$uid -isnot [int64])) { 'TEST-UID'; return } # returns testUID
  if ([int64]$uid -is [int64]) { $uid; return }
  Write-Warning ('{0},{1},{2},UID not found' -f $MyInvocation.MyCommand.name, $_.empId, $_.gmail)
 }
}

function Format-SSOInsert {
 begin {
  $sisParams = @{
   Server     = $SISServer
   Database   = $SISDatabase
   Credential = $SISCredential
  }
  $insertSSO = Get-Content .\sql\insert-SSO.sql -Raw
  $updateSSO = Get-Content .\sql\update-SSO.sql -Raw
 }
 process {
  if (-not$_.gmail) {
   Write-Warning  ( '{0},{1},{2},GSUITE address (homepage) missing.' -f $MyInvocation.MyCommand.Name, $_.empId, $_.samid )
   return
  }
  $UID = $_ | Get-UID
  if ([int64]$UID -is [int64]) {
   $msgVars = $MyInvocation.MyCommand.Name, $_.empId, $_.gmail, $UID
   Write-Host ('{0},{1},{2},UID [{3}]' -f $msgVars)
   $checkUID = Invoke-Sqlcmd @sisParams -Query "SELECT * FROM SSO WHERE UID = $UID"
   # When UID present in SSO table but GEM is not correct
   # then the corresponding row needs to be updated
   $sql = if ($checkUID) {
    $updateSSO -f $_.gmail, $UID
   }
   else {
    $insertSSO -f $UID, $_.gmail
   }
   $msgData = $MyInvocation.MyCommand.Name, $sql
   Write-Verbose ( $msgData | Out-String )
   $newObj = $_.PSObject.Copy()
   $newObj | Add-Member -MemberType NoteProperty -Name sqlInsertSSO -Value $sql
   $newObj | Add-Member -MemberType NoteProperty -Name UID -Value $UID
   $newObj
  }
 }
}

function Format-STFInsert {
 begin {
  $baseSql = Get-Content .\sql\insert-STF.sql -Raw
 }
 process {
  $newObj = $_.PSObject.Copy()
  # ID, LN, FN, EM, U8
  $sql = $baseSql -f $_.empId, $_.ln, $_.fn, $_.email, $_.U8
  $msgData = $MyInvocation.MyCommand.Name, $sql
  Write-Verbose ( $msgData | Out-String )
  $newObj | Add-Member -MemberType NoteProperty -Name sqlInsertSTF -Value $sql
  $newObj
 }
}

function Format-UGNInsert {
 begin {
  $baseSql = Get-Content .\sql\insert-UGN.sql -Raw
 }
 process {
  $newObj = $_.PSObject.Copy()
  $sql = $baseSql -f $_.empId, $_.samid, $_.ln, $_.fn, $_.email, $_.UTY
  Write-Verbose ($sql | Out-String)
  $newObj | Add-Member -MemberType NoteProperty -Name sqlInsertUGN -Value $sql
  $newObj
 }
}

function Format-UserObj ($adObjs) {
 begin {
  Write-Verbose $MyInvocation.MyCommand.Name
  function Select-Type ($code) {
   switch ($code) {
    'CUMA2R' { @{type = 'Admin'; UTY = 'aduser'; U8 = 'A' } }
    'CUTA1P' { @{type = 'Teacher'; UTY = 'adteacher'; U8 = 'T' } }
    'CSEA2R' { @{type = 'Office Staff'; UTY = 'aduser'; U8 = 'C' } }
    '2S' { @{type = 'Office Sub'; UTY = 'aduser'; U8 = 'C' } }
    '1S' { @{type = 'Teacher Sub'; UTY = 'adteacher'; U8 = 'T' } }
    'U' { @{type = 'Student Teacher'; UTY = 'adteacher'; U8 = 'T' } }
    default { @{type = 'Default'; UTY = 'aduser'; U8 = 'C' } }
   }
  }
 }
 process {
  [int64]$id = [int64]$_.empId
  $ADobj = $adObjs.Where({ [int64]$_.employeeId -eq [int64]$id })
  if (-not$ADobj) {
   Write-Host ('{0},EmpId Not found in AD: [{1}]' -f $MyInvocation.MyCommand.Name , $id)
   return
  }
  if ($ADobj.Enabled -eq $false) {
   Write-Host ('{0},EmpId Obj disabled in AD: [{1}],[{2}]' -f $MyInvocation.MyCommand.Name , $id, $ADobj.Description)
   return
  }
  # Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name , $id)
  $code = ([string]$_.bargId + [string]$_.persId + [string]$_.empType).replace(' ', '')
  $typeData = Select-Type $code
  $obj = New-Object -TypeName PSObject -Property @{
   empId     = $_.empId
   siteId    = $_.siteId
   email     = $_.emailW
   gmail     = $ADobj.homepage
   samid     = $ADobj.samAccountName
   SY        = 'AERIES.NET'
   TY        = 1
   bargId    = $_.bargId
   code      = $code
   U8        = $typeData.U8
   UTY       = $typeData.UTY
   HT        = -1
   FN        = $_.fn.replace("'", "''") # Fix single quote
   LN        = $_.ln.replace("'", "''") # Fix single quote
   # emailH    = $_.emailH
   # city      = $_.city
   # state     = $_.state
   # addr      = $_.addr
   # zip       = $_.zip
   # phone     = $_.phone
   # cell      = $_.cell
   empType   = $_.empType
   empStatus = $_.empStatus
   jobDesc   = $_.jobDesc
   persId    = $_.persId
   type      = $typeData.type
   dts       = $_.dts
  }
  # $msgData = $MyInvocation.MyCommand.Name, $code , $_.empId, $_.emailW, $obj.type, $obj.UTY, $obj.U8, $_.jobDesc
  # Write-host ('{0},{1},{2},{3},{4},{5},{6},{7}' -f $msgData) -Fore $infoClr
  $obj
 }
}

function Get-ADData {
 $dc = Select-DomainController $DomainControllers
 New-ADSession -dc $dc -cmdlets 'Get-ADUser' -cred $ADCredential
 $employeeParams = @{
  filter     = "employeeID -like '*' -and mail -like '*@*'"
  Properties = 'mail', 'homepage', 'employeeID', 'extensionAttribute1', 'Description'
  SearchBase = $StaffOrgUnit
 }
 $results = Get-ADUser @employeeParams | Where-Object {
  # ($_.Enabled -eq $True) -and
  ( $_.employeeId -match '^\d{4,}$' )
 }
 Write-Host ('{0},Count: {1}' -f $MyInvocation.MyCommand.Name, $results.count) -Fore $infoClr
 $results
}

function Get-EmployeeData {
 $escParams = @{
  Server     = $EscapeServer
  Database   = $EscapeDatabase
  Credential = $EscapeCredential
  Query      = Get-Content -Path ./sql/escape-aeries-users.sql -Raw
 }
 Write-Host ('{0},{1}\{2}' -f $MyInvocation.MyCommand.Name, $EscapeServer, $EscapeDatabase) -Fore $infoClr
 $results = Invoke-SqlCmd @escParams
 Write-Host ('{0},Count: {1}' -f $MyInvocation.MyCommand.Name, $results.count) -Fore $infoClr
 $results
}

function Get-SQLData {
 param(
  [string]$Server,
  [string]$Database,
  [System.Management.Automation.PSCredential]$Credential,
  [string]$Query
 )
 $msgData = $MyInvocation.MyCommand.Name, $Server, $Database, $Credential.Username, ($Query -split '\n')[0]
 Write-Host ('{0},[{1}\{2} as {3}],[{4}]' -f $msgData) -Fore $actionClr
 Invoke-SqlCmd -ServerInstance $Server -Database $Database -Credential $Credential -Query $Query
}

function Update-SIS ($sql) {
 $sqlParams = @{
  Server     = $SISServer
  Database   = $SISDatabase
  Credential = $SISCredential
  Query      = $sql
 }
 $msgData = @(
  $MyInvocation.MyCommand.Name
  $sqlParams.Server
  $sqlParams.Database
  $sqlParams.Credential.Username
  ($sqlParams.Query -split '\n')[0]
 )
 Write-Host ('{0},[{1}\{2} as {3}],[{4}]' -f $msgData) -Fore $actionClr
 if (-not$WhatIf) {
  Write-Host 'Warning. SQL CHANGES HERE!' -Fore $alertClr
  Invoke-SqlCmd @sqlParams
 }
}

function Select-MissingUGN {
 begin {
  Write-Verbose ('{0}' -f $MyInvocation.MyCommand.Name)
  $params = @{
   Server     = $SISServer
   Database   = $SISDatabase
   Credential = $SISCredential
   Query      = 'SELECT SID FROM UGN;'
  }
  $sisUGNData = Invoke-SqlCmd @params
 }
 process {
  if ($sisUGNData.SID -notcontains $_.empId) {
   Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.email)
   $_
  }
 }
}

function Select-MissingSSO {
 begin {
  Write-Verbose ('{0}' -f $MyInvocation.MyCommand.Name)
  $params = @{
   Server     = $SISServer
   Database   = $SISDatabase
   Credential = $SISCredential
   Query      = 'SELECT GEM FROM SSO;'
  }
  $sisSSOData = Get-SQLData @params
  Write-Host ('{0},SSO Table Count {1}' -f $MyInvocation.MyCommand.Name, $sisSSOData.count ) -Fore $infoClr
 }
 process {
  # Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.empId )
  if ($sisSSOData.GEM -notcontains $_.gmail) {
   Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.gmail)
   $_
  }
 }
}

function Select-MissingSTF {
 begin {
  Write-Verbose ('{0}' -f $MyInvocation.MyCommand.Name)
  $params = @{
   Server     = $SISServer
   Database   = $SISDatabase
   Credential = $SISCredential
   Query      = 'SELECT ID FROM STF;'
  }
  $sisSTFData = Get-SQLData @params
  Write-Host ('{0},Count {1}' -f $MyInvocation.MyCommand.Name, $sisSTFData.count ) -Fore $infoClr
 }
 process {
  # Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.empId ) -Fore $infoClr
  if ($sisSTFData.ID -notcontains $_.empId) {
   Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.email)
   $_
  }
 }
}

# ==============================================================================================
# Imported Functions
. .\lib\Clear-SessionData.ps1
. .\lib\Load-Module.ps1
. .\lib\New-ADSession.ps1
. .\lib\Select-DomainController.ps1
. .\lib\Show-BlockInfo.ps1
. .\lib\Show-TestRun.ps1

Show-BlockInfo Main
Clear-SessionData
Show-TestRun

'SqlServer' | Load-Module

$employeeData = Get-EmployeeData
$adData = Get-ADData

$userObj = $employeeData | Format-UserObj $adData

if ($InsertUGN) {
 Show-BlockInfo 'Insert UGN'
 $userObj | Select-MissingUGN | Format-UGNInsert | Add-UGNEntry | Complete-Processing
}

if ($InsertSTF) {
 Show-BlockInfo 'Insert STF'
 $userObj | Select-MissingSTF | Format-STFInsert | Add-STFEntry | Complete-Processing
}

if ($InsertSSO) {
 Show-BlockInfo 'Insert SSO'
 $userObj | Select-MissingSSO | Format-SSOInsert | Add-SSOEntry | Complete-Processing
}

Clear-SessionData
Show-TestRun