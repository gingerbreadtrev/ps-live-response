
<#
To do

Create a banner for the beginning and end of the log file instead of just using normal function

Need to grab pc name, os and version and put right below banner


#>





Function Write-Log {
    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,
 
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('INFO','DEBUG','ERROR', 'SECTION')]
        [string]$Severity = 'INFO',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$LogFile,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Prefix = ""
    )
    $LogTime = "[ $(Get-Date -Format `"MM/dd/yyyy HH:mm:ss K`") ]"
    If ($Severity -eq 'SECTION') {
        $Message = "$('*'*20) $($Prefix)$($Message.ToUpper()) $('*'*20)"
        $LogSeverity = "[ $($Severity) ]"
        $LogMessage = "`n`n$($LogTime) $($LogSeverity) > `t$($Message)`n"
    } Else {
        # 'Section' is the longest severity enum so let's make all log levels consistent format
        $LogSeverity = "[ $($Severity)$(' '*('Section'.Length - $Severity.Length)) ]"
        $LogMessage = "$($LogTime) $($LogSeverity) > `t$($Prefix)$($Message)"
    }
    $LogMessage | Tee-Object -FilePath $LogFile -Append
}

# Temporary measure to clean out log file
Remove-Item -Path "$($PSScriptRoot)\$($env:computerName)-logs.log" -Force
Remove-Item -Path "$($PSScriptRoot)\LR-Output" -Force -Recurse
Write-Host "`n`n"
############################

# Create timer to time execution
$StopWatch = [Diagnostics.Stopwatch]::StartNew()

$LRLogFile = "$($PSScriptRoot)\$($env:computerName)-logs.log"

Write-Log -Message "Beginning Live Reponse on $($env:computerName)" -Severity INFO -LogFile $LRLogFile

# Declare files and paths ------------------------------------------------------------------------------------

Write-Log -Message "Declaring Output Paths" -Severity SECTION -LogFile $LRLogFile

"$($PSScriptRoot)\LR-Output" | Tee-Object -Variable OutputFolder | Write-Log -Prefix "Output Folder : " -Severity DEBUG -LogFile $LRLogFile
"$($OutputFolder)\$($env:computerName)-winevent-logs" | Tee-Object -Variable WinEventLogFolder | 
                                                        Write-Log -Prefix "Windows Event Log Folder : " -Severity DEBUG -LogFile $LRLogFile     
"$($WinEventLogFolder)\$($env:computerName)-aggregate-winevents.txt" | Tee-Object -Variable WinEventLogsText | 
                                                        Write-Log -Prefix "Windows Event Log Text File : " -Severity DEBUG -LogFile $LRLogFile 
"$($OutputFolder)\$($env:computerName)-prefetch" | Tee-Object -Variable PrefetchOutputFolder | 
                                                        Write-Log -Prefix "Prefetch Folder : " -Severity DEBUG -LogFile $LRLogFile                               
"$($PrefetchOutputFolder)\$($env:computerName)-original-prefetch" | Tee-Object -Variable OriginalPrefetch | 
                                                        Write-Log -Prefix "Unparsed Prefetch Files : " -Severity DEBUG -LogFile $LRLogFile                      
"$($PrefetchOutputFolder)\$($env:computerName)-parsed-prefetch.txt" | Tee-Object -Variable ParsedPrefetchText | 
                                                        Write-Log -Prefix "Parsed Prefetch Text File : " -Severity DEBUG -LogFile $LRLogFile  
"$($OutputFolder)\$($env:computerName)-browser-history" | Tee-Object -Variable BrowserHistoryFolder | 
                                                        Write-Log -Prefix "Browser History Folder : " -Severity DEBUG -LogFile $LRLogFile                  
 
# Tool Paths ------------------------------------------------------------------------------------

Write-Log -Message "Declaring Tool Paths" -Severity SECTION -LogFile $LRLogFile

