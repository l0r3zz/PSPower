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
	# Some initisl variables 
    $homepath = pwd
    $asperaetc = "C:\Program Files (x86)\Aspera\Enterprise Server\etc"
	$asperaetcfiles = $asperaetc + "\*"
    $bundlepath =   "c:\Windows\Temp\"
	$bundlefile = $bundlepath + "$bundle.zip"
	$manifestfile = ".asmanifest.txt"
    $BackupList = "aspera.conf","passwd","ui.conf","sync-conf.xml",
				  "docroot","group"
				  
	# CD over to the aspera /etc directory
    Set-Location $asperaetc|out-null
	
	# Get the list of context files and write them to a zip archive
    get-childitem $asperaetcfiles -force -inc $BackupList |
    write-Zip -output $bundlefile | out-null
	
	# Create a manifet file and append it to the zip archive
	New-Item -Path $bundlepath -Name $manifestfile -type "file" `
	    -Value "bundlepath:$bundlepath"
	Write-Zip -Path ($bundlepath + $manifestfile) -Append `
	    -OutputPath $bundlefile 
		
	# Remove the manifest file
	Remove-Item -Path ($bundlepath + $manifestfile) |out-null
	
	# CD back to where you started
    Set-location $homepath |out-null
	
}elseif( $restore.isPresent){
    Write-Host "Not implemented"
	
}else{
    Write-Host "Usage: asbackup -backup [-noprivdata] | -restore <bundle>"
}