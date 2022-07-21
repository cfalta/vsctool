# vsctool
vsctool implements Powershell functions which allow you to interact with volume shadow copies. Available functions are explained below in more detail.

Please be aware that this project is in an early development stage - use at your own risk ;)

Inspired by Eric Zimmerman's [vscmount](https://github.com/EricZimmerman/VSCMount)

## Get-VSC

Shows a list of all available volume shadow copies and maps them to drive letters.

### Arguments

None

### Example

``` powershell
Get-VSC
```

<img src="https://user-images.githubusercontent.com/7213829/180279022-483ca200-aa22-4c1d-ba9a-6352464670e8.png">



## Test-VSC

Tests the existence of a shadow copy by ID. Returns true if the shadow copy exists and false if it does not.

### Arguments

#### -ShadowCopyId

The ID of the shadow copy to look for.

### Example

``` powershell
Test-VSC -ShadowCopyID 6A3E7292-FF8E-45C7-8782-82C9433D8A8E
```

<img src="https://user-images.githubusercontent.com/7213829/180279089-e64f5861-fb2d-43be-845c-b4a945051838.png">



## Compare-VSC

This function was made with a DFIR usecase in mind but might also be useful for sysadmins. It compares the content of two shadow copies. You have to supply a reference and a difference ID as well as a searchbase. The later refers to the starting point in the filesystem cause you usually wouldn't want to compare the whole VSC since this takes a lot of time.

Therefore you can for example use a searchbase of `C:\users\jack\downloads` to compare only the contents of the `Downloads` folder of the user `jack`. Note that the searchbase is always recursive, so subfolders and files are included by default.
You can also supply a search filter to only compare files that match the filter. For example, you could use a filter of `*.exe` and a searchbase of `C:\users\jack\` to only compare exe-files in the user profile (looking for you, evil malware in AppData ;) ).

**Comparison logic:**

1. Get a list of all items (files and folders) in the reference.
2. Treat everything that exists only in the reference or difference (matched by path) as different.
3. For every item that exists in the reference and the difference (again matched by path), do the following:
    * If it's a folder and the LastWriteTime is different, treat as different. Otherwise treat as equal.
    * If it's a file and the Size is different, treat as different.
    * If it's a file and the LastWriteTime is different, treat as different.
    * If it's a file and neither Size nor LastWriteTime are different, calculate a hash and compare. If it's different, treat as different.
    * If it's a file and none of the above matched, treat as equal.

### Arguments

#### -ReferenceID

The ID of the reference shadow copy. You can get this information by using `Get-VSC`

#### -DifferenceID

The ID of the difference shadow copy. You can get this information by using `Get-VSC`

#### -Searchbase

The starting point in the filesystem. Needs to point to a folder.

#### -Filter

Makes the script only compare files that match the filter. For example, you could use a filter of `*.exe` and a searchbase of `C:\users\jack\` to only compare exe-files in the user profile (looking for you, evil malware in AppData ;) ).

#### -IncludeEqual

Includes all results in the output, not only those that are different.

#### -HashType

Set the hash algorithm that's used to compare files if necessary. Possible values are "MD5","SHA1","SHA256","SHA512". Default ist MD5.

#### -AlwaysCalculateHash

Always compare by hash, regardless of size or timestamp differences.

#### -CSV

Output the result to a CSV file. You could the use something like Excel or the great Timeline Explorer by Eriz Zimmerman to go through the results.

#### -NoStdOut

Do not print the result to stdout. Default is to print all results as custom powershell objects to stdout.


### Example

**Example 1**

This command compares only the contents in the users download folder. By default, only a few attributes are returned so the output should fit in a table view in most cases. The idea is to give a summary of the results.

<img src="https://user-images.githubusercontent.com/7213829/180279626-c7d512f9-76f0-4a38-b7f5-ce2ad3477682.png">

**Example 2**

Same as previous, we just get all of the properties. Compare-VSC returns PSObjects so you can handle them like you're used to.

<img src="https://user-images.githubusercontent.com/7213829/180281001-b64863e4-1e36-4efc-9d90-7ce5458f5b63.png">

**Example 3**

Here's how you could use a filter to look for different ".exe"-files in the users home directory.

<img src="https://user-images.githubusercontent.com/7213829/180283747-88158ffc-422b-4419-a99f-a0aae1468108.png">