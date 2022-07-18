<#
Version 1.0
This will capture
 .network dump
 .memory dump
 .xperf
 .Disk.sys trace
 .iSCSI trace
 .MPIO/DSM trace
 .perfmon
 .storport
 .System.evtx
 .Application.evtx
#>


#region LogPath
$DefaultDrive = "c:\"
$logDir = "Logs"
$DefaultLogDir = $DefaultDrive + $logDir
$xperfToolLocation = "C:\Toolkit"
if (!(test-path -path $DefaultLogDir)) {
    New-Item -Name $logDir -ItemType Directory -path $DefaultDrive -ErrorAction Stop

}



#endregion

#region Filter
$EventLogName = "System"
$EventProviderName = "disk"
$EventLevel = "3"
$EventID = "153"
$EventEntryType = "Warning"

#endregion

#region EventLogs
[scriptblock]$copyEventLogs = {
    
    $timeStamp = get-date -Format "MM_dd_yyyy_HH_mm"
   
    $systemLogPath = $timeStamp + "_System.evtx"
    $systemLogPath = $DefaultLogDir + "\" + $systemLogPath
    
    $applicationLogPath = $timeStamp + "_Application.evtx"
    $applicationLogPath = $DefaultLogDir + "\" + $applicationLogPath
     
    wevtutil.exe epl System $systemLogPath
    wevtutil.exe epl Application $applicationLogPath
    Get-Date -Format "dddd MM/dd/yyyy HH:mm K" | Out-File -FilePath  $DefaultLogDir"\TimeZone.txt"
    (Get-TimeZone) | Out-File -FilePath $DefaultLogDir"\TimeZone.txt" -Append
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
     
    "Network Trace"
    $nameHost = hostname
    $traceName = "NetworkTrace_" + $nameHost + ".etl"
    netsh trace start capture=yes maxsize=2048 filemode=circular overwrite=yes report=disabled tracefile= $DefaultLogDir"\$traceName"
}

[scriptblock]$NetworkTarceStop =
{ Netsh trace stop }

#endregion

#region Xperf
[ScriptBlock]$XperfStart = {

    "Xperf"
    $timeStamp = get-date -Format HH_mm_ss
    $XperfKernelETL = "Start_Xperf" + $timeStamp + "_kernel.etl"
    $XperfDir = $DefaultLogDir + "\" + $XperfKernelETL
    Set-Location -Path $xperfToolLocation
    .\xperf -on PROC_THREAD+LOADER+FLT_IO_INIT+FLT_IO+FLT_FASTIO+FLT_IO_FAILURE+FILENAME+FILE_IO+FILE_IO_INIT+DISK_IO+HARD_FAULTS+DPC+INTERRUPT+CSWITCH+PROFILE+DRIVERS+Latency+DISPATCHER  -stackwalk MiniFilterPreOpInit+MiniFilterPostOpInit+CSwitch+ReadyThread+ThreadCreate+Profile+DiskReadInit+DiskWriteInit+DiskFlushInit+FileCreate+FileCleanup+FileClose+FileRead+FileWrite+FileFlush -BufferSize 4096 -MaxBuffers 4096 -MaxFile 4096 -FileMode Circular -f $XperfDir 
}

[scriptblock]$XperfStop = {
    Set-Location -Path $xperfToolLocation
    .\Xperf -d $DefaultLogDir"\Xperf_WaitAnalysis.ETL"

}
#endregion

#region Perfmon
[scriptblock]$perfmonStart = {
    
    "Perfmon"
    $nameHost = hostname
    $CounterName = $nameHost + "_MS"
    logman.exe create counter $CounterName -o $DefaultLogDir"\Perfmon_$($nameHost).blg" -f bincirc -v mmddhhmm -max 1024 -c  "\PhysicalDisk(*)\*" "\Processor(*)\*" "\Memory\*" "\SMB Client Shares(*)\*" "\SMB Server Shares(*)\*" "\Network Adapter(*)\*" "\iSCSI Request Processing Time(*)\*" "\Process(*)\*"  -si 00:00:01
    logman.exe start $CounterName
}

[scriptblock]$perfmonStop = {

    $nameHost = hostname
    $CounterName = $nameHost + "_MS"
    logman stop $CounterName
    logman delete $counterName
}

#endregion

#region JobStorageNetwork 

$jobStorageNetwork = {

    param($LogName, $ProviderName, $Level, $ID)    

    $filter = @{

        LogName      = $LogName
        ProviderName = $ProviderName
        StartTime    = (Get-Date).AddMinutes(-1)
        Level        = $Level
        ID           = $ID
      
    }

    [ScriptBlock]$StorageTracesStop = {

        logman stop "storport" -ets
        logman stop "minkernel_storage_Disk" -ets
        logman stop "drivers_storage_iSCSI" -ets
        logman stop "drivers_storage_MPIO" -ets
        logman stop "drivers_storage_DSM" -ets
    
    }

    [scriptblock]$NetworkTarceStop = { Netsh trace stop }

 
    [scriptblock]$perfmonStop = {

        $nameHost = hostname
        $CounterName = $nameHost + "_MS"
        logman stop $CounterName
        logman delete $CounterName
    }

    try {

        while (1) {
            $errorMessage = Get-WinEvent -FilterHashtable $filter -MaxEvents 1 -ErrorAction SilentlyContinue
            if ($errorMessage) {
                .$StorageTracesStop
                .$perfmonStop
                .$NetworkTarceStop
                Write-Host -ForegroundColor yellow "Storage & network traces collected."
                break;
            }
        }   


    }
    catch {

        .$StorageTracesStop
        .$perfmonStop
        .$NetworkTarceStop
        Write-Host "JobStorageNetwork -Exception Thrown" -ForegroundColor Green
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Line at which exception occured => $($_.InvocationInfo.Line)" -ForegroundColor yellow


    
    }

}#JobEnd

