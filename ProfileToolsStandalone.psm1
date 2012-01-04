<#
	CBitsAPI: Mass Profile Tools for Windows Vista/7
	Author: Scott Keiffer
	Date: 09/03/09
	Website: http://www.cm.utexas.edu
#>

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

function Remove-Profiles
{
	<#
		.Synopsis
		Deletes a list of profiles from a computer (vista and up only)
	
		.Description
		This command deletes all profiles from a given computer. Or all profiles that have been piped in from the Get-Profiles command.
		
		.Parameter computer
		The computer on which you wish to delete profiles from. (defaults to localhost) Piped input always takes presidence.
		
		.parameter commit
		This switch is used to write the changes. If switch is missing, no profiles will be deleted.
	
		.Example
		Remove-Profiles -comptuer Server01 -commit
		Deletes all of the profiles from Server01.
		
		.Example
		Get-Content .\computers.txt | Get-Profiles | Remove-Profiles
		Does a dry run of deleteing all user profiles from all of the computers listed in computers.txt
		
		.example
		Get-Content .\computers.txt | Get-Profiles | ?{$_.Username -like "*Billy"} | Remove-Profiles -commit
		Deletes Billy's user profile from all comptuers listed in computers.txt
		
		.Link
		Get-Profiles
		AUTHOR:    Scott Keiffer
		Date:      08/28/09
		Website:   http://www.cm.utexas.edu
		#Requires -Version 2.0
	#>
	[CmdletBinding()]
	param ([parameter(ValueFromPipeLine=$true)][String]$computer = "localhost", [Switch]$commit)
	begin {
		$commitText=""
		if(!$commit) { $commitText="[TRIAL RUN] " }
		
		#function that will call self with good piped info.
		function CallSelf($computer)
		{
			$command = "Get-Profiles -computer $computer | Remove-Profiles"
			if ($commit) { $command += " -commit" }
			if ($VerbosePreference -eq "Continue") { $command += " -verbose" }
			Invoke-Expression -Command $command
		}
    }
    process {
        # if piped info is present, use it.
        if ($_) {
			#If the profile reference exists and is the right type, call it's delete method.
			if ($_.profileRef -and ($_.profileRef -is [System.Management.ManagementBaseObject])) {
				$success = $true
				if ($commit) { 
					Write-Verbose ("Attempting to delete profile for user: " + $_.Username)
					# The delete process can take some time per profile, timeout is also very high, be patient. 
					try { $_.profileRef.Delete() }
					catch { $success=$false }
				}
				if($success) {
					Write-Host $commitText"Deleted Profile with Username:" $_.Username "From:" $_.Computer
				}
				else {
					Write-Warning ("Unable to Delete or Fully Delete Profile (possibly logged in, or file in use) with Username: " + $_.Username + " From: " + $_.Computer)
				}
			}
			#If the profile reference does not exist, assume piped input is a list of computers. 
			else {
				#filter out offline hosts, run get-profiles, and rerun remove-profiles. 
				if ($_.Name) { $computer = $_.Name | Test-Host -TCPPort 135 }
        		elseif ($_) { $computer = $_ | Test-Host -TCPPort 135 }
        		else { $computer = Test-Host -TCPPort 135 $computer }
				
				if ($computer) {
					CallSelf($computer)
				}
				else {
					Write-Warning "Unable to communicate with specified host.";
				}
			}
        }
        else { 
			#No piped input so lets use get-profiles and recall self for localhost
			CallSelf($computer)
        }
    }
}

