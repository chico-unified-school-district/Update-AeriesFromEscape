#Requires -Version 5.0
<#
.SYNOPSIS
	Add Relevant Employees to Aeries from Escape
.DESCRIPTION
	This Script Queries the Escape database for Employees that fit the criteria ('CUTA','CUMA',or 'CSEA' members) for Aeries access
	and adds them to the Aeries UNG table in the format: Domain\Username
.EXAMPLE
	Update-AeriesFromEscape.PS1 -Sandbox -Log
.EXAMPLE
	Update-AeriesFromEscape.PS1 -Log
.EXAMPLE
	Update-AeriesFromEscape.PS1 -Sandbox  -Log -Test -Verbose -Slow
.INPUTS
.OUTPUTS
.NOTES
 $AeriesQuery = "SELECT DISTINCT * FROM UGN WHERE UTY = `'adteacher`' OR  UTY = `'aduser`' ORDER BY SID"
 $AeriesQuery = "SELECT * FROM UGN WHERE UTY = `'adteacher`' OR  UTY = `'aduser`' ORDER BY SID"
.LINK
#>

[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)]
 [Alias('DC', 'Server')]
 [ValidateScript( { Test-Connection -ComputerName $_ -Quiet -Count 1 })]
 [string]$DomainController,
 # PSSession to Domain Controller and Use Active Directory CMDLETS  
 [Parameter(Mandatory = $True)]
 [Alias('ADCred')]
 [System.Management.Automation.PSCredential]$ADCredential,
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
	# Sandbox Database
	[switch]$Sandbox,
	# Run a Whatif on commands - no data will be changed
	[switch]$WhatIf
)
 
Clear-Host ; $error.clear() # Clear screen and error log.
Get-PSSession | Remove-PSSession -WhatIf:$false

# AD Domain Controller Session
$adCmdLets = 'Get-ADUser'
$adSession = New-PSSession -ComputerName $DomainController -Credential $ADCredential
Import-PSSession -Session $adSession -Module ActiveDirectory -CommandName $adCmdLets -AllowClobber

# Variables

# Imported Functions
. '.\lib\Add-Log.ps1'
. '.\lib\Run-SQLCmd.PS1'

# Use the sandbox db for testing purposes
$SISDatabaseHash.Database = $sisDb
$AeriesResults = Run-SQLCmd @SISDatabaseHash -Query 'SELECT * FROM UGN'

# Employee Management Database Connection Info
$escapeQuery = Get-Content -Path ./sql/escape-aeries-users.sql -Raw
$EscapeResults = Run-SQLCmd @EscapeDatabaseHash -Query $escapeQuery

# Active Directory Employee Objects
$employeeParams = @{
 filter     = { 
  (employeeID -like "*") -and 
  (mail -like "*@chicousd.org") -and
  (department -ne 380)
 }
 Properties = 'mail', 'employeeID', 'extensionAttribute1'
 SearchBase = 'OU=Employees,OU=Users,OU=Domain_Root,DC=chico,DC=usd'
}
$ADEmployeeAccounts = Get-ADUser @employeeParams

foreach ($emp in $EscapeResults) {
 # Begin Process Escape Results
	Write-Verbose ("=== Started processing for: {0} | {1} {2} ===" -f $emp.empid, $emp.namefirst, $emp.namelast)
 Write-Debug "Process?"
	$empId = $emp.empid
	$user = $ADEmployeeAccounts.Where( { $_.employeeID -eq $empId })
	if (!$user) {
  Write-Verbose "$empId,User not found in AD" 
 }
 else {
  # Begin AD User Exists
		# EmpID match found - Checking UGN
		# Setting Variables
		$EM = $user.mail
		$SID = $empID
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
   Write-Verbose "$FN $LN $empID not in UGN Table."
			# Add UN (Username) to UGN
			$UGNInsert = @"
			INSERT INTO $sisDb.dbo.UGN([UID], UN, SY, TY, UTY, HT, CD, EM, FN, LN, CDT, SID, PLC)
			VALUES  ((SELECT MAX([UID]) + 1 FROM UGN),`'$UN`',`'$SY`',$TY,`'$UTY`',$HT,GETDATE(),
			`'$EM`',`'$FN`',`'$LN`',GETDATE(),$SID,GETDATE())
"@ # Indentation causes error

   Add-Log update "Adding '$EM' '$empID' to $sisDb\UGN TABLE"
   Run-SQLCmd @SISDatabaseHash -Query $UGNInsert -WhatIf:$WhatIf
  } # End INSERT User in UGN Table

  if ( ($bargUnitId -eq 'CUTA') -or
   ($bargUnitId -eq 'CUMA') -or
   ($bargUnitId -eq 'CSEA') ) {
   # BEGIN INSERT/UPDATE User STF Table data
   $STFIUserCheck = Run-SQLCmd @SISDatabaseHash -Query "SELECT EM,U8 FROM STF WHERE ID = $empID"
   if (!$STFIUserCheck) {
    # Begin INSERT New STF Entry
    $STFInsertUser = "INSERT INTO STF (ID,FN,LN,EM,U8) VALUES (`'$empID`',`'$FN`',`'$LN`',`'$EM`',`'$U8`')"
    Add-Log insert "$STFInsertUser"
    Run-SQLCmd @SISDatabaseHash -Query $STFInsertUser -WhatIf:$WhatIf
   } # END INSERT New STF Entry

   if ( $STFIUserCheck.em -ne $user.mail ) {
    # Begin CHECK/UPDATE EMAIL
    Write-Verbose "STF.EM ($($STFIUserCheck.em)) not equal for $EM $empID"
    $STFEMUpdate = "UPDATE STF SET STF.EM = `'$($user.mail)`' WHERE STF.ID = $empID"
    Add-Log update "$STFEMUpdate"
    Run-SQLCmd @SISDatabaseHash -Query $STFEMUpdate -WhatIf:$WhatIf
   } # End CHECK/UPDATE EMAIL

   if ( $STFIUserCheck.u8 -ne $emp.u8 ) {
    # Begin CHECK/UPDATE U8
    Write-Verbose "Aeries STF.u8 ($($STFIUserCheck.u8)) not equal to Escape: $U8 for $empID"
    $STFU8Update = "UPDATE STF SET STF.U8 = `'$U8`' WHERE STF.ID = $empID"
    Add-Log update "$STFU8Update"
    Run-SQLCmd @SISDatabaseHash -Query $STFU8Update -WhatIf:$WhatIf
   } # End CHECK/UPDATE U8

   # INSERT/UPDATE UGN.UID

  } # END INSERT/UPDATE User STF Table data
  # ======================================================================
 } # End AD User Exists
 Write-Verbose ("=== Completed processing for: {0} | {1} {2} ===" -f $emp.empid, $emp.namefirst, $emp.namelast)
} # End Process Escape Results

Add-Log script "Tearing down PS Sessions..."
Get-PSSession | Remove-PSSession -WhatIf:$false