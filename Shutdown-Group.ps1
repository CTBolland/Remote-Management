#REQUIRES -Version 2.0
<# 
.SYNOPSIS
    Group Shutdown of virtual and physical servers.
.DESCRIPTION
    Imports all servers in the target group. Determines if 
    server is a guest or host. Guest types shutdown via 
    "Stop-VM" through host sever. Hosts shutdown remotely 
    via "shutdown.exe". 
.INPUTS
    CSV Server list
.PARAMETER group
    Target specifc groups within the csv    
.EXAMPLE
    Shutdown group A, the VM guests running on Server01:
        .\Group-Shutdown.ps1 -group "A"

    Shutdown group B, the host Server01:
        .\Group-Shutdown.ps1 -group "B"
.NOTES               
    REQUIREMENTS:   WMI must be allowed through firewall to hosts.
                    If targeting VM's hoted on a cluster that you 
                    Install Failover Remote Management Tools.
    AUTHOR:         Craig Bolland
    CREATED:        02-26-2019 
    UPDATED:        03-19-2019 
#> 
# ----------------------------------------------------------
param ([string]$group)  
$deviceList = "c:\temp\ServerList.csv"
$logFolder = "c:\temp\logs"
$clusters = @("clusterA", "clusterB")
$hostTypes = @("*host*", "*physical*", "*cluster*")
$guest = "*guest*"
$log = ("$logFolder\Server-Shutdown-Log-" + (Get-Date).tostring("MM-dd-yyyy") + ".csv")
# -----------------------------------------------------------
if(!(Test-Path -Path $log )){New-Item -ItemType File -Path $log}
function Write-Log {
    param ([string]$code)
    if     ( $code -eq 1 ) { $status = 'SHUTTING OFF'; $message = "The virtual machine is SHUTTING OFF"  }
    elseif ( $code -eq 2 ) { $status = 'OFF'; $message = "The virtual machine is already OFF" }
    elseif ( $code -eq 3 ) { $status = 'ERROR'; $message = "Device NOT REACHABLE" }
    
    $time = "{0:HH:mm:ss}" -f (Get-Date)
    [pscustomobject]@{
    
        'DateTime' = $time
        'Status' = $status
        'Group' = $group
        'Name' = $name
        'Type' = $type
        'Host' = $hoster
        'IP' = $ip
        'Message' = $message
        
    } | Export-Csv -Path $log  -force -Append -NoTypeInformation
}    
# -----------------------------------------------------------
$servers = Import-Csv -Path $deviceList| Where-Object {$_.Group -eq $group} 
foreach ($server in $servers) {
    # csv variables
    $ip = $server.ip
    $name = $server.name
    $type = $server.type
    $hoster = $server.host
# -----------------------------------------------------------
    if (($type -eq $guest) -and ($hoster -in $clusters)) {
        $vmNode = Get-ClusterNode –Cluster $hoster | Get-ClusterResource -Name *$name | Get-VM
        if ($vmNode.state -eq "Running") {
            $vmNode | Select-Object -Index 0 | Stop-VM -Force
            Write-Log -code 1
        } 
        elseif ($vmNode.state -eq "Off") {
            Write-Log -code 2
        }
        else {
            Write-Log -code 3
        }
    }
# -----------------------------------------------------------
# if hosted on standalone host:
    elseif (($type -eq $guest) -and ($hoster -notin $clusters)) {
        if ((get-vm -name $name -ComputerName $hoster).state -eq 'Running') {
            Stop-VM –Name $name –ComputerName $hoster -Force
            Write-Log -code 1
        } 
        elseif ((get-vm -name $name -ComputerName $hoster).state -eq 'Off') {
            Write-Log -code 2
        } 
        else { 
            Write-Log -code 3
        }
    }
# -----------------------------------------------------------
#   If device is a physical server:
    elseif ($type -in $hostTypes) {
        # shutdown command
        shutdown -s -m \\$ip -t 1 /f 
        # error and is pingable:
        if ($LastExitCode -ne 0 -And (Test-Connection -computername $ip -Quiet -Count 1)) { 
            Write-Log -code 3
        }
        # error and is not pingable:
        elseif ($LastExitCode -ne 0 -And (!(Test-Connection -computername $ip -Quiet -Count 1))) {
            Write-Log -code 2
        }
        # no error:
        else { 
            Write-Log -code 1
        }
    }
}
