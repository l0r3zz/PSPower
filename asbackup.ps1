# FileName: asbackup.ps1
# Script Name: asbackup
# =============================================================================
# Company: Asperasoft.com
# Email:   geoffw@asperasoft.com
# =============================================================================
# Created: [12/26/2011]
# Author: Geoff White
# Arguments:
# Usage: ascbkup   --backup [--no-priv-data] | --restore    <bundle>
#
#        <bundle>       is some form of archive file that contains/will contain 
#                       full user data from the source Server
#
#        --backup       Backup all the configuration and user credential data to
#                       <bundle>
#
#        --restore      Restore all configuration and user credential data from
#                       <bundle> to the destination Server
#
#        --no-priv-data Do not back up (or restore) sensitive  user data  
#                       (such as ssh private keys)  if present
#        --silent       Perform ootentially disruptive actions without prompting
#                        user for input.
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
	[switch]$silent,
    [string[]]$bundle
)
# =============================================================================
# FUNCTION LISTINGS
# =============================================================================

# *****************************************************************************
# Count-Object - return the number of object passed on the input stream
# *****************************************************************************

function Count-Object {
	begin { $count =0 }
	process { $count +=1 }
	end { $count }
}

# *****************************************************************************
# quiet-services - Quell aspera services that will lock files
#
# note: this code creates the asperacentralService variable 
# with scoping originating in the PARENT of this called function!
# This is an easy way to exppose the variable to the unquite-services
# function
# *****************************************************************************

