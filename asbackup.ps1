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

Function asbackup {
    [CmdletBinding()]
    Param (
            [switch]$backup,
            [switch]$restore,
            [switch]$noprivdata,
            [Parameter(Mandatory=$True)]
            [string[]]
            $bundle
    )
            
    cd 'C:\Program Files (x86)\Aspera\Enterprise Server\etc'
    get-childitem * -inc aspera.conf,passwd,ui.conf,sync-conf.xml,docroot,group`| 
    write-tar -output "c:\Windows\Temp\$bundle" + ".tar"
}