function Get-VSC
{
#WMI queries stolen from here https://github.com/EricZimmerman/VSCMount
$volumes = get-wmiobject -query "SELECT Caption,DeviceID FROM Win32_volume"
$vsc = get-wmiobject -query "SELECT DeviceObject,ID,InstallDate,OriginatingMachine,VolumeName,ServiceMachine FROM Win32_ShadowCopy"

#add captions to vsc
foreach ($v in $vsc)
{
    $caption = $volumes | ? {$_.DeviceID -eq $v.VolumeName}
    if($caption)
    {
        $v | Add-Member -MemberType NoteProperty -Name Caption -Value $caption.caption
    }
}

$vsc | select ID,Caption,VolumeName,DeviceObject,InstallDate,OriginatingMachine,ServiceMachine

}

function Test-VSC
{
    [CmdletBinding()]
    param (
    [Parameter(ValueFromPipeline=$true)]
    [ValidateNotNullOrEmpty()]
    [String]
    $ShadowCopyID)

    if(-not $ShadowCopyID.StartsWith("{"))
    {
        $ShadowCopyID = "{" + $ShadowCopyID
    }
    if(-not $ShadowCopyID.EndsWith("}"))
    {
        $ShadowCopyID = $ShadowCopyID + "}"
    }

    $vsc = Get-VSC
    if($vsc.ID.contains($ShadowCopyID))
    {
        return $true
    }
    else {
        return $false
    }
}

