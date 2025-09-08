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
 [Parameter(Mandatory = $True)][Alias('DCs')][string[]]$DomainControllers,
 [Parameter(Mandatory = $True)][Alias('ADCred')][System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)][Alias('OU')][string]$StaffOrgUnit,
 # Student Information Server
 [Parameter(Mandatory = $true)][string]$SISServer,
 [Parameter(Mandatory = $true)][string]$SISDatabase,
 [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$SISCredential,
 # Escape Employee Server
 [Parameter(Mandatory = $true)][string]$EscapeServer,
 [Parameter(Mandatory = $true)][string]$EscapeDatabase,
 [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$EscapeCredential,
 # Intermediate Server
 [Parameter(Mandatory = $true)][string]$IntServer,
 [Parameter(Mandatory = $true)][string]$IntDatabase,
 [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$IntCredential,
 [Parameter(Mandatory = $true)][string]$IntTable,
 # Run a 'Whatif' on commands - no data will be changed
 [Alias('wi')][switch]$WhatIf
)

# Variables ==================================
$infoClr = 'Green'
$actionClr = 'DarkCyan'
# ============================================
function Add-UGNEntry ($params) {
 begin {
  $sql = "INSERT INTO UGN (SID,UN,LN,FN,EM,UTY,[UID],SY,TY,HT,CD,CDT,PLC)
  VALUES (@sid,@un,@ln,@fn,@em,@uty,(SELECT MAX([UID]) + 1 FROM UGN),'AERIES.NET',1,-1,GETDATE(),GETDATE(),GETDATE() );"
 }
 process {
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $_.emp.empId, $_.ad.SamAccountName) -Fore $actionClr
  # @sid,@un,@ln,@fn,@em,@uty - $_.empId, $_.ad.SamAccountName, $_.ln, $_.fn, $_.email, $_.UTY
  $sqlVars = "sid=$($_.empid)", "un=$($_.ad.SamAccountName)", "ln=$($_.ln)", "fn=$($_.fn)", "em=$($_.email)", "uty=$($_.UTY)"
  Write-Host ('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.name, $params.Database, $sql, ($sqlVars -join ',')) -F $actionClr
  if (!$Whatif) { New-SqlOperation @params -Query $sql -Parameters $sqlVars }
  $_
 }
}

function Add-SSOEntry ($params) {
 process {
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $_.emp.EmpId, $_.ad.SamAccountName) -Fore $actionClr
  $sqlVars = "gem=$($_.gmail)", "uid=$($_.UID)"
  Write-Host ('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.name, $params.Database, $_.sqlSSO, ($sqlVars -join ',')) -F $actionClr
  if (!$WhatIf) { New-SqlOperation @params -Query $_.sqlSSO -Parameters $sqlVars }
  $_
 }
}

function Add-STFEntry ($params) {
 begin {
  # ID, LN, FN, EM, U8 (Coorespnds to BargUnitID),CP (mobile phone), NP (Notification Preference)
  # NP 0=Do Not Contact, 1=General and Emergency Announcements, 2=Emergency Announcements
  $sql = 'INSERT INTO STF (ID,LN,FN,EM,U8,CP,NP,PS,PSC) VALUES (@id,@ln,@fn,@em,@u8,@cp,1,@ps,@psc)'
 }
 process {
  Write-Host ('{0},{1},{2}' -f $MyInvocation.MyCommand.name, $_.empId, $_.ad.SamAccountName) -Fore $actionClr
  $sqlVars = "id=$($_.empid)", "ln=$($_.ln)", "fn=$($_.fn)", "em=$($_.email)",
  "u8=$($_.u8)", "cp=$($_.mobile)", "ps=$($_.positionStatus)", "psc=$($_.siteId)"
  Write-Host ('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.name, $params.Database, $sql, ($sqlVars -join ',')) -F $actionClr
  if (!$WhatIf) { New-SqlOperation @params -Query $sql -Parameters $sqlVars }
  $_
 }
}

function Complete-Processing {
 process {
  $msgData = $MyInvocation.MyCommand.Name, $i, $_.code , $_.empId, $_.email, $_.type, $_.UTY, $_.U8, $_.jobDesc
  Write-Host ('{0},{1},{2},{3},{4},{5},{6},{7},{8}' -f $msgData) -Fore $infoClr
  Write-Verbose ($_ | Out-String)
 }
}

function Get-UID  ($params) {
 begin {
  $sql = 'SELECT TOP 1 UID FROM UGN WHERE SID = @sid'
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
   ad             = $null
   emp            = $_
   int            = $_
   empId          = $_.empId
   siteId         = $_.siteId
   email          = $_.emailW
   gmail          = $null
   bargId         = $_.bargId
   code           = $code
   U8             = $null
   UTY            = $null
   HT             = -1
   FN             = $_.fn.replace("'", "''") # Fix single quote
   LN             = $_.ln.replace("'", "''") # Fix single quote
   mobile         = $_.mobile.replace(' ', '')
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
 $results = New-SqlOperation @params -Query $query | ConvertTo-Csv | ConvertFrom-Csv
 Write-Host ('{0},{1},Count: {2}' -f $MyInvocation.MyCommand.Name, $EscapeDatabase, @($results).count) -Fore $infoClr
 $results
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

function Set-EmployeeTypeData {
 begin {
 }
 process {
  $_.code = ([string]$_.bargId + [string]$_.persId + [string]$_.emp.empType).replace(' ', '')
  $typeData = switch ($_.code) {
   'CUMA2R' { @{type = 'Admin'; UTY = 'aduser'; U8 = 'A' } }
   'CUTA1P' { @{type = 'Teacher'; UTY = 'adteacher'; U8 = 'T' } }
   'CSEA2R' { @{type = 'Office Staff'; UTY = 'aduser'; U8 = 'C' } }
   '2S' { @{type = 'Office Sub'; UTY = 'aduser'; U8 = 'C' } }
   '1S' { @{type = 'Teacher Sub'; UTY = 'adteacher'; U8 = 'T' } }
   '6U' { @{type = 'Student Teacher'; UTY = 'adteachersub'; U8 = 'T' } }
   '6' { @{type = 'Student Teacher'; UTY = 'adteachersub'; U8 = 'T' } }
   default { @{type = 'Default'; UTY = 'adteacher'; U8 = 'T' } }
  }
  # Write-Verbose ('{0},{1},Code: {2}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.code)
  $_.type = $typeData.type
  $_.UTY = $typeData.UTY
  $_.U8 = $typeData.U8
  $_
 }
}

function Set-PositionStatus {
 begin {
 }
 process {
  $result = switch ($_.emp.empType) {
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
  New-ADSession -DC $dc -Cmdlets 'Get-ADUser' -cred $ADCredential
 }
 process {
  # Write-Verbose ('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.Name, $_.empId, $_.fn, $_.ln)
  $adParams = @{
   Filter     = "EmployeeID -eq $($_.empId)"
   Properties = 'Mail', 'HomePage', 'EmployeeID', 'extensionAttribute1', 'Description', 'departmentNumber', 'AccountExpirationDate'
  }
  $adObj = Get-ADUser @adParams
  if (!$adObj) {
   $msg = $MyInvocation.MyCommand.Name , $_.empId, $_.fn, $_.ln
   return (Write-Host ('{0},{1},{2},{3},Employee not found' -f $msg))
  }
  $_.ad = $adObj
  $_.gmail = $adObj.homepage
  $_.ad.SamAccountName = $adObj.samAccountName
  $_
 }
}

# function Set-IntData ($params, $table) {
#  begin {
#   $sql = 'SELECT * FROM {0} WHERE EmpId = @id AND dts > DATEADD(day,-60,GETDATE())' -f $table
#  }
#  process {
#   $sqlVars = "id=$($_.empId)"
#   # Write-Verbose ('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.Name, $_.ad.SamAccountName, $sql, $sqlVars)
#   $_.int = New-SqlOperation @params -Query $sql -Parameters $sqlVars | ConvertTo-Csv | ConvertFrom-Csv
#   $_
#  }
# }

function Set-SiteId {
 process {
  $adDept = try { $_.ad.departmentNumber[0] } catch { $null }
  # zone ref site codes match employee db codes. Sis codes omit the trailing zero
  $siteId = if ($_.emp.siteId -match '\d') { $_.emp.siteId }
  elseif ( $_.int.siteCode -match '\d' ) { $_.int.siteCode }
  else { [System.DBNull]::Value }
  $_.siteId = try { [int]$siteId / 10 } catch { $siteId }
  if ($_.siteId) { Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $_.siteId) -f Red; Read-Host }
  $_
 }
}

function Set-STFSiteID ($params) {
 begin {
  $sql = 'UPDATE STF SET PSC = @deptNum WHERE ID = @id'
 }
 process {
  $siteId = if ($_.siteId -match '\d') { $_.siteId } else { 0 }
  $sqlVars = "deptNum=$siteID", "id=$($_.ad.EmployeeID)"
  $msgVars = $MyInvocation.MyCommand.Name, $_.ad.SamAccountName, $sql, ($sqlVars -join ',')
  Write-Host ('{0},{1},{2},{3}' -f $msgVars) -F DarkCyan
  if ($WhatIf) { return $_ }
  New-SqlOperation @params -Query $sql -Parameters $sqlVars
  $_
 }
}

function Set-UGNExpirationDate ($params, $idList) {
 begin {
  $sql = 'UPDATE UGN SET XD = @expireDate WHERE SID = @id'
 }
 process {
  if ($idList -notcontains $_.persId) { return $_ } # Only process specific personTypeIds
  if ($_.ad.AccountExpirationDate -isnot [datetime]) {
   Write-Host ('{0},{1},{2},AccountExpirationDate missing' -f $MyInvocation.MyCommand.Name, $_.ad.SamAccountName)
   return $_
  }
  $sqlVars = "expireDate=$($_.ad.AccountExpirationDate)", "id=$($_.ad.EmployeeID)"
  $msgVars = $MyInvocation.MyCommand.Name, $_.ad.SamAccountName, $sql, ($sqlVars -join ',')
  Write-Host ('{0},{1},{2},{3}' -f $msgVars) -F DarkBlue
  if ($WhatIf) { return $_ }
  New-SqlOperation @params -Query $sql -Parameters $sqlVars
  $_
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

$intParams = @{
 Server     = $IntServer
 Database   = $IntDatabase
 Credential = $IntCredential
}

$userObj = Get-EmployeeData $empParams |
 Format-UserObj |
  Set-ADData |
   Set-IntData $intParams $IntTable |
    Set-SiteId |
     #   Set-PositionStatus |
     #    Set-EmployeeTypeData
     Complete-Processing

Show-BlockInfo $SISDatabase

# Show-BlockInfo 'Insert UGN'
# $userObj | Select-MissingUGN $sisParams | Add-UGNEntry $sisParams | Set-UGNExpirationDate $sisParams 6 | Complete-Processing

# Show-BlockInfo 'Insert STF'
# $userObj | Select-MissingSTF $sisParams | Add-STFEntry $sisParams | Set-STFSiteID $sisParams | Complete-Processing

# Show-BlockInfo 'Insert SSO'
# $userObj | Select-MissingSSO $sisParams | Select-SqlSSO $sisParams | Add-SSOEntry $sisParams | Complete-Processing

Clear-SessionData
if ($WhatIf) { Show-TestRun }