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
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $sql, ($sqlVars -join ',')) -F DarkCyan
  if (!$Whatif) { New-SqlOperation @params -Query $sql -Parameters $sqlVars }
  $_
 }
}

function Add-SSOEntry ($params) {
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.name, $_.empId, $_.samid) -Fore $actionClr
  $sqlVars = "gem=$($_.gmail)", "uid=$($_.UID)"
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $_.sqlSSO, ($sqlVars -join ',')) -F DarkCyan
  if (!$WhatIf) { New-SqlOperation @params -Query $_.sqlSSO -Parameters $sqlVars }
  $_
 }
}

function Add-STFEntry ($params) {
 begin {
  # ID, LN, FN, EM, U8 (Coorespnds to BargUnitID),CP (mobile phone), NP (Notification Preference)
  # NP 0=Do Not Contact, 1=General and Emergency Announcements, 2=Emergency Announcements
  $sql = "INSERT INTO STF (ID,LN,FN,EM,U8,CP,NP,PS,PSC) VALUES (@id,@ln,@fn,@em,@u8,@cp,1,@ps,@psc)"
 }
 process {
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $_.empId, $_.samid) -Fore $actionClr
  $sqlVars = "id=$($_.empid)", "ln=$($_.ln)", "fn=$($_.fn)", "em=$($_.email)",
  "u8=$($_.u8)", "cp=$($_.mobile)", "ps=$($_.positionStatus)", "psc=$($_.siteId)"
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $sql, ($sqlVars -join ',')) -F DarkCyan
  #TODO
  # pause
  if (!$WhatIf) {
   New-SqlOperation @params -Query $sql -Parameters $sqlVars
  }
  $_
 }
}

function Complete-Processing {
 begin { $i = 0 }
 process {
  $i++
  $msgData = $MyInvocation.MyCommand.Name, $i, $_.code , $_.empId, $_.email, $_.type, $_.UTY, $_.U8, $_.jobDesc
  Write-host ('{0},{1},{2},{3},{4},{5},{6},{7},{8}' -f $msgData) -Fore $infoClr
  Write-Verbose ($_ | Out-String)
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
  if (!$uid -and $WhatIf) { $uid = 99999999 }
  if ([int64]$uid -is [int64]) { $uid; return }
  Write-Warning ('{0},{1},{2},UID not found' -f $MyInvocation.MyCommand.name, $_.empId, $_.gmail)
 }
}

function Format-UserObj {
 process {
  New-Object -TypeName PSObject -Property @{
   empId          = $_.empId
   siteId         = $_.siteId
   deptNum        = $null
   email          = $_.emailW
   gmail          = $null
   samid          = $null
   bargId         = $_.bargId
   code           = $code
   U8             = $null
   UTY            = $null
   HT             = -1
   FN             = $_.fn.replace("'", "''") # Fix single quote
   LN             = $_.ln.replace("'", "''") # Fix single quote
   mobile         = $_.mobile.replace(' ', '')
   empType        = $_.empType
   empStatus      = $_.empStatus
   jobDesc        = $_.jobDesc
   persId         = $_.persId
   positionStatus = $null
   type           = $null
   dts            = $_.dts
   sqlSSO         = $null
   UID            = $null
  }
 }
}

function Get-EmployeeData ($params) {
 $query = Get-Content -Path ./sql/escape-aeries-users.sql -Raw
 $results = New-SqlOperation @params -Query $query
 Write-Host ('{0},{1},Count: {2}' -f $MyInvocation.MyCommand.Name, $EscapeDatabase, @($results).count) -Fore $infoClr
 $results
}