function quiet-services {
	# Stopping asperacentral can abort transfers that are taking place, prompt
	# user before proceeding.
	Set-variable -Name asperacentralService -Value (Get-Service -Name asperacentral)-Scope 1
	if (-not $silent.isPresent) {
	    $ans = Read-Host "Stopping asperacentral proceed?  {yes=ENTER/No=N]: "
		# Abort if user types anything except return
		if ($ans ) {throw (New-Object `
		    System.Management.Automation.ActionPreferenceStopException) }
	}
		
	# Stop the asperacentral process if it is running so that we can backup preferences.db
	
	#check the status of the asperacentral service
	if ($asperaCentralService.status -eq "Running"){
		Stop-service asperacentral 
	}else{
		Write-Host "Asperacentral is not running"
	}
}

function unquiet-services {
	# Start asperacentral back up only if it was running before
	if ($asperaCentralService.status-eq "Running"){
		Start-Service asperacentral
	}
}
# *****************************************************************************
# Get-Profiles - Gets a list of user profiles on a computer.
# *****************************************************************************
function Get-Profiles
{   
	<#
		.Synopsis
		Gets a list of user profiles on a computer.
	
		.Description
		This command gets a list of user profiles on a computer. 
		The info is pipable and can be used to do other useful tasks.
		
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
		#if ($_.Name) { $computer = $_.Name | Test-Host -TCPPort 135 }
		#elseif ($_) { $computer = $_ | Test-Host -TCPPort 135 }
		#else { $computer = Test-Host -TCPPort 135 $computer }

		$profiles=$null
		# Get the userprofile list and then filter out the built-in accounts
		if ($computer) {
			$profiles = Get-WmiObject win32_userprofile -computerName $computer|
			    ?{$_.SID -like "s-1-5-21*"}
			if (!$?) { Write-Warning "Unable to communicate with - $computer"; 
			continue }
		}
		else { Write-Warning "Unable to communicate with specified host."; 
		continue }
		
		if($profiles.count -gt 0 -or ($profiles -and 
		    ($profiles.GetType()).Name -eq "ManagementObject")) {
			# Loop through the list of profiles
			foreach ($profile in $profiles) {
				Write-Verbose ("Reading profile for SID " + $profile.SID + 
				    " on $computer")
				$user = $null
				$objUser = $null
				#Create output objects
				$Output = New-Object PSObject
				# create a new secuity identifier object
				$ObjSID = New-Object `
				    System.Security.Principal.SecurityIdentifier($profile.SID)
				# Try to link the user SID to an actual user object 
				# (can fail for local accounts on remote machines, 
				#  or the user no long exists but the profile still remains)
				Try { 
					$objUser = $objSID.Translate(
					    [System.Security.Principal.NTAccount]) 
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


# Variables used by both the backup and the restore function
$manifestfile = ".asmanifest.txt"
$BackupList = "aspera.conf","passwd","ui.conf","sync-conf.xml",
              "docroot","group", "preferences.db"
			  
#Find the install directory for the aspera products
$InstallDir = (Get-ChildItem -Path `
    "Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Aspera\"`
	|ForEach-Object {Get-Childitem  $_.pspath `
	}|ForEach-Object {Get-ItemProperty $_.pspath}).InstallDir
	
# Find the Path to the Users Directories
$U = [string]( (Get-childitem Env:USERPROFILE).value)
$UserDirPath = $U.substring(0,$U.lastindexof("\")+1)

			  
# Perform Backup Operation				  
if ($backup.isPresent){
	# Some initisl variables 
    $homepath = pwd
    $asperaetc = $InstallDir+"etc"
	$asperaetcfiles = $asperaetc + "\*"
    $bundlepath =   "c:\Windows\Temp\"
	$bundlefile = $bundlepath + "$bundle.zip"
	
	trap [System.Management.Automation.ActionPreferenceStopException] { 
	      cd $homepath;Write-Output "Aborting.`n"; exit }
	
	Set-Location $bundlepath |Out-Null	
	#Create the zip archive file
	Set-Content $bundlefile ("PK" + [char]5 + [char]6 + ("$([char]0)" * 18 ))
	
	# CD over to the aspera /etc directory
    Set-Location $asperaetc|out-null
	
	quiet-services

	# Get the list of context files and write them to a zip archive
	foreach ($f in Get-ChildItem -ErrorVariable +ziperr $BackupList 2> $null) { 
	    Write-Zip -inputObject $f -Append -OutputPath $bundlefile }
		
	unquiet-services
	
	foreach ($e in $ziperr ) {Write-Host "Zip error: $e"}

	
	# gather the user data from /etc/passwd
	if (Test-Path passwd) {
		$UserData = Get-Content passwd |foreach {
			$e=@{}
			$e.name,$e.unused1,[int]$e.uid,[int]$e.gid,$e.fullname,$e.adid,$e.uuid,
			    $e.homedir,$e.shell = $_ -split '[:,]'
			$e
		}
		$UserMap = @{}
		# Build a hash of names in the /etc file
		foreach ($u in $UserData ) { $UserMap.($u.name) = 1 }
		# See if there are any user profiles that match the names in the passwd file
		$UserProfiles = Get-Profiles | foreach {if ($userMap.($_.Username)) 
		    {$_}}
		if ( $UserProfiles) {
			Write-Host "User Profiles are present"
		} else {
			Write-Host "No User Profiles are present"
		}
	}else {
		Write-Host "No /etc/passwd file found. Create some users!"
	}
	

	Set-Location $bundlepath
	# Create a manifest file and add it to  the zip archive
	New-Item -Force -Name $manifestfile -type "file" `
	    -Value "aspera_etc=$asperaetc `nbundlepath=$bundlepath" |Out-Null
	# Add Userdata info for found uers in the passsword file
	# Ugly hack to keep add-content from appending newline chars :(
	Add-Content -Path $manifestfile ([Byte[]][Char[]] "`nuser_profile= [")`
	    -Encoding Byte
	foreach ($u in $UserProfiles) {
		Add-Content -Path $manifestfile ([Byte[]][Char[]]`
		  "{'username':`'$($u.Username)`','localpath':`'$($u.ProfileRef.LocalPath)`','sid':`'$($u.ProfileRef.SID)`'},")`
		  -Encoding Byte
		  
		 # Get the list of context files and write them to a zip archive
		 $sshdirpath  = $u.profileRef.localPath + "\.ssh\*"
	
	    Write-Zip -Path $sshdirpath -Append -Errorvariable +ziperr -OutputPath $bundlefile | out-null
	}
	Add-Content -Path $manifestfile "]"

	Get-ChildItem $manifestfile | Write-Zip -flat -Append -OutputPath $bundlefile | out-null 
	# Remove the manifest file
	Remove-Item -Path  ($bundlepath + $manifestfile) |out-null
	
	# CD back to where you started
    Set-location $homepath |out-null
	write-host

# Perform Restore Operation
}elseif( $restore.isPresent){
	$bundlefile = $bundle
	$restorepath = "Windows\Temp\"
	
	# Retrieve the manifest file containing the Metadata
	Read-Archive -Path $bundlefile |Where-Object { $_.name -like $manifestfile}`
	| Expand-Archive -PassThru | out-null
	
	# Parse the Metadata into a hash table based on keys in the manifiest file
	$ArchiveMetaData = @{}
	$restorebundle = $restorepath + $manifestfile 
	get-Content $restorebundle | foreach {
	    $key,$value = $_ -split '='
		$ArchiveMetaData.$key = $value
	}
	Remove-Item -Path $restorebundle |out-null
	
	quiet-services
	
	# Retrieve and instantiate the contents of /etc
	# Note we have to do this kluge because of a bug in the Expand-Archive 
	# Commandlet that has a broken -EntryPath switch 
	$NumberOfFiles = Expand-Archive -Path $bundlefile -PassThru | Count-Object
	$IndexRange = 1..$numberOfFiles
	$bundlepath = $ArchiveMetaData.bundlepath 
	Expand-Archive -Path $bundlefile -Index $IndexRange -OutputPath `
	    $bundlepath 
		
	unquiet-services 
	
    Write-Host "Writing restore to $bundlepath  for debugging"
	
}else{
    Write-Host "Usage:
	   asbackup -silent |-backup [-noprivdata] | -restore <bundle>"
}