function Compare-VSC
{
[CmdletBinding()]
param (
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]
    $ReferenceID,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]
    $DifferenceID,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]
    $Searchbase,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]
    $Filter,

    [Parameter()]
    [Switch]
    $IncludeEqual,

    [Parameter()]
    [ValidateSet("MD5","SHA1","SHA256","SHA512")]
    [String]
    $HashType = "MD5",

    [Parameter()]
    [Switch]
    $AlwaysCalculateHash,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String]
    $CSV,

    [Parameter()]
    [Switch]
    $NoStdOut

    )

    if(-not $ReferenceID.StartsWith("{"))
    {
        $ReferenceID = "{" + $ReferenceID
    }
    if(-not $DifferenceID.StartsWith("{"))
    {
        $DifferenceID = "{" + $DifferenceID
    }
    if(-not $ReferenceID.EndsWith("}"))
    {
        $ReferenceID =  $ReferenceID + "}"
    }
    if(-not $DifferenceID.EndsWith("}"))
    {
        $DifferenceID =  $DifferenceID + "}"
    }

    if((Test-VSC $ReferenceID) -and (Test-VSC $DifferenceID))
    {
        
        #Get base paths of the volume shadow copies
        $allVSC = Get-VSC
        $RefBasePath = ($allVSC | ?{$_.ID -eq $ReferenceID}).DeviceObject
        $DiffBasePath = ($allVSC | ?{$_.ID -eq $DifferenceID}).DeviceObject

        #Get full search path based on user arguments
        $RefFullPath = Join-Path -Path $RefBasePath -ChildPath $Searchbase
        $DiffFullPath = Join-Path -Path $DiffBasePath -ChildPath $Searchbase
        
        Write-Verbose "RefFullPath is: $RefFullPath"
        Write-Verbose "DiffFullPath is: $DiffFullPath"

        #Get all files in the search path based on filter if specified
        if($Filter)
        {
            Write-Verbose "Filter is: $Filter"
            $RefFiles = Get-ChildItem -LiteralPath $RefFullPath -Filter $Filter -Recurse -Force -ErrorAction SilentlyContinue
            $DiffFiles = Get-ChildItem -LiteralPath $DiffFullPath -Filter $Filter -Recurse -Force -ErrorAction SilentlyContinue
        }
        else {
            $RefFiles = Get-ChildItem -LiteralPath $RefFullPath -Recurse -Force -ErrorAction SilentlyContinue
            $DiffFiles = Get-ChildItem -LiteralPath $DiffFullPath -Recurse -Force -ErrorAction SilentlyContinue
        }


        if($RefFiles -or $DiffFiles)
        {
            Write-Verbose "Reffiles count is: $($RefFiles.Count)"
            Write-Verbose "Difffiles count is: $($DiffFiles.Count)"
            #Generate short names for matching difference
            $DiffFiles | % {
                $_ | Add-Member -MemberType NoteProperty -Name ShortName -Value $_.Fullname.Substring($DiffFullPath.Length)
                $_ | Add-Member -MemberType NoteProperty -Name hasMatch -Value $false
            }

            #Create result array
            $ResultArray = New-Object -TypeName "System.Collections.ArrayList"

            #Define individual object structure
            $BaseObject = [PSCustomObject]@{
                ShortName = ""
                SideIndicator = ""
                isDifferent = ""
                isDifferentBecause = ""
                isFolder = ""
                LastWriteTime = ""
                Length = ""
                RefLastWriteTime = ""
                DiffLastWriteTime = ""
                RefLength = ""
                DiffLength = ""	
                RefHash = ""
                DiffHash = ""
                RefFullName = ""
                DiffFullName = ""
                }
            
            #Set default properties to show in stdout
            #https://learn-powershell.net/2013/08/03/quick-hits-set-the-default-property-display-in-powershell-on-custom-objects/
            $defaultDisplaySet = 'ShortName','isDifferent','isDifferentBecause',"isFolder"
            $defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet',[string[]]$defaultDisplaySet)
            $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)
            $BaseObject | Add-Member MemberSet PSStandardMembers $PSStandardMembers

            #Compare files
            foreach($f in $RefFiles)
            {
                $temp = $BaseObject.psobject.Copy()
                $temp.RefFullName = $f.FullName
                $temp.ShortName = $f.Fullname.Substring($RefFullPath.Length)
                $temp.RefLastWriteTime = $f.LastWriteTime
                $temp.RefLength = $f.Length
                $temp.LastWriteTime = $f.LastWriteTime
                $temp.Length = $f.Length

                $diff = $DiffFiles | ? {$_.ShortName -eq $temp.ShortName}

                if($diff)
                {
                    $temp.DiffFullName = $diff.FullName
                    $temp.DiffLastWriteTime = $diff.LastWriteTime
                    $temp.DiffLength = $diff.Length
                    $temp.SideIndicator = "both"
                    $diff.hasMatch = $true

                    if($f.psiscontainer -and $diff.psiscontainer)
                    {
                        $temp.isFolder = $true
                        if($f.LastWriteTime -ne $diff.LastWriteTime)
                        {
                            $temp.isDifferent = $true
                            $temp.isDifferentBecause = "LastWriteTime"
                        }
                        else {
                            $temp.isDifferent = $false
                        }
                    }
                    else 
                    {

                        if(-not $f.psiscontainer -and -not $diff.psiscontainer)
                        {
                            $temp.isFolder = $false
                            if($f.Length -ne $diff.Length)
                            {
                                $temp.isDifferent = $true
                                $temp.isDifferentBecause = ($temp.isDifferentBecause + "+FileSize").TrimStart("+")
                            }
                            if($f.LastWriteTime -ne $diff.LastWriteTime)
                            {
                                $temp.isDifferent = $true
                                $temp.isDifferentBecause = ($temp.isDifferentBecause + "+LastWriteTime").TrimStart("+")
                            }
                            if(-not $temp.isDifferent -or $AlwaysCalculateHash)
                            {
                                    $refhash = Get-FileHash -LiteralPath $f.Fullname -Algorithm $HashType -ErrorAction SilentlyContinue
                                    $diffhash = Get-FileHash -LiteralPath $diff.Fullname -Algorithm $HashType -ErrorAction SilentlyContinue
                                    if($refhash.hash -and $diffhash.hash)
                                    {
                                        $temp.RefHash = $refhash.Hash
                                        $temp.DiffHash = $diffhash.Hash
                                        if($refhash.hash -ne $diffhash.hash)
                                        {
                                            $temp.isDifferent = $true
                                            $temp.isDifferentBecause = ($temp.isDifferentBecause + "+Hash").TrimStart("+")
                                        }
                                    }
                                    else {
                                        #If we can't calculate the hash, and there is no other indication we assume they are not different - I don't know if this is the better choice, let me know if you have an opinion on that
                                        if(-not $temp.isDifferent)
                                        {
                                            $temp.isDifferent = $false
                                        }
                                        if($refhash -eq $null)
                                        {
                                            $temp.RefHash = "unknown"
                                            Write-Verbose "Could not generate hash for $f.Fullname"
                                        }
                                        if($diffhash -eq $null)
                                        {
                                            $temp.DiffHash = "unknown"
                                            Write-Verbose "Could not generate hash for $diff.Fullname"
                                        }
                                    }
                            }
                            if(-not $temp.isDifferent)
                            {
                                $temp.isDifferent = $false
                            }
                        }
                        else {
                            #File/Folder mismatch with same name
                            Write-Warning "File/Folder mismatch - this is strange..."
                            Write-Warning "Reference: $f.Fullname"
                            Write-Warning "Reference is folder: $f.psiscontainer"
                            Write-Warning "Difference is folder: $diff.psiscontainer"
                        }
                    
                    }
                }
                else {
                    $temp.SideIndicator = "ref"
                    $temp.isDifferent = $true
                    $temp.isDifferentBecause = "OnlyInReference"
                    if($f.psiscontainer)
                    {
                        $temp.isFolder = $true 
                    }
                    else 
                    {
                        $temp.isFolder = $false
                    }
                }

                $null = $ResultArray.Add($temp)
            }

            #Go through all files that didn't have a match in the reference
            foreach($d in ($DiffFiles | ? {$_.hasmatch -eq $false}))
            {
                $temp = $BaseObject.psobject.Copy()
                $temp.DiffFullName = $d.FullName
                $temp.ShortName = $d.ShortName
                $temp.LastWriteTime = $d.LastWriteTime
                $temp.Length = $d.Length
                $temp.DiffLastWriteTime = $d.LastWriteTime
                $temp.DiffLength = $d.Length
                $temp.SideIndicator = "diff"
                $temp.isDifferent = $true
                $temp.isDifferentBecause = "OnlyInDifference"

                if($d.psiscontainer)
                {
                    $temp.isFolder = $true 
                }
                else 
                {
                    $temp.isFolder = $false
                }

                $null = $ResultArray.Add($temp)
            }

            if($IncludeEqual)
            {
                $OutputArray = $ResultArray
            }
            else {
                $OutputArray = $ResultArray | ? {$_.isDifferent -eq $true}
            }

            if($CSV)
            {
                $OutputArray | Export-Csv -Path $CSV -NoTypeInformation -Force
            }

            if(-not $NoStdOut)
            {
                $OutputArray
            }
        }
        else {
            Write-Warning "No files found in search path"
            Write-Warning ("Reffiles count: " + $RefFiles.Count)
            Write-Warning ("Diffiles count: " + $DiffFiles.Count)
        }
    }
}