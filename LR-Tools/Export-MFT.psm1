#Requires -RunAsAdministrator

<#
	.SYNOPSIS
		Extracts master file table from volume.
		
		Version: 0.3
		Author : Costas Katsavounidis (@kacos2000)
		Fixed bug with negative dataruns
		Changed extracted Filename to more human friendly one (inc. Volume Serial & extracted timestamp in FileTimeUtc)
		Added Support for both 1K & 4K records
		Added extra info on extracted MFT (inc. MD5/SHA256 hashes)
		Updated output -> parameter CSV is now a switch (true/false)
		- Note: Remote Host features NOT tested
		
		Version: 0.1
		Author : Jesse Davis (@secabstraction)
		License: BSD 3-Clause
	
	.DESCRIPTION
		This module exports the master file table (MFT) and writes it to $env:TEMP.
		in the form of $MFT_g_48D72F27_133120553486907264
		where "g" is the Driveletter, "48D72F27" is the Volume Serial Number, and
		"133120553486907264" the timestamp of the start of the extraction.

			You can convert this timestamp at a CMD terminal:
			C:\w32tm -ntte 133120553486907264
			154074 17:09:08.6907264 - 4/11/2022 7:09:08 pm
		
			or with Powershell:
			[Datetime]::FromFileTimeUtc(133120553486907264)
			Friday, November 4, 2022 5:09:08 pm

	.PARAMETER ComputerName
		Specify host(s) to retrieve data from.

    .PARAMETER LROutputPath
		Specify output path for LR MFT
	
	.PARAMETER ThrottleLimit
		Specify maximum number of simultaneous connections.
	
	.PARAMETER Volume
		Specify a volume to retrieve its master file table.
		If ommited, it defaults to System (C:\)
	
	.PARAMETER CSV
		Output log file as comma separated values to the same folder as the extracted $MFT file(s).
		Terminal Output is suppressed
	
	.EXAMPLE
		The following example extracts the master file table from the local system volume and writes it to TEMP.
		
		PS C:\> Export-MFT
	
	.EXAMPLE
		The following example extracts the master file table from the system volume of Server01 and writes it to TEMP.
		
		PS C:\> Export-MFT -ComputerName Server01
	
	.EXAMPLE
		The following example extracts the master file table from the F volume on Server01 and writes it to TEMP.
		
		PS C:\> Export-MFT -ComputerName Server01 -Volume F

	.EXAMPLE
		The following example extracts the master file table from the F volume writes it to TEMP.
		A CSV (Comma Separated Log File is created/appended with info on the xtracted MFT
		
		PS C:\> Export-MFT  -Volume G -CSV

		Included info example:

		ComputerName         : MYPC
		Cluster Size         : 4096
		MFT Record Size      : 4096
		MFT Size             : 140 MB
		MFT Volume           : G
		MFT Volume Serial Nr : 48D72F27
		MFT File MD5 Hash    : 825C0DC93FEDDF98E77B992C9D1BEE23
		MFT File SHA256 Hash : E17AF5EEC50CF603CAC708A2018C57A0146E713077F2AE4F0320482BA6A7A6A3
		MFT File             : e:\Temp\Export-MFT_4.11.2022\\$MFT_g_48D72F27_133120553486907264


#>
Function Export-MFT {


    [CmdletBinding()]
    param
    (
        [ValidateNotNullOrEmpty()]
        [Parameter(Mandatory=$True,Position=0)]
	    [String]$LROutputPath,
	    [ValidateNotNullOrEmpty()]
	    [String[]]$ComputerName,
	    [ValidateNotNullOrEmpty()]
	    [Int]$ThrottleLimit = 10,
	    [ValidateNotNullOrEmpty()]
	    [Char]$Volume = 0,
	    [switch]$CSV
    ) #End Param
        
        $ScriptTime = [Diagnostics.Stopwatch]::StartNew()
	    $td = (Get-Date).ToShortDateString().replace("/", ".")
	    $OutputFolderPath = "$LROutputPath"

	    $RemoteScriptBlock = {
	    Param (
		    $Volume,
		    $LROutputPath
	    )
	
		    if ($Volume -ne 0)
		    {
			    $Win32_Volume = Get-CimInstance -ClassName CIM_StorageVolume | where DriveLetter -match $Volume
			    #$Win32_Volume = Get-WmiObject -Class Win32_Volume -Filter "DriveLetter LIKE '$($Volume):'"
                if ($Win32_Volume.FileSystem -ne "NTFS") {
			    Write-Error "$($Volume) does not have an NTFS filesystem."
                    break
                }
            }
            else {
			    $Win32_Volume = Get-CimInstance -ClassName CIM_StorageVolume | where DriveLetter -match $env:SystemDrive
			    #$Win32_Volume = Get-WmiObject -Class Win32_Volume -Filter "DriveLetter LIKE '$($env:SystemDrive)'"
			    if ($Win32_Volume.FileSystem -ne "NTFS")
				    { 
	                    Write-Error "$($env:SystemDrive) does not have an NTFS filesystem."
	                    break
				    }
				    else
				    {
					    $Volume = ($env:SystemDrive).Trim(":")
				    }
	    }
	
	    $tnow = (Get-Date).ToFileTimeUtc()
		    if (![System.IO.Directory]::Exists($LROutputPath))
		    {
			    $null = [System.IO.Directory]::CreateDirectory($LROutputPath)
		    }
		    $OutputFilePath = "$($LROutputPath)\`$MFT_$($Volume)_$($Win32_Volume.SerialNumber.ToString('X'))_$($tnow)"
	
            ## Old -> $OutputFilePath = $env:TEMP + "\$([IO.Path]::GetRandomFileName())"
	
		    #region WinAPI
		    $Supported = @("WindowsPowerShell", "SAPIEN Technologies")
		    $SPaths = [string]::Join('|', $Supported)
		    if([System.AppDomain]::CurrentDomain.Basedirectory -notmatch $SPaths)
			    {
				    Write-Output "Please try running this script in Windows Powershell (PS 5.1)"
				    Write-Output "PowerShell 7 is not currently supported"
				    break
				
			    }
            $GENERIC_READWRITE = 0x80000000
            $FILE_SHARE_READWRITE = 0x02 -bor 0x01
            $OPEN_EXISTING = 0x03
	
		    $DynAssembly = New-Object System.Reflection.AssemblyName('MFT')
		    $AssemblyBuilder = [System.AppDomain]::CurrentDomain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
		    $AssemblyBuilder = [AppDomain]::CurrentDomain.DefineDynamicAssembly($DynAssembly, [Reflection.Emit.AssemblyBuilderAccess]::Run)
            $ModuleBuilder = $AssemblyBuilder.DefineDynamicModule('InMemory', $false)

            $TypeBuilder = $ModuleBuilder.DefineType('kernel32', 'Public, Class')
            $DllImportConstructor = [Runtime.InteropServices.DllImportAttribute].GetConstructor(@([String]))
            $SetLastError = [Runtime.InteropServices.DllImportAttribute].GetField('SetLastError')
            $SetLastErrorCustomAttribute = New-Object Reflection.Emit.CustomAttributeBuilder($DllImportConstructor,
                @('kernel32.dll'),
                [Reflection.FieldInfo[]]@($SetLastError),
                @($True))

            #CreateFile
            $PInvokeMethodBuilder = $TypeBuilder.DefinePInvokeMethod('CreateFile', 'kernel32.dll',
                ([Reflection.MethodAttributes]::Public -bor [Reflection.MethodAttributes]::Static),
                [Reflection.CallingConventions]::Standard,
                [IntPtr],
                [Type[]]@([String], [Int32], [UInt32], [IntPtr], [UInt32], [UInt32], [IntPtr]),
                [Runtime.InteropServices.CallingConvention]::Winapi,
                [Runtime.InteropServices.CharSet]::Ansi)
            $PInvokeMethodBuilder.SetCustomAttribute($SetLastErrorCustomAttribute)

            #CloseHandle
            $PInvokeMethodBuilder = $TypeBuilder.DefinePInvokeMethod('CloseHandle', 'kernel32.dll',
                ([Reflection.MethodAttributes]::Public -bor [Reflection.MethodAttributes]::Static),
                [Reflection.CallingConventions]::Standard,
                [Bool],
                [Type[]]@([IntPtr]),
                [Runtime.InteropServices.CallingConvention]::Winapi,
                [Runtime.InteropServices.CharSet]::Auto)
            $PInvokeMethodBuilder.SetCustomAttribute($SetLastErrorCustomAttribute)

            $Kernel32 = $TypeBuilder.CreateType()

            #endregion WinAPI

            # Get handle to volume
            if ($Volume -ne 0) { $VolumeHandle = $Kernel32::CreateFile(('\\.\' + $Volume + ':'), $GENERIC_READWRITE, $FILE_SHARE_READWRITE, [IntPtr]::Zero, $OPEN_EXISTING, 0, [IntPtr]::Zero) }
            else { 
                $VolumeHandle = $Kernel32::CreateFile(('\\.\' + $env:SystemDrive), $GENERIC_READWRITE, $FILE_SHARE_READWRITE, [IntPtr]::Zero, $OPEN_EXISTING, 0, [IntPtr]::Zero) 
                $Volume = ($env:SystemDrive).TrimEnd(':')
            }
        
            if ($VolumeHandle -eq -1) { 
                Write-Error -Message "Unable to obtain read handle for volume $($Volume)"
                break 
            }         
        
            # Create a FileStream to read from the volume handle
            $FileStream = New-Object IO.FileStream($VolumeHandle, [IO.FileAccess]::Read)                   

            # Read VBR from volume
            $VolumeBootRecord = New-Object Byte[](512)                                                     
            if ($FileStream.Read($VolumeBootRecord, 0, $VolumeBootRecord.Length) -ne 512) { Write-Error "Error reading volume $($Volume)'s boot record." }

            # Get bytes per cluster
		    $bytespersector = [Bitconverter]::ToUInt16($VolumeBootRecord[0xB .. 0xC], 0)
		    $sectorspercluster = [int]$VolumeBootRecord[0xD]
		    $bytespercluster = $bytespersector * $sectorspercluster

            # Parse MFT offset from VBR and set stream to its location
            $MftOffset = [Bitconverter]::ToInt32($VolumeBootRecord[0x30..0x37], 0) * $bytespercluster
            $FileStream.Position = $MftOffset

            # Get Volume Serial Number
		    $vs = $VolumeBootRecord[0x48 .. 0x4B]
		    [System.Array]::Reverse($vs)
		    $VolumeSerial = [System.BitConverter]::ToString($vs) -replace '-', ''

            ## Read MFT's file record header & Validate MFT file signature
		    $MftFileRecordHeader = New-Object byte[](48)
		    if ($FileStream.Read($MftFileRecordHeader, 0, $MftFileRecordHeader.Length) -ne $MftFileRecordHeader.Length)
		    {
			    Write-Error -Exception "Error reading the `$MFT file record header."
			    return
		    }
		    elseif([System.Text.Encoding]::ASCII.GetString($MftFileRecordHeader[0..3]) -ne 'FILE')
		    {
			    Write-Error "The `$MFT is corrupt or not an `$MFT"
			    return
		    }
		
		    # Read MFT record Size
		    $RecordSize = [Bitconverter]::ToInt32($MftFileRecordHeader[0x1C .. 0x1F], 0)
		
		    #fxoffset
		    $fxoffset = [Bitconverter]::ToUInt16($MftFileRecordHeader[4 .. 5], 0)
		
		    #Nr of fixups
		    $nrfixups = [Bitconverter]::ToUInt16($MftFileRecordHeader[6 .. 7], 0) - 1
		
		    # Parse values from MFT's file record header
		    $OffsetToAttributes = [Bitconverter]::ToUInt16($MftFileRecordHeader[0x14 .. 0x15], 0) # Offset to 1st Attribute
		    $AttributesRealSize = [Bitconverter]::ToUInt32($MftFileRecordHeader[0x18 .. 0x21], 0) # Logical Size of record
		
		    # Read MFT's full file record
		    $MftFileRecord = New-Object System.Byte[]($RecordSize)
		    $FileStream.Position = $MftOffset
		    if ($FileStream.Read($MftFileRecord, 0, $MftFileRecord.Length) -ne $RecordSize)
		    {
			    Write-Error -Message "Error reading `$MFT file record."
			    return
		    }
		
		    # Replace the Fix-ups
		    foreach ($fx in (1 .. $nrfixups))
		    {
			    $MftFileRecord[(($fx * 512) - 2)] = $MftFileRecord[($fxoffset + (2 * $fx))]
			    $MftFileRecord[(($fx * 512) - 1)] = $MftFileRecord[($fxoffset + (2 * $fx) + 1)]
		    }
		
		    # Parse MFT's attributes from file record
		    $Attributes = New-object System.Byte[]($AttributesRealSize - $OffsetToAttributes)
		    [Array]::Copy($MftFileRecord, $OffsetToAttributes, $Attributes, 0, $Attributes.Length)
	
	    # Find Data attribute
	    try
	    {
		    $CurrentOffset = 0
		    do
		    {
			    $AttributeType = [Bitconverter]::ToUInt32($Attributes[$CurrentOffset .. $($CurrentOffset + 3)], 0)
			    $AttributeSize = [Bitconverter]::ToUInt32($Attributes[$($CurrentOffset + 4) .. $($CurrentOffset + 7)], 0)
			    $CurrentOffset += $AttributeSize
		    }
		    until ($AttributeType -eq 128)
	    }catch{break}
	    # Parse data attribute from all attributes
            $DataAttribute = $Attributes[$($CurrentOffset - $AttributeSize)..$($CurrentOffset - 1)]

            # Parse the MFT logical size from data attribute
            $MftSize = [Bitconverter]::ToUInt64($DataAttribute[0x30..0x37], 0)
        
            # Parse data runs from data attribute
            $OffsetToDataRuns = [Bitconverter]::ToInt16($DataAttribute[0x20..0x21], 0)        
            $DataRuns = $DataAttribute[$OffsetToDataRuns..$($DataAttribute.Length -1)]
        
            # Convert data run info to string[] for calculations
		    $Runlist = [Bitconverter]::ToString($DataRuns) -replace '-',''
        
            # Setup to read MFT
            $FileStreamOffset = 0
            $DataRunStringsOffset = 0        
            $TotalBytesWritten = 0
		    try
		    {
			    $OutputFileStream = [IO.File]::OpenWrite($OutputFilePath)
		    }
		    catch
		    {
			    Write-Error "Error creating out file $($OutputFilePath)"
			    break
		    }
	
	    # MD5 Hash	
		    $md5new = [System.Security.Cryptography.MD5]::Create()
            $sha256new = [System.Security.Cryptography.SHA256]::Create()
		    $dr = 0

		    # Start the extraction
            do
		    {
			    $StartBytes = [int]"0x$($Runlist.Substring($DataRunStringsOffset + 0, 1))"
			    $LengthBytes = [int]"0x$($Runlist.Substring($DataRunStringsOffset + 1, 1))"
			
			    # start of extend	
			    $starth = $Runlist.Substring($DataRunStringsOffset + $LengthBytes * 2 + 2, $StartBytes * 2) -split "(..)"
			    [array]::reverse($starth)
			    $starth = (-join $starth).trim() -replace " ", ""
			    $DataRunStart = [bigint]::Parse($starth, 'AllowHexSpecifier')
			
			    # Length of Extend
			    $lengthh = $Runlist.Substring($DataRunStringsOffset + 2, $LengthBytes * 2) -split "(..)"
			    [array]::reverse($lengthh)
			    $lengthh = (-join $lengthh).trim() -replace " ", ""
			    $DataRunLength = [bigint]::Parse($lengthh, 'AllowHexSpecifier')
			    # Get the Logical Size & not the Physical (Allocated)
			    $MftData = if (($TotalBytesWritten + $bytespercluster * $DataRunLength) -gt $MftSize)
			    {
				    New-Object System.Byte[]($MftSize - $TotalBytesWritten)
			    }
			    else { New-Object System.Byte[]($bytespercluster * $DataRunLength) }
			    $FileStreamOffset += ($DataRunStart * $bytespercluster)
			    $FileStream.Position = $FileStreamOffset
			
			    if ($FileStream.Read($MftData, 0, $MftData.Length) -ne $MftData.Length)
			    {
				    Write-Error "Possible error reading MFT data"
			    }
			    $OutputFileStream.Write($MftData, 0, $MftData.Length)
			
			    # compute hashes (partial)
			    $null = $md5new.TransformBlock($MftData, 0, $MftData.Length, $null, 0)
			    $null = $sha256new.TransformBlock($MftData, 0, $MftData.Length, $null, 0)
			    # Get total bytes
			    $TotalBytesWritten += $MftData.Length
			    $DataRunStringsOffset += ($StartBytes + $LengthBytes + 1) * 2
			
                $dr++
		    }
		    until ($TotalBytesWritten -eq $MftSize)
		    #Write-Host  "Saved $($dr) Dataruns - Total bytes written: $($MftSize)" -InformationAction Continue
            $FileStream.Dispose()
            $OutputFileStream.Dispose()

            # Get Final (Full) Hash
		    $md5new.TransformFinalBlock([byte[]]::new(0), 0, 0)
            $sha256new.TransformFinalBlock([byte[]]::new(0), 0, 0)
		    $md5 = [System.BitConverter]::ToString($md5new.Hash).Replace("-", "")
            $sha256 = [System.BitConverter]::ToString($sha256new.Hash).Replace("-", "")

            $Properties = [Ordered]@{
                'ComputerName' = $env:COMPUTERNAME
                'Cluster Size' = $bytespercluster
                'MFT Record Size' = $RecordSize
                'MFT Size' = "$($MftSize / 1024 / 1024) MB"
                'MFT Volume' = $Volume.ToString().ToUpper()
                'MFT Volume Serial Nr' = $VolumeSerial
                'MFT File MD5 Hash' = $md5
                'MFT File SHA256 Hash' = $sha256
                'MFT File' = $OutputFilePath
            }
            New-Object -TypeName PSObject -Property $Properties
        } # End RemoteScriptBlock

	    $args = @(
		    $Volume
		    $LROutputPath
	    )

        if ($PSBoundParameters['ComputerName']) {   
            $ReturnedObjects = Invoke-Command -ComputerName $ComputerName -ScriptBlock $RemoteScriptBlock -ArgumentList $args -SessionOption (New-PSSessionOption -NoMachineProfile) -ThrottleLimit $ThrottleLimit
        }
        else { $ReturnedObjects = Invoke-Command -ScriptBlock $RemoteScriptBlock -ArgumentList $args }

        if ($ReturnedObjects -ne $null -and $PSBoundParameters['CSV'])
		    {
	    $OutputCSVPath = "$($LROutputPath)\Export-MFT_Log.csv"
	    if (![System.IO.File]::Exists($OutputCSVPath))
				    {
					    $ReturnedObjects | Export-Csv -Path $OutputCSVPath -NoTypeInformation -ErrorAction SilentlyContinue
				    }
				    else
				    {
					    $ReturnedObjects | Export-Csv -Path $OutputCSVPath -Append  -NoTypeInformation -ErrorAction SilentlyContinue
				    }
			    Invoke-Item -LiteralPath $OutputCSVPath
		    }
	            else { Write-Output $ReturnedObjects }

        [GC]::Collect()
        $ScriptTime.Stop()
        Write-Output "Extraction Finished in: $($ScriptTime.Elapsed)"
}