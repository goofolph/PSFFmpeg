function Get-Info {
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [System.IO.FileInfo]
        $Path,

        # Returns format info
        [Parameter(Position = 0, Mandatory = $false)]
        [switch]
        $Format,

        # Returns stream info
        [Parameter(Position = 0, Mandatory = $false)]
        [switch]
        $Streams
    )

    $params = @(
        "-v", "quiet",
        "-print_format", "json"
    )
    if ($Format) {
        $params += "-show_format"
    }
    if ($Streams) {
        $params += "-show_streams"
    }

    $info = ffprobe $params $Path | ConvertFrom-Json

    # add a few extra properties or calculated versions
    if ($Streams) {
        foreach ($stream in $info.streams) {
            # video
            if ($stream.codec_type -eq "video") {
                $stream.bits_per_raw_sample = [long]$stream.bits_per_raw_sample
                $stream.nal_length_size = [long]$stream.nal_length_size
            }

            # audio
            if ($stream.codec_type -eq "audio") {
                $stream.bits_per_sample = [long]$stream.bits_per_sample
                $stream.sample_rate = [long]$stream.sample_rate
            }

            # calculate additional properties
            if ($stream.codec_type -eq "video") {
                # force evaluation as a double
                $avg_fps = Invoke-Expression "[double]$($stream.avg_frame_rate)"
                $r_fps = Invoke-Expression "[double]$($stream.r_frame_rate)"
                Add-Member -InputObject $stream -NotePropertyName "avg_frame_rate_calc" -NotePropertyValue $avg_fps
                Add-Member -InputObject $stream -NotePropertyName "r_frame_rate_calc" -NotePropertyValue $r_fps
            }
            $duration = New-Object TimeSpan -ArgumentList ($stream.duration * [timespan]::TicksPerSecond)
            Add-Member -InputObject $stream -NotePropertyName "duration_timespan" -NotePropertyValue $duration
        }
    }

    return $info
}

function Convert-JsonProperties {
    param (
        [pscustomobject]$inputObject
    )

    if ($inputObject -is [PSCustomObject]) {
        $inputObject.PSObject.Properties | ForEach-Object {
            $propertyName = $_.Name
            $propertyValue = $_.Value
            Write-Host "Processing: $propertyName : $propertyValue"

            if ($propertyValue -is [string]) {
                Write-Host "`tDetected as string"
                if ($propertyValue -match '^\d+$') {
                    Write-Host "`t`tConverting to long"
                    $inputObject.PSObject.Properties.Remove($propertyName)
                    $inputObject | Add-Member -MemberType NoteProperty -Name $propertyName -Value ([long]$propertyValue) -Force
                }
                elseif ($propertyValue -match '^\d+(\.\d+)?$') {
                    Write-Host "`t`tConverting to double"
                    $inputObject.PSObject.Properties.Remove($propertyName)
                    $inputObject | Add-Member -MemberType NoteProperty -Name $propertyName -Value ([double]$propertyValue) -Force
                }
                elseif ($propertyValue -eq 'true' -or $propertyValue -eq 'false') {
                    Write-Host "`t`tConverting to bool"
                    $inputObject.PSObject.Properties.Remove($propertyName)
                    $inputObject | Add-Member -MemberType NoteProperty -Name $propertyName -Value ([bool]$propertyValue) -Force
                }
            }
            elseif ($propertyValue -is [pscustomobject]) {
                Write-Host "`tDetected as custom Object"
                Convert-JsonProperties -inputObject $propertyValue
            }
            elseif ($propertyValue -is [object[]]) {
                Write-Host "`tDetected as Object array"
                foreach ($obj in $propertyValue) {
                    Convert-JsonProperties -inputObject $obj
                }
            }
        }
    }
}