"$($PSScriptRoot)\LR-Tools" | Tee-Object -Variable ToolPath | Write-Log -Prefix "Tools Folder : " -Severity DEBUG -LogFile $LRLogFile
"$($ToolPath)\PECmd.exe" | Tee-Object -Variable PrefetchParser | Write-Log -Prefix "Prefetch Parser : " -Severity DEBUG -LogFile $LRLogFile
"$($ToolPath)\sqlite3.exe" | Tee-Object -Variable SQLite3 | Write-Log -Prefix "SQLite3 : " -Severity DEBUG -LogFile $LRLogFile


# load all custom Live Response PowerShell modules into PSSession --------------------------------------------------

Write-Log -Message "Loading Custom PSModules" -Severity SECTION -LogFile $LRLogFile

$MOdules = Get-ChildItem -Path $ToolPath | Where-Object FullName -like "*.psm1"

ForEach ($Module in $Modules.FullName) {
    Import-Module -Name $Module -Verbose -Force 4>&1 | Write-Log -Severity INFO -LogFile $LRLogFile
}

# Create Directories to hold related output files ------------------------------------------------------------------------------------
Write-Log -Message "Creating Directories on Host $($env:computerName)" -Severity SECTION -LogFile $LRLogFile

New-Item -Path $OutputFolder -ItemType Directory -Force | Write-Log -Prefix "Created : " -Severity INFO -LogFile $LRLogFile 
New-Item -Path $WinEventLogFolder -ItemType Directory -Force | Write-Log -Prefix "Created : " -Severity INFO -LogFile $LRLogFile 
New-Item -Path $PrefetchOutputFolder -ItemType Directory -Force | Write-Log -Prefix "Created : " -Severity INFO -LogFile $LRLogFile 
New-Item -Path $OriginalPrefetch -ItemType Directory -Force | Write-Log -Prefix "Created : " -Severity INFO -LogFile $LRLogFile 
New-Item -Path $BrowserHistoryFolder -ItemType Directory -Force | Write-Log -Prefix "Created : " -Severity INFO -LogFile $LRLogFile 


# Collecting Windows Event Logs ------------------------------------------------------------------------------------
$EventLogNames = @(
    "System",
    #"Security",
    "Application",
    "Microsoft-Windows-AAD/Operational",
    "not a log"
    )

Write-Log -Message "Collecting Windows Event Logs" -Severity SECTION -LogFile $LRLogFile

$WinEventLogNames = Get-WinEvent -ListLog * -ErrorAction Ignore