function Set-EmployeeTypeData {
 begin {
 }
 process {
  $code = ([string]$_.bargId + [string]$_.persId + [string]$_.empType).replace(' ', '')
  $typeData = switch ($code) {
   'CUMA2R' { @{type = 'Admin'; UTY = 'aduser'; U8 = 'A' } }
   'CUTA1P' { @{type = 'Teacher'; UTY = 'adteacher'; U8 = 'T' } }
   'CSEA2R' { @{type = 'Office Staff'; UTY = 'aduser'; U8 = 'C' } }
   '2S' { @{type = 'Office Sub'; UTY = 'aduser'; U8 = 'C' } }
   '1S' { @{type = 'Teacher Sub'; UTY = 'adteacher'; U8 = 'T' } }
   '6U' { @{type = 'Student Teacher'; UTY = 'adteachersub'; U8 = 'T' } }
   '6' { @{type = 'Student Teacher'; UTY = 'adteachersub'; U8 = 'T' } }
   default { @{type = 'Default'; UTY = 'adteacher'; U8 = 'T' } }
  }
  Write-Verbose ('{0},{1},Code: {2}' -f $MyInvocation.MyCommand.Name, $_.empId, $code)
  $_.code = $code
  $_.U8 = $typeData.U8
  $_.UTY = $typeData.UTY
  $_.type = $typeData.type
  $_
 }
}

function Set-PositionStatus {
 begin {
 }
 process {
  $result = switch ($_.empType) {
   'P' { 1 } # Tenured
   1 { 2 } # Probationary
   2 { 2 } # Probationary
   'B' { 2 } # Probationary
   'U' { 5 } # Student Teacher
   default { [System.DBNull]::Value }
  }
  $_.positionStatus = $result
  $_
 }
}

function Set-ADData {
 begin {
  $dc = Select-DomainController $DomainControllers
  New-ADSession -dc $dc -cmdlets 'Get-ADUser' -cred $ADCredential
 }
 process {
  Write-Verbose ('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.fn, $_.ln)
  $adParams = @{
   Filter     = "EmployeeID -eq $($_.empId) -and mail -like '*@*' -and Enabled -eq 'True'"
   Properties = 'mail', 'homepage', 'employeeID', 'extensionAttribute1', 'Description', 'departmentNumber'
  }
  $adObj = Get-Aduser @adParams
  if (!$adObj) {
   $msg = $MyInvocation.MyCommand.Name , $_.empId, $_.fn, $_.ln
   return (Write-Host ('{0},{1},{2},{3},Employee not found' -f $msg))
  }
  # Write-Verbose ($adObj | out-string)
  $_.deptNum = try { $adObj.departmentNumber[0] } catch {}
  $_.gmail = $adObj.homepage
  $_.samid = $adObj.samAccountName
  $_
 }
}

function Set-Site {
 process {
  $siteId = if ($_.siteId -match '\d') { $_.siteId }
  elseif ($_.deptNum -match '\d') { $_.deptNum }
  else { [System.DBNull]::Value }
  $_.siteId = $siteId
  $_
 }
}

function Select-MissingUGN  ($params) {
 begin {
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
  $sisSSOData = New-SqlOperation @params -Query 'SELECT GEM FROM SSO;'
 }
 process {
  # Write-Verbose ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.empId )
  if ($sisSSOData.GEM -contains $_.gmail) { return }
  Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.gmail)
  $_
 }
}

function Select-MissingSTF ($params) {
 begin {
  $sisSTFData = New-SqlOperation @params -Query 'SELECT ID FROM STF;'
 }
 process {
  # Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.empId ) -Fore $infoClr
  if ($sisSTFData.ID -notcontains $_.empId) {
   Write-Verbose ('{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.email)
   $_
  }
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

# =========================================================================

Import-Module CommonScriptFunctions
Import-Module -Name dbatools -Cmdlet Invoke-DbaQuery, Set-DbatoolsConfig

Clear-SessionData
if ($WhatIf) { Show-TestRun }
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

$userObj = Get-EmployeeData $empParams |
 Format-UserObj |
  Set-ADData |
   Set-Site |
    Set-PositionStatus |
     Set-EmployeeTypeData

Show-BlockInfo 'Insert UGN'
$userObj | Select-MissingUGN $sisParams | Add-UGNEntry $sisParams | Complete-Processing

Show-BlockInfo 'Insert STF'
$userObj | Select-MissingSTF $sisParams | Add-STFEntry $sisParams | Complete-Processing

Show-BlockInfo 'Insert SSO'
$userObj | Select-MissingSSO $sisParams | Select-SqlSSO $sisParams | Add-SSOEntry $sisParams | Complete-Processing

Clear-SessionData
if ($WhatIf) { Show-TestRun }