function Test-Host
{
    <#
        .Synopsis
            Test a host for connectivity using either WMI ping or TCP port
        .Description
            Allows you to test a host for connectivity before further processing
        .Parameter Server
            Name of the Server to Process.
        .Parameter TCPPort
            TCP Port to connect to. (default 135)
        .Parameter Timeout
            Timeout for the TCP connection (default 1 sec)
        .Parameter Property
            Name of the Property that contains the value to test.
        .Example
            # To test a list of hosts.
            cat ServerFile.txt | Test-Host | Invoke-DoSomething
        .Example
            # To test a list of hosts against port 80.
            cat ServerFile.txt | Test-Host -tcp 80 | Invoke-DoSomething   
        .Example
            # To test the output of Get-ADComputer using the dnshostname property
            Get-ADComputer | Test-Host -property dnsHostname | Invoke-DoSomething    
        .OUTPUTS
            Object
        .INPUTS
            object
        .Link
            N/A
		NAME:      Test-Host
		AUTHOR:    YetiCentral\bshell
		Website:   www.bsonposh.com
		LASTEDIT:  02/04/2009 18:25:15
        #Requires -Version 2.0
    #>
    [CmdletBinding()]
    
    Param(
        [Parameter(ValueFromPipeline=$true,Mandatory=$True)]
        $ComputerName,
        [Parameter()]
        [int]$TCPPort,
        [Parameter()]
        [int]$timeout=500,
        [Parameter()]
        [string]$property
        )
    Begin
    {
        function TestPort {
            Param($srv,$tport,$tmOut)
            Write-Verbose " [TestPort] :: Start"
            Write-Verbose " [TestPort] :: Setting Error state = 0"
            $ErrorActionPreference = "SilentlyContinue"
            
            Write-Verbose " [TestPort] :: Creating [system.Net.Sockets.TcpClient] instance"
            $tcpclient = New-Object system.Net.Sockets.TcpClient
            
            Write-Verbose " [TestPort] :: Calling BeginConnect($srv,$tport,$null,$null)"
            $iar = $tcpclient.BeginConnect($srv,$tport,$null,$null)
            
            Write-Verbose " [TestPort] :: Waiting for timeout [$timeout]"
            $wait = $iar.AsyncWaitHandle.WaitOne($tmOut,$false)
            # Traps     
            trap 
            {
                Write-Verbose " [TestPort] :: General Exception"
                Write-Verbose " [TestPort] :: End"
                return $false
            }
            trap [System.Net.Sockets.SocketException]
            {
                Write-Verbose " [TestPort] :: Exception: $($_.exception.message)"
                Write-Verbose " [TestPort] :: End"
                return $false
            }
            if(!$wait)
            {
                $tcpclient.Close()
                Write-Verbose " [TestPort] :: Connection Timeout"
                Write-Verbose " [TestPort] :: End"
                return $false
            }
            else
            {
                Write-Verbose " [TestPort] :: Closing TCP Sockett"
                $tcpclient.EndConnect($iar) | out-Null
                $tcpclient.Close()
            }
            if($?){Write-Verbose " [TestPort] :: End";return $true}
        }
        function PingServer {
            Param($MyHost)
            Write-Verbose " [PingServer] :: Pinging $MyHost"
            $pingresult = Get-WmiObject win32_pingstatus -f "address='$MyHost'"
            Write-Verbose " [PingServer] :: Ping returned $($pingresult.statuscode)"
            if($pingresult.statuscode -eq 0) {$true} else {$false}
        }
    }
    Process
    {
        Write-Verbose ""
        Write-Verbose " Server   : $ComputerName"
        if($TCPPort)
        {
            Write-Verbose " Timeout  : $timeout"
            Write-Verbose " Port     : $TCPPort"
            if($property)
            {
                Write-Verbose " Property : $Property"
                if(TestPort $ComputerName.$property -tport $TCPPort -tmOut $timeout){$ComputerName}
            }
            else
            {
                if(TestPort $ComputerName -tport $TCPPort -tmOut $timeout){$ComputerName} 
            }
        }
        else
        {
            if($property)
            {
                Write-Verbose " Property : $Property"
                if(PingServer $ComputerName.$property){$ComputerName} 
            }
            else
            {
                Write-Verbose " Simple Ping"
                if(PingServer $ComputerName){$ComputerName}
            }
        }
        Write-Verbose ""
    }
}

Export-ModuleMember Get-Profiles, Remove-Profiles
