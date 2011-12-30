# FileName: asbackup.ps1
# Script Name: asbackup
# =============================================================================
# Company: Asperasoft.com
# Email:   geoffw@asperasoft.com
# =============================================================================
# Created: [12/26/2011]
# Author: Geoff White
# Arguments:
# =============================================================================
# Purpose: Backup or Migrate an Enterprise Server Instance to another Machine
#
#
# =============================================================================
[CmdletBinding()]
Param (
    [switch]$backup,
    [switch]$restore,
    [switch]$noprivdata,
    [string[]]$bundle
)
Import-Module Pscx       #Use the PowerShell Community Extensions
#$debugPreference = "Continue"

if ($backup.isPresent){
    $homepath = pwd
    $asperaetc = "C:\Program Files (x86)\Aspera\Enterprise Server\etc"
	$asperaetcfiles = $asperaetc + "\*"
    $bundlepath =   "c:\Windows\Temp\$bundle" + ".tar"
    $BackupList = "aspera.conf","passwd","ui.conf","sync-conf.xml",
				  "docroot","group"   
    Set-Location $asperaetc|out-null
    get-childitem $asperaetcfiles -force -inc $BackupList |
    write-tar -output $bundlepath | out-null
    Set-location $homepath |out-null
}elseif( $restore.isPresent){
    Write-Host "Not implemented"
}else{
    Write-Host "Usage: asbackup -backup [-noprivdata] | -restore <bundle>"
}