<#
.SYNOPSIS
Add Relevant Employees to Aeries from Escape
.DESCRIPTION
This Script Queries the Escape database for Employees that fit the criteria ('CUTA','CUMA',or 'CSEA' members) for Aeries access
and adds them to the Aeries UNG table in the format: Domain\Username
.EXAMPLE
Update-AeriesFromEscape.PS1 -DC $dc -ADCred $adCred -SISServer SISServer -SISData SISDB -SISCred $SISCred `
 -EscapeServer EscServer -EscapeData EscDB -EscapeCred $EscapeCred
.EXAMPLE
Update-AeriesFromEscape.PS1 -DC $dc -ADCred $adCred -SISServer SISServer -SISData SISDB -SISCred $SISCred `
 -EscapeServer EscServer -EscapeData EscDB -EscapeCred $EscapeCred -WhatIf -Verbose
.INPUTS
.OUTPUTS
.NOTES
$AeriesQuery = "SELECT DISTINCT * FROM UGN WHERE UTY = `'adteacher`' OR  UTY = `'aduser`' ORDER BY SID"
$AeriesQuery = "SELECT * FROM UGN WHERE UTY = `'adteacher`' OR  UTY = `'aduser`' ORDER BY SID"
.LINK
#>
#Requires -Version 5.0

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
 # Run a Whatif on commands - no data will be changed
 [Alias('wi')]
	[switch]$WhatIf
)
 
Clear-Host ; $error.clear() # Clear screen and error log.
Get-PSSession | Remove-PSSession -WhatIf:$false

# AD Domain Controller Session
$adCmdLets = 'Get-ADUser'
$adSession = New-PSSession -ComputerName $DomainController -Credential $ADCredential
Import-PSSession -Session $adSession -Module ActiveDirectory -CommandName $adCmdLets -AllowClobber > $null

# Variables

# Imported Functions
. '.\lib\Add-Log.ps1'
. '.\lib\Invoke-SQLCOmmand.PS1'

$SISDatabaseHash = @{
 Server     = $SISServer
 Database   = $SISDatabase
 Credential = $SISCredential
}
$AeriesResults = Invoke-SQLCOmmand @SISDatabaseHash -Query 'SELECT * FROM UGN'

# Employee Management Database Connection Info
$EscapeDatabaseHash = @{
 Server     = $EscapeServer
 Database   = $EscapeDatabase
 Credential = $EscapeCredential
 Query      = Get-Content -Path ./sql/escape-aeries-users.sql -Raw
}
Add-Log info ('Querying employee database {0}\{1}' -f $EscapeServer, $EscapeDatabase)
$EscapeResults = Invoke-SQLCOmmand @EscapeDatabaseHash

# Active Directory Employee Objects
$employeeParams = @{
 filter     = { 
  (employeeID -like "*") -and 
  (mail -like "*@chicousd.org") -and
  (department -ne 380)
 }
 Properties = 'mail', 'homepage','employeeID', 'extensionAttribute1'
 SearchBase = 'OU=Employees,OU=Users,OU=Domain_Root,DC=chico,DC=usd'
}
Add-Log info ('{0},Getting Active Directory staff objects' -f $DomainController)
$ADEmployeeAccounts = Get-ADUser @employeeParams

