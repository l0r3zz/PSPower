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
# =============================================================================
# FUNCTION LISTINGS
# =============================================================================
function Get-Profiles
{   
	<#
		.Synopsis
		Gets a list of user profiles on a computer.
	
		.Description
		This command gets a list of user profiles on a computer. The info is pipable and can be used to do other useful tasks.
		
		.Parameter computer
		The computer on which you wish to recieve profiles. (defaults to localhost)
	
		.Example
		Get-Profiles -comptuer Server01
		Gets all of the profiles from Server01
		
		.Example
		Get-Content .\computers.txt | Get-Profiles
		Returns all of the profiles for the computers listed in computers.txt
		
		.Link
		Remove-Profiles
		Author:    Scott Keiffer
		Date:      08/27/09
		Website:   http://www.cm.utexas.edu
		#Requires -Version 2.0
	#>
	[CmdletBinding()]
	param ([parameter(ValueFromPipeLine=$true)][String]$computer = "localhost")	
	process {
		$ErrorActionPreference = "SilentlyContinue"
		# Check for pipe input
		if ($_.Name) { $computer = $_.Name | Test-Host -TCPPort 135 }
		elseif ($_) { $computer = $_ | Test-Host -TCPPort 135 }
		else { $computer = Test-Host -TCPPort 135 $computer }

		$profiles=$null
		# Get the userprofile list and then filter out the built-in accounts
		if ($computer) {
			$profiles = Get-WmiObject win32_userprofile -computerName $computer | ?{$_.SID -like "s-1-5-21*"}
			if (!$?) { Write-Warning "Unable to communicate with - $computer"; continue }
		}
		else { Write-Warning "Unable to communicate with specified host."; continue }
		
		if($profiles.count -gt 0 -or ($profiles -and ($profiles.GetType()).Name -eq "ManagementObject")) {
			# Loop through the list of profiles
			foreach ($profile in $profiles) {
				Write-Verbose ("Reading profile for SID " + $profile.SID + " on $computer")
				$user = $null
				$objUser = $null
				#Create output objects
				$Output = New-Object PSObject
				# create a new secuity identifier object
				$ObjSID = New-Object System.Security.Principal.SecurityIdentifier($profile.SID)
				# Try to link the user SID to an actual user object (can fail for local accounts on remote machines, 
				#  or the user no long exists but the profile still remains)
				Try { 
					$objUser = $objSID.Translate([System.Security.Principal.NTAccount]) 
				}
				catch { 
					$user = "ERROR: Not Readable"
				}
				
				if ($objUser.Value) { $user = $objUser.Value }
				
				$Output | Add-Member NoteProperty Computer $computer
				$Output | Add-Member NoteProperty Username $user
				$Output | Add-Member NoteProperty ProfileRef $profile 
				Write-Output $Output
			}
		}
	}
}


# =============================================================================
# SCRIPT BODY
# =============================================================================


Import-Module Pscx       #Use the PowerShell Community Extensions
#$debugPreference = "Continue"

# Variables used by both the backup and the restore function
$manifestfile = ".asmanifest.txt"
$BackupList = "aspera.conf","passwd","ui.conf","sync-conf.xml",
              "docroot","group"
			  
# Perform Backup Operation				  
if ($backup.isPresent){
	# Some initisl variables 
    $homepath = pwd
    $asperaetc = "C:\Program Files (x86)\Aspera\Enterprise Server\etc"
	$asperaetcfiles = $asperaetc + "\*"
    $bundlepath =   "c:\Windows\Temp\"
	$bundlefile = $bundlepath + "$bundle.zip"
				  
	# CD over to the aspera /etc directory
    Set-Location $asperaetc|out-null
	
	# Get the list of context files and write them to a zip archive
    get-childitem $asperaetcfiles -force -inc $BackupList |
    write-Zip -output $bundlefile | out-null
	
	# Create a manifet file and append it to the zip archive
	New-Item -Path $bundlepath -Name $manifestfile -type "file" `
	    -Value "aspera_etc:$asperaetc `nbundlepath$bundlepath" |Out-Null 
	Write-Zip -Path ($bundlepath + $manifestfile) -Append `
	    -OutputPath $bundlefile 
		
	# Remove the manifest file
	Remove-Item -Path ($bundlepath + $manifestfile) |out-null
	
	# gather the user data from /etc/passwd
	$UserData = Get-Content passwd |foreach {
		$e=@{}
		$e.name,$e.unused1,[int]$e.uid,[int]$e.gid,$e.fullname,$e.adid,$e.uuid,
		    $e.homedir,$e.shell = $_ -split '[:,]'
		$e
	}
	
	# CD back to where you started
    Set-location $homepath |out-null
	write-host

# Perform Restore Operation
}elseif( $restore.isPresent){
	$bundlefile = $bundle
	Read-Archive -Path $bundlefile |Where-Object { $_.name -like $manifestfile}`
	| Expand-Archive -PassThru 
    Write-Host "Not implemented"
	
}else{
    Write-Host "Usage: asbackup -backup [-noprivdata] | -restore <bundle>"
}