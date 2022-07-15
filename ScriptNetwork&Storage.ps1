
<#
This will capture
 .network dump
 .memory dump
 .xperf
 .Disk.sys trace
 .iSCSI trace
 .MPIO/DSM trace
 .System.evtx
#>


#region LogPath
$DefaultDrive = "c:\"
$logDir = "Logs"
$DefaultLogDir = $DefaultDrive + $logDir
if (!(test-path -path $DefaultLogDir)) {
    New-Item -Name $logDir -ItemType Directory -path $DefaultDrive -ErrorAction Stop

}

#endregion

#region Filter

$eventCapTime = -1
$start = (get-date).AddMinutes($eventCapTime)

$filter153 = @{

    LogName      = "System"
    ProviderName = "disk"
    StartTime    = $start 
    Level        = 3
    ID           = 153
  
}
#endregion

#region StorageTraces
[ScriptBlock]$StorageTracesStart = { 
    
    "Storport"
    logman create trace "storport" -ow -o $DefaultLogDir"\storport.etl" -p "Microsoft-Windows-StorPort" 0xffffffffffffffff 0xff -nb 16 16 -bs 1024 -mode Circular -f bincirc -max 1024 -ets
    "Disk Trace"
    logman create trace "minkernel_storage_Disk" -ow -o $DefaultLogDir"\minkernel_storage_disk.etl" -p `{945186BF-3DD6-4F3F-9C8E-9EDD3FC9D558`} 0xffffffffffffffff 0xff -nb 16 16 -bs 1024 -mode Circular -f bincirc -max 1024 -ets
    "iSCSI Trace"
    logman create trace "drivers_storage_iSCSI" -ow -o $DefaultLogDir"\drivers_storage_iSCSI.etl" -p `{1BABEFB4-59CB-49E5-9698-FD38AC830A91`} 0xffffffffffffffff 0xff -nb 16 16 -bs 1024 -mode Circular -f bincirc -max 1024 -ets
    "MPIO Trace"
    logman create trace "drivers_storage_MPIO" -ow -o $DefaultLogDir"\drivers_storage_MPIO.etl" -p `{8E9AC05F-13FD-4507-85CD-B47ADC105FF6`} 0xffffffffffffffff 0xff -nb 16 16 -bs 1024 -mode Circular -f bincirc -max 1024 -ets
    "DSM Trace"
    logman create trace "drivers_storage_DSM" -ow -o $DefaultLogDir"\drivers_storage_DSM.etl" -p `{DEDADFF5-F99F-4600-B8C9-2D4D9B806B5B`} 0xffffffffffffffff 0xff -nb 16 16 -bs 1024 -mode Circular -f bincirc -max 1024 -ets

}


[ScriptBlock]$StorageTracesStop = {

    logman stop "storport" -ets
    logman stop "minkernel_storage_Disk" -ets
    logman stop "drivers_storage_iSCSI" -ets
    logman stop "drivers_storage_MPIO" -ets
    logman stop "drivers_storage_DSM" -ets

}

#endregion

#region NetworkTrace

[scriptblock]$NetworkTarceStart = {
     
    $nameHost = hostname
    $traceName = $nameHost + ".etl"
    netsh trace start capture=yes maxsize=2048 filemode=circular overwrite=yes report=no tracefile= $DefaultLogDir"\$traceName"
}

[scriptblock]$NetworkTarceStop ={Netsh trace stop}

#endregion

#region Job

$job = {

    [ScriptBlock]$StorageTracesStop = {

        logman stop "storport" -ets
        logman stop "minkernel_storage_Disk" -ets
        logman stop "drivers_storage_iSCSI" -ets
        logman stop "drivers_storage_MPIO" -ets
        logman stop "drivers_storage_DSM" -ets
    
    }

    [scriptblock]$NetworkTarceStop ={Netsh trace stop}
    
    $eventCapTime = -1
    $start = (get-date).AddMinutes($eventCapTime)

    $filter153 = @{

        LogName      = "System"
        ProviderName = "disk"
        StartTime    = $start 
        Level        = 3
        ID           = 153
      
    }

    while (1) {
        $errorMessage = Get-WinEvent -FilterHashtable $filter153 -MaxEvents 1 -ErrorAction SilentlyContinue
        if ($errorMessage) {
            .$StorageTracesStop
            .$NetworkTarceStop
            Write-Host -ForegroundColor yellow "Issue captured & Collected Traces."
            break;
        }
    }   

}#JobEnd

#endregion


#region iSCSIFunction

function get-iSCSIData($path) {

    try {

        Get-ChildItem $path -ErrorAction Stop
        Write-Host -ForegroundColor yellow "Starting Traces"
        .$StorageTracesStart
        .$NetworkTarceStart
        
       
        $job = Start-job -ScriptBlock $job

        do {
               
            receive-job -job  $job
            Write-Host -ForegroundColor Green "To check job status press 1"
            Write-Host -ForegroundColor Green "To stop the trace press 2"
            
            $command = read-host "Select option"
            switch ($command) {

                1 { (Get-job -Id $job.Id).JobStateInfo; break }
                2 { 
                    if ((Get-Job -id $job.ID).state -eq "Completed") {

                        break;
                    }
                    else {
                        Write-Host -ForegroundColor yellow "Throwing Dummy Event 153 to stop the job $($job.Id)."
                        Write-Host -ForegroundColor yellow "Current State of the Job"
                        get-job | FT Id, Name, State
                        write-eventlog -logname System -source "disk" -EntryType warning -EventID 153 -message "I am dummy!" 
                        "Waiting for 5 seconds"
                        start-sleep -s 5
                        get-job | FT Id, Name, State

                    }


                    break;
                }

                default { Write-Host -ForegroundColor red "Select Valid Option" }
 
            }#switch



        }while ($command -ne 2)
        
        receive-job -job  $job
        get-job | remove-job -force

         
        

    }
    catch {


        Write-Host -ForegroundColor yellow "Exception Occured."
        Write-Host $_.Exception.Message -ForegroundColor Red
        .$StorageTracesStop
        get-job | remove-job -force

    }

    finally{

         $logDirName = Get-Date -Format HH_mm_ss
         New-Item -Name $logDirName -ItemType dir -Path $DefaultLogDir"\"
         set-location -Path $DefaultLogDir
         Move-Item -Path $DefaultLogDir"\*.*" -Destination $DefaultLogDir"\"$logDirName 
    }

  


}
#endregion

get-iSCSIData -path $DefaultLogDir