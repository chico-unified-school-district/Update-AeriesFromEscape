<#
.SYNOPSIS
Add Relevant Employees to Aeries from Escape
.DESCRIPTION
This Script Queries the Escape database for Employees that fit the criteria ('CUTA','CUMA',or 'CSEA' members) for Aeries access
and adds them to the Aeries UNG table in the format: Domain\Username
.EXAMPLE
Update-AeriesFromEscape.PS1 -DC $dc -ADCred $adCred -OU 'OU=Employees,OU=Users,DC=OurDistrict,DC=org' -SISServer SISServer -SISData SISDB -SISCred $SISCred `
 -EscapeServer EscServer -EscapeData EscDB -EscapeCred $EscapeCred
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
 [Alias('wi')]
	[switch]$WhatIf
)

# Variables ==================================
$infoClr = 'Green'
$actionClr = 'Yellow'
$alertClr = 'Red'
# ============================================
function Add-UGNEntry ($params) {
 begin {
  $sql = "INSERT INTO UGN (SID,UN,LN,FN,EM,UTY,[UID],SY,TY,HT,CD,CDT,PLC)
  VALUES (@sid,@un,@ln,@fn,@em,@uty,(SELECT MAX([UID]) + 1 FROM UGN),'AERIES.NET',1,-1,GETDATE(),GETDATE(),GETDATE() );"
 }
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.empId, $_.samid) -Fore $actionClr
  # @sid,@un,@ln,@fn,@em,@uty - $_.empId, $_.samid, $_.ln, $_.fn, $_.email, $_.UTY
  $sqlVars = "sid=$($_.empid)", "un=$($_.samid)", "ln=$($_.ln)", "fn=$($_.fn)", "em=$($_.email)", "uty=$($_.UTY)"
  Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $sql, ($sqlVars -join ','))
  if (!$Whatif) { New-SqlOperation @params -Query $sql -Parameters $sqlVars }
  $_
 }
}

function Add-SSOEntry ($params) {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.empId, $_.samid) -Fore $actionClr
  $sqlVars = "gem=$($_.gmail)", "uid=$($_.UID)"
  Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $sql, ($sqlVars -join ','))
  if (!$WhatIf) { New-SqlOperation @params -Query $_.sqlSSO -Parameters $sqlVars }
  $_
 }
}

function Add-STFEntry ($params) {
 begin {
  # ID, LN, FN, EM, U8 (Coorespnds to BargUnitID),CP (mobile phone), NP (Notification Preference)
  # NP 0=Do Not Contact, 1=General and Emergency Announcements, 2=Emergency Announcements
  $sql = "INSERT INTO STF (ID,LN,FN,EM,U8,CP,NP) VALUES (@id,@ln,@fn,@em,@u8,@cp,1)"
 }
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.empId, $_.samid) -Fore $actionClr
  $sqlVars = "id=$($_.empid)", "ln=$($_.ln)", "fn=$($_.fn)", "em=$($_.email)", "u8=$($_.u8)", "cp=$($_.mobile)"
  Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $sql, ($sqlVars -join ','))
  if (!$WhatIf) { New-SqlOperation @params -Query $sql -Parameters $sqlVars }
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

function Get-UID  ($params) {
 begin {
  $sql = "SELECT TOP 1 UID FROM UGN WHERE SID = @sid"
 }
 process {
  Write-Host ( '{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.gmail ) -Fore $infoClr
  $sqlVars = "sid=$($_.empId)"
  Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $sql, $sqlVars)
  $uid = (New-SqlOperation @params -Query $sql -Parameters $sqlVars).UID
  if ($WhatIf -and ([int64]$uid -isnot [int64])) { 'TEST-UID'; return } # returns testUID
  if ([int64]$uid -is [int64]) { $uid; return }
  Write-Warning ('{0},{1},{2},UID not found' -f $MyInvocation.MyCommand.name, $_.empId, $_.gmail)
 }
}

function Select-SqlSSO ($params) {
 begin {
  $updateSSO = 'UPDATE SSO SET GEM = @gem WHERE UID = @uid'
  $insertSSO = "INSERT INTO SSO (UID, AK, EID, SCU, GEM) VALUES (@uid,'',0,'',@gem)"
  $ssoSql = 'SELECT * FROM SSO WHERE UID = @uid'
 }
 process {
  $UID = $_ | Get-UID $params
  if ([int64]$UID -is [int64]) {
   $msgVars = $MyInvocation.MyCommand.Name, $_.empId, $_.gmail, $UID
   Write-Host ('{0},{1},{2},UID [{3}]' -f $msgVars)
   $sqlVars = "uid=$UID"
   if ($UID) { $checkUID = New-SqlOperation @params -Query $ssoSql -Parameters $sqlVars }
   # When UID present in SSO table but GEM is not correct
   # then the corresponding row needs to be updated
   $sql = if ($checkUID) { $updateSSO } else { $insertSSO }
   $msgData = $MyInvocation.MyCommand.Name, $sql
   Write-Verbose ( $msgData | Out-String )
   $_.UID = $UID
   $_.sqlSSO = $sql
   $_
  }
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
    '6' { @{type = 'Student Teacher'; UTY = 'adteachersub'; U8 = 'T' } }
    default { @{type = 'Default'; UTY = 'adteacher'; U8 = 'T' } }
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
  $mobile = $_.mobile.replace(' ', '')
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
   mobile    = $mobile
   empType   = $_.empType
   empStatus = $_.empStatus
   jobDesc   = $_.jobDesc
   persId    = $_.persId
   type      = $typeData.type
   dts       = $_.dts
   sqlSSO    = $null
   UID       = $null
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

function Get-EmployeeData ($params) {
 $query = Get-Content -Path ./sql/escape-aeries-users.sql -Raw
 $results = New-SqlOperation @params -Query $query
 Write-Host ('{0},{1}\{2}' -f $MyInvocation.MyCommand.Name, $EscapeServer, $EscapeDatabase) -Fore $infoClr
 Write-Host ('{0},Count: {1}' -f $MyInvocation.MyCommand.Name, $results.count) -Fore $infoClr
 $results
}

function Update-SIS ($params, $sql) {
 $msgData = @(
  $MyInvocation.MyCommand.Name
  $params.Server
  $params.Database
  $params.Credential.Username
  ($sql -split '\n')[0]
 )
 Write-Host ('{0},[{1}\{2} as {3}],[{4}]' -f $msgData) -Fore $actionClr
 if (-not$WhatIf) {
  Write-Host 'Warning. SQL CHANGES HERE!' -Fore $alertClr
  Invoke-SqlCmd @params -Query $sql
 }
}

function Select-MissingUGN  ($params) {
 begin {
  Write-Verbose ('{0}' -f $MyInvocation.MyCommand.Name)
  $sisUGNData = New-SqlOperation @params -Query 'SELECT SID FROM UGN;'
 }
 process {
  if ($sisUGNData.SID -notcontains $_.empId) {
   Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.email)
   $_
  }
 }
}

function Select-MissingSSO ($params) {
 begin {
  Write-Verbose ('{0}' -f $MyInvocation.MyCommand.Name)
  $sisSSOData = New-SqlOperation @params -Query 'SELECT GEM FROM SSO;'
  Write-Host ('{0},SSO Table Count {1}' -f $MyInvocation.MyCommand.Name, $sisSSOData.count ) -Fore $infoClr
 }
 process {
  Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.empId )
  if ($sisSSOData.GEM -contains $_.gmail) { return }
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.gmail)
  $_
 }
}

function Select-MissingSTF ($params) {
 begin {
  Write-Verbose ('{0}' -f $MyInvocation.MyCommand.Name)
  $sisSTFData = New-SqlOperation @params -Query 'SELECT ID FROM STF;'
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

Import-Module CommonScriptFunctions
Import-Module -Name dbatools -Cmdlet Invoke-DbaQuery, Set-DbatoolsConfig

Clear-SessionData
Show-TestRun
Show-BlockInfo Main

$empParams = @{
 Server     = $EscapeServer
 Database   = $EscapeDatabase
 Credential = $EscapeCredential
}

$sisParams = @{
 Server     = $SISServer
 Database   = $SISDatabase
 Credential = $SISCredential
}

$employeeData = Get-EmployeeData $empParams
$adData = Get-ADData

$userObj = $employeeData | Format-UserObj $adData

Show-BlockInfo 'Insert UGN'
$userObj | Select-MissingUGN $sisParams | Add-UGNEntry $sisParams | Complete-Processing

Show-BlockInfo 'Insert STF'
$userObj | Select-MissingSTF $sisParams | Add-STFEntry $sisParams | Complete-Processing

Show-BlockInfo 'Insert SSO'
$userObj | Select-MissingSSO $sisParams | Select-SqlSSO $sisParams | Add-SSOEntry $sisParams | Complete-Processing

Clear-SessionData
Show-TestRun