foreach ($emp in $EscapeResults) {
 # Begin Process Escape Results
	Write-Verbose ("++=== Started processing for: {0} | {1} {2} ===++" -f $emp.empId, $emp.namefirst, $emp.namelast)
 Write-Debug ('======== Process {0} =========' -f $emp.empID)
	$empId = $emp.empId
	$user = $ADEmployeeAccounts.Where( { $_.employeeID -eq $empId })
	if (!$user) {
  Write-Verbose "$empId,User not found in AD" 
 }
 else {
  # Begin AD User Exists
		# empId match found - Checking UGN
  # Setting Variables
  if ($user.count -gt 1) {
   Add-Log warning ('EmployeeID {0} count > 1' -f $user[0].employeeID)
  }
  $EM = $user.mail
  $GEM = $user.homepage
		$SID = $empId
		$UN = $user.samAccountName
		$SY = 'AERIES.NET'
  $TY = 1
  $bargUnitId = $emp.BargUnitId
  $U8 = $emp.U8
		if ($bargUnitId -eq 'CUTA') { $UTY = 'adteacher' } else { $UTY = 'aduser' }
		$HT	= -1
		$FN = $emp.NameFirst.replace("'", "")
		$LN = $emp.NameLast.replace("'", "")

		if (
   ( $AeriesResults.SID -notcontains $empId ) -and 
   ( $AeriesResults.UN -notcontains $UN ) -and 
   ( $AeriesResults.EM -notcontains $EM ) ) {
   # Begin INSERT User in UGN Table
   Write-Verbose "$FN $LN $empId not in UGN Table."
			# Add UN (Username) to UGN
			$UGNInsert = @"
			INSERT INTO UGN ([UID], UN, SY, TY, UTY, HT, CD, EM, FN, LN, CDT, SID, PLC)
			VALUES  ((SELECT MAX([UID]) + 1 FROM UGN),`'$UN`',`'$SY`',$TY,`'$UTY`',$HT,GETDATE(),
			`'$EM`',`'$FN`',`'$LN`',GETDATE(),$SID,GETDATE())
"@ # Indentation causes error

   Add-Log insert ('{0},{1},{2}' -f $EM, $empId, "[$SISDatabase].[UGN]")  -WhatIf:$WhatIf
   Invoke-SQLCOmmand @SISDatabaseHash -SqlCommand $UGNInsert -WhatIf:$WhatIf
  } # End INSERT User in UGN Table

  if ( ($bargUnitId -eq 'CUTA') -or
   ($bargUnitId -eq 'CUMA') -or
   ($bargUnitId -eq 'CSEA') ) {
   # BEGIN INSERT/UPDATE User STF Table data
   $STFIUserCheck = Invoke-SQLCOmmand @SISDatabaseHash -SqlCommand "SELECT EM,U8 FROM STF WHERE ID = $empId"
   if (!$STFIUserCheck) {
    # Begin INSERT New STF Entry
    $STFInsertUser = "INSERT INTO STF (ID,FN,LN,EM,U8) VALUES (`'$empId`',`'$FN`',`'$LN`',`'$EM`',`'$U8`')"
    Add-Log insert "$EM,$empId,$FN,$LN,$U8,[$SISDatabase].[UGN]" -WhatIf:$WhatIf
    Invoke-SQLCOmmand @SISDatabaseHash -SqlCommand $STFInsertUser -WhatIf:$WhatIf
   } # END INSERT New STF Entry

   if ( $STFIUserCheck.em -ne $user.mail ) {
    # Begin CHECK/UPDATE EMAIL
    Write-Verbose "STF.EM ($($STFIUserCheck.em)) not equal for $EM $empId"
    $STFEMUpdate = "UPDATE STF SET STF.EM = `'$($user.mail)`' WHERE STF.ID = $empId"
    Add-Log update ('{0},{1},{2}' -f $user.mail, $empId, "[$SISDatabase].[STF].[EM]") -WhatIf:$WhatIf
    Invoke-SQLCOmmand @SISDatabaseHash -SqlCommand $STFEMUpdate -WhatIf:$WhatIf
   } # End CHECK/UPDATE EMAIL

   if ( $STFIUserCheck.u8 -ne $emp.u8 ) {
    # Begin CHECK/UPDATE U8
    Write-Verbose "Aeries STF.u8 ($($STFIUserCheck.u8)) not equal to Escape: $U8 for $empId"
    $STFU8Update = "UPDATE STF SET STF.U8 = `'$U8`' WHERE STF.ID = $empId"
    Add-Log update "$empId,$U8,[$SISDatabase].[STF].[U8]" -WhatIf:$WhatIf
    Invoke-SQLCOmmand @SISDatabaseHash -SqlCommand $STFU8Update -WhatIf:$WhatIf
   } # End CHECK/UPDATE U8

   # INSERT/UPDATE UGN.UID
  } # END INSERT/UPDATE User STF Table data
  # ======================================================================
  # INSERT/UPDATE SSO TABLE - SSO.GEM
  $uidSql = "SELECT UID FROM UGN WHERE UN = `'$UN`'"
  $UID=  (Invoke-SQLCOmmand @SISDatabaseHash -SqlCommand $uidSql | Select-Object -First 1).UID
  if ($UID -notmatch "\d{4,}"){
   Add-Log warning ('{0} UID not in correct format for {1} in UGN Table {2}\{3}' -f $UID, $UN, $SISServer, $SISDatabase)
  }
  else {

  }
  # $userUgnUid = ( $AeriesResults.Where({$_.UN -eq $UN}) ).UID | Select-Object -First 1
  $ssoUIDCheck = Invoke-SQLCOmmand @SISDatabaseHash -SqlCommand "SELECT UID FROM SSO WHERE UID = $UID"
  if ($ssoUIDCheck){ # BEGIN SSO UID CHECK
   Write-Verbose ('{0} for {1} already present in SSO' -f $UID, $UN) 
  }
  else {
   # Read-Host 'UID Wait'
   if ($GEM -like "*@chicousd.net"){
    $ssoGemcheck = Invoke-SQLCOmmand @SISDatabaseHash -SqlCommand "SELECT GEM FROM SSO WHERE GEM = `'$GEM`'"
    if ($ssoGemCheck) { 
     Write-Verbose ('SSO.GEM: {0} GSuite address already present.' -f $GEM)
    }
    else{
      Write-Debug 'process sso.gem?'
      Add-Log insert ('SSO.GEM {0} for SSO.UID {1}' -f $GEM, $UID)
      $ssoGemInsert = "INSERT INTO SSO(UID, AK, EID, SCU, GEM) VALUES ($UID,`'`',0,`'`',`'$GEM`')"
      # $ssoGemInsert
      Invoke-SQLCOmmand @SISDatabaseHash -SqlCommand $ssoGemInsert -WhatIf:$WhatIf
    } # END SSO.GEM check
   }
   else {
    Add-Log warning ('GSuite address {0} not vaild for {1}' -f $GEM,$user.samAccountName)
   }# END GEM address exists
  } # END SSO UID CHECK
  # ======================================================================
 } # End AD User Exists
 Write-Verbose ("||== Completed processing for: {0} | {1} {2} ==||" -f $emp.empId, $emp.namefirst, $emp.namelast)
} # End Process Escape Results

Add-Log script "Tearing down PS Sessions..."
Get-PSSession | Remove-PSSession -WhatIf:$false