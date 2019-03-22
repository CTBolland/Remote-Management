param ([string]$group)  

$group = "a"
$deviceList = "c:\scripts\eaton\server\test2.csv"
$logFolder = "c:\scripts\eaton\server\logs"
$clusters = @("asgard", "midgard")
$pTypes = @("host", "physical", "cluster*")
$guest = "guest"
$log = ("$logFolder\Server-Shutdown-Log-" + (Get-Date).tostring("MM-dd-yyyy") + ".csv")

# --------------------------------------------------------------
if(!(Test-Path -Path $log )){New-Item -ItemType File -Path $log}

function Write-Log {
    param ([string]$code)

    if     ( $code -eq 1 ) { $status = 'SHUTTING OFF'; $message = "The virtual machine is shutting down"  }
    elseif ( $code -eq 2 ) { $status = 'OFF'; $message = "The virtual machine is already in the specified state." }
    elseif ( $code -eq 3 ) { $status = 'ERROR'; $message = "Device not reachable" }

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

# --------------------------------------------------------------

$servers = Import-Csv -Path $deviceList| Where-Object {$_.Group -eq $group} 
foreach ($server in $servers) {
    # csv variables
    $ip = $server.ip
    $name = $server.name
    $type = $server.type
    $hoster = $server.host

# --------------------------------------------------------------
# if hosted within failover cluster:
    if (($type -eq $guest) -and ($hoster -in $clusters)) {
       $vmNode = Get-ClusterNode –Cluster $hoster | Get-ClusterResource -Name *$name 
        $vmNode | Select-Object -Index 0 | Get-VM | Stop-VM -Force -WarningVariable a
        if ($a -eq $null) { Write-Log -code 1 } 
        else { Write-Log -code 2 }
    }
# --------------------------------------------------------------
# if hosted on standalone host:
    elseif (($type -eq $guest) -and ($hoster -notin $clusters)) {
        if ((get-vm -name $name -ComputerName $hoster).state -eq 'Running') {
            Stop-VM –Name $name –ComputerName $hoster -Force; Write-Log -code 1 }
        elseif ((get-vm -name $name -ComputerName $hoster).state -eq 'Off') { Write-Log -code 2 }
        else { Write-Log -code 3 }
    }
# --------------------------------------------------------------
#   If device is a physical server:
    elseif ($type -in $pTypes) {
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