#endregion

#region JobXperf

$jobXperf = {


    param($LogName, $ProviderName, $Level, $ID)

    $filter = @{

        LogName      = $LogName
        ProviderName = $ProviderName
        StartTime    = (get-date).AddMinutes(-1)
        Level        = $Level
        ID           = $ID
      
    }


    $DefaultDrive = "c:\"
    $logDir = "Logs"
    $DefaultLogDir = $DefaultDrive + $logDir
    $xperfToolLocation = "C:\Toolkit"

    [scriptblock]$XperfStop = {
        Set-Location -Path $xperfToolLocation
        .\Xperf -d $DefaultLogDir"\Xperf_WaitAnalysis.ETL"
    
    }

    try {

        while (1) {
            $errorMessage = Get-WinEvent -FilterHashtable $filter -MaxEvents 1 -ErrorAction SilentlyContinue
            if ($errorMessage) {
                .$XperfStop
                Write-Host -ForegroundColor yellow "Xperf Collected."
                break;
            }
        }   

    }
    catch {
        .$XperfStop
        Write-Host "jobXperf -Exception Thrown" -ForegroundColor Green
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Line at which exception occured => $($_.InvocationInfo.Line)" -ForegroundColor yellow
    }
}#JobEnd


#endregion

#region FunctioniSCSiData

function get-iSCSIData($LogPath, $ToolLocation) {

    #region try
    try {

        $checkLogPath = Get-ChildItem $LogPath -ErrorAction Stop
        $checkToolLocation = Get-ChildItem $ToolLocation -ErrorAction stop
        Write-Host -ForegroundColor yellow "Starting Traces"
        .$StorageTracesStart
        .$perfmonStart
        .$NetworkTarceStart
        .$XperfStart
        
       
        $jobSN = Start-job -ScriptBlock $jobStorageNetwork -ArgumentList @($EventLogName, $EventProviderName, $EventLevel, $EventID)  -name "StorageNetwork"
       
        <#

          For jobXperf param required
          param($LogName,$ProviderName,$Level,$ID)
       
        #>
        $jobX = start-job  -ScriptBlock $jobXperf -ArgumentList @($EventLogName, $EventProviderName, $EventLevel, $EventID) -name "Xperf"

        do {
               
           
            Write-Host -ForegroundColor Green "To check the job status press 1"
            Write-Host -ForegroundColor Green "To stop the traces press 2"
            
            $command = read-host "Select option"
            switch ($command) {

                1 { 
                    
                    "Job {0} - status {1}" -f (Get-job -Id $jobSN.Id).Name, (Get-job -id $jobSN.Id).State
                    "Job {0} - status {1}" -f (Get-job -Id $jobX.Id).Name, (Get-job -id $jobX.Id).State
                    receive-job -job $jobSN -keep
                    receive-job -job $jobX -keep
                  
                    break 
                }
                2 { 
                    if ((Get-Job -id $jobSN.ID).state -eq "Completed" -and (Get-Job -id $jobX.ID).state -eq "Completed") {

                        break;
                    }
                    else {
                        Write-Host -ForegroundColor yellow "Throwing dummy event $($EventID) to stop the job $($jobSN.Name) & $($JobX.Name)."
                        Write-Host -ForegroundColor yellow "Current State of the Job"
                        get-job | FT Id, Name, State
                        write-eventlog -logname $EventLogName -source $EventProviderName -EntryType $EventEntryType -EventID $EventID -message "I am dummy!" 
                        "Waiting for 5 seconds"
                        start-sleep -s 5
                        get-job | FT Id, Name, State
                    }


                    break;
                }

                default { Write-Host -ForegroundColor red "Select the Valid Option" }
 
            }#switch



        }while ($command -ne 2)

        @{StorageJob        = Receive-Job -job $jobSN -keep
            XperfJob        = Receive-Job -job $jobX -keep
            StoragaJobState = (get-job -id $jobSN.id).State
            XperfJobState   = (get-job -id $jobX.id).State
             
        } | export-clixml -path $DefaultLogDir"\diag.xml"

          
        receive-job -job  $jobSN
        receive-job -job $jobX
        get-job | remove-job -force

         
        

    }
    #endregion

    #region catch
    catch {


        Write-Host -ForegroundColor yellow "Exception Occured."
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Line number at which exception occured $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
        .$StorageTracesStop
        .$NetworkTarceStop
        .$XperfStop
        .$perfmonStop
        get-job | remove-job -force

    }
    #endregion


    #region finally

    finally {

        $logDirName = get-date -Format "MM_dd_yyyy_HH_mm"
        $nameHost = HOSTNAME
        $logDirName = $logDirName + "_" + $nameHost
        New-Item -Name $logDirName -ItemType dir -Path $DefaultLogDir"\"
        .$copyEventLogs
        set-location -Path $DefaultLogDir
        Move-Item -Path $DefaultLogDir"\*.*" -Destination $DefaultLogDir"\"$logDirName 
    }

    #endregion

  


}
#endregion

get-iSCSIData -LogPath $DefaultLogDir -ToolLocation $xperfToolLocation

        