ForEach ($LogName in $EventLogNames) {

    If ($LogName -in $WinEventLogNames.LogName) { 
        Write-Output "Saving Windows Event Log: `"$($LogName)`" to XML file" | Write-Log -Severity INFO -LogFile $LRLogFile
        wevtutil qe $LogName > "$($WinEventLogFolder)\$($env:computerName)-$($LogName.Replace("/","-")).xml"
        Write-Output "$("#" * 20) $($LogName) $("#" * 20)" | Out-File -FilePath $WinEventLogsText -Append
        $Records = ($WinEventLogNames | Where-Object LogName -EQ $LogName).RecordCount
        Write-Output "Appending [ $($Records) ] events from `"$($LogName)`" to text file..." | Write-Log -Severity INFO -LogFile $LRLogFile
        Get-WinEvent -LogName $LogName | Select-Object LogName, ProviderName, TimeCreated, ID, LevelDisplayName, Message | 
                                                                Format-List | Out-File -FilePath $WinEventLogsText -Append
    } Else {
        Write-Output "`"$($LogName)`" is not a valid Windows Event Log on this host" | Write-Log -Severity ERROR -LogFile $LRLogFile
    }
}

# Collect Prefetch Files ------------------------------------------------------------------------------------

Write-Log -Message "Collecting Prefetch files" -Severity SECTION -LogFile $LRLogFile

$PrefetchFilePath = "C:\Windows\Prefetch"

If (Test-Path -Path $PrefetchFilePath) {
    Write-Log -Message "Copying Prefetch Files in `"$($PrefetchFilePath)`"" -Severity INFO -LogFile $LRLogFile
    Get-ChildItem -Path $PrefetchFilePath -Recurse | Copy-Item -Destination $OriginalPrefetch
    Write-Log -Message "Parsing Prefetch Files..." -Severity INFO -LogFile $LRLogFile
    & $PrefetchParser "-d" "$($PrefetchFilePath)" | Out-File -FilePath $ParsedPrefetchText
} Else {
    Write-Log -Message "Could not find Prefetch files" -Severity ERROR -LogFile $LRLogFile
}

# Collect MFT on all Volumes ------------------------------------------------------------------------------------

Write-Log -Message "Collecting MFT" -Severity SECTION -LogFile $LRLogFile

# Some computers have multiple drives and Export-MFT only works on NTFS Filesystems
$NTFSVolumes = (Get-Volume | Where-Object {$_.FileSystemType -eq "NTFS" -and $_.DriveLetter -gt $null}).DriveLetter

ForEach ($Volume in $NTFSVolumes) {

    Write-Log -Message "Gathering MFT on Volume $($Volume)..." -Severity INFO -LogFile $LRLogFile
    $MFTInfo = Export-MFT -LROutputPath $OutputFolder -Volume $Volume
    Write-Log -Message "Saved MFT for Volume $($Volume) - SIZE : [ $(($MFTInfo | Select-Object 'MFT Size').'MFT Size') ]" -Severity INFO -LogFile $LRLogFile
}


# Collect All User Profiles ------------------------------------------------------------------------------------

Write-Log -Message "Collecting User Profiles" -Severity SECTION -LogFile $LRLogFile

$UserProfiles = Get-CimInstance -ClassName Win32_UserProfile -Filter "Special = 'False'" |
                     Where-Object LocalPath -NotLike "*default*" | 
                     Select-Object @{Label = "User"; Expression = {$_.LocalPath.Split('\')[-1]}}, 
                                                @{Label = "UserDir"; Expression = {$_.LocalPath}}
# Log all discovered User Profiles
$UserProfiles | ForEach-Object {
        Write-Log -Message "Found User `"$($_.User)`" with home dir `"$($_.UserDir)`"" -Severity INFO -LogFile $LRLogFile
        }

# Collect Browser History and dump to flat file ------------------------------------------------------------------------------------

Write-Log -Message "Collecting Browser History" -Severity SECTION -LogFile $LRLogFile

$BrowserHistoryFiles = @{
    "Edge" = "AppData\Local\Microsoft\Edge\User Data\Default\History"; # Edge History File Path
    "Chrome" = "AppData\Local\Google\Chrome\User Data\Default\History"   # Chrome History File Path
}

ForEach ($Profile in $UserProfiles) {
    $BrowserHistoryFiles.GetEnumerator() | ForEach-Object {
        If (Test-Path -Path "$($Profile.UserDir)\$($_.Value)") {
            Write-Log -Message "Storing : $($Profile.UserDir)\$($_.Value)" -Severity INFO -LogFile $LRLogFile
            $Database = "$($BrowserHistoryFolder)\$($Profile.User)-$($_.Key)-history.db"
            Copy-Item -Path "$($Profile.UserDir)\$($_.Value)" -Destination $Database
            Write-Log -Message "Dumping $($Database) to csv file..." -Severity INFO -LogFile $LRLogFile
            & $SQLite3 $Database ".headers on" ".mode csv" "select * from urls;" > "$($BrowserHistoryFolder)\$($Profile.User)-$($_.Key)-history.csv"
        } Else {
            Write-Log -Message "MISSING : $($Profile.UserDir)\$($_.Value)" -Severity ERROR -LogFile $LRLogFile
        }
    }
}




$StopWatch.Stop()
Write-Log -Message "Live Response Collection Complete. Elapsed Time: [ $($Stopwatch.Elapsed) ]" -Severity INFO -LogFile $LRLogFile