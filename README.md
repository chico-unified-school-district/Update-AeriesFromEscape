# Update-AeriesFromEscape
This process queries the Escape database for Employees that fit the criteria ('CUTA','CUMA',or 'CSEA' members as well as HREmployment.PersonTypeId IN (1,2,4)) for Aeries access and adds them to the Aeries UNG table in the format: Domain\Username

## Requirements
- PowerShell modules: `CommonScriptFunctions`, `dbatools`, and `ActiveDirectory` (only `Get-ADUser` and `Set-ADUser` are imported).

## Parameters
| Parameter | Alias | Description |
|---|---|---|
| `ADCredential` | `ADCred` | Credential passed to the Active Directory cmdlets (`Set-ADData -cred`). |
| `StaffOrgUnit` | `OU` | Staff organizational unit. |
| `SISServer` / `SISDatabase` / `SISCredential` | | Aeries (Student Information System) SQL server, database, and credential. |
| `EscapeServer` / `EscapeDatabase` / `EscapeCredential` | | Escape employee SQL server, database, and credential. |
| `WhatIf` | `wi` | Test run; no data is changed. |

Default parameter values are defined in `params.ps1`.

## Example
```powershell
.\Update-AeriesFromEscape.PS1 -ADCred $adCred -OU 'OU=Employees,OU=Users,DC=OurDistrict,DC=org' `
 -SISServer SISServer -SISDatabase SISDB -SISCredential $SISCred `
 -EscapeServer EscServer -EscapeDatabase EscDB -EscapeCredential $EscapeCred -WhatIf
```