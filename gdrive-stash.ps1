<#
MIT License

Copyright (c) 2024 pilgrim_tabby

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

<#
.SYNOPSIS
Copy a directory's files to a directory in Google Drive.

.DESCRIPTION
An add-on for the gdrive CLI (https://github.com/glotlabs/gdrive).
Loops through files in a local directory $srcDir (and its subdirectories if
$recursive is enabled) and puts them directly into a Google Drive directory
$destDir.

.PARAMETER srcDir
The locally stored parent directory of the directory to be backed up.
Ex: C:\foo\bar\ (trailing backslash optional)

.PARAMETER destDir
The full path OR the Google Drive ID of the target folder. Files inside srcDir
will be copied directly inside destDir. Using an ID is faster but the full path
is easier to obtain.
Paths begin with "\" (forward slashes are converted to backslashes in Resolve-
DriveDirId). Passing "\" will copy the files in srcDir into Google Drive's root
directory. If you want to copy files into a folder called "My Backups" in your
drive's root, you would pass destDir as "\My Backups".

.PARAMETER destDirIsId
Tells function to treat $dest as a Google Drive ID, not a pathname.
Default is $false. Alias is "-i".

.PARAMETER makeParents
When enabled, tells Resolve-DriveDirId to create any directories in $destDir's
path that don't already exist. If this is disabled and $destDir doesn't exist,
the script will exit. Alias is "-p".

.PARAMETER recursive
Tells function to recursively back up subdirectories in $srcDir.
Default is $false. Alias is "-r".

.EXAMPLE
gdrive-stash "C:\foo\bar\mystuff" "\"
Result: All files in "mystuff" are copied into Google Drive's root directory,
excluding subdirectories.

.EXAMPLE
gdrive-stash "C:\foo\bar\mystuff" "\mybackups"
Result: All files in "mystuff", excluding subdirectories, are copied into
"mybackups", which resides in Google Drive's root directory. If "mybackups"
doesn't exist, the script will exit.

.EXAMPLE
gdrive-stash "C:\foo\bar\mystuff" "\mybackups\todays-date" -p
Result: All files in "mystuff", excluding subdirectories, are copied
into "mybackups\todays-date", which resides in Google Drive's root directory.
If either of those directories doesn't exist, they will be created.

.EXAMPLE
gdrive-stash "C:\foo\bar\mystuff" "\mybackups" -r
Result: All files in "mystuff", including subdirectories, are recursively
copied into "mybackups", which resides in Google Drive's root directory.

.EXAMPLE
gdrive-stash "C:\foo\bar\mystuff" "1Fn7xLIHE_iIY8o5MHbjQaAX20PdnE0ZD" -r -i
Result: All files in "mystuff", including subdirectories, are recursively
copied into the directory with Google Drive ID 1Fn7xLIHE_iIY8o5MHbjQaAX20PdnE0ZD.
This is much faster than having to crawl through an entire directory path, but
it may not be worth the effort...
#>
param (
    [Parameter(Mandatory=$true)][string]$srcDir,
    [Parameter(Mandatory=$true)][string]$destDir,
    [switch][Alias("r")]$recursive,
    [switch][Alias("p")]$makeParents,
    [switch][Alias("i")]$destDirIsId
)


#########################
#                       #
# Function Declarations #
#                       #
#########################

function Backup-Dir {
<#
    .SYNOPSIS
    Back up a directory (and optionally, its subdirectories) to Google Drive.

    .DESCRIPTION
    Iterates through all non-directory files, calling Backup-File on each one.
    If "recursive" is $true, also recursively backs up subdirectories.
    See Get-Help gdrive-stash for parameter information and examples.
#>
    param (
        [Parameter(Mandatory=$true)][string]$srcDir,
        [Parameter(Mandatory=$true)][string]$destDir,
        [switch]$recursive,
        [switch]$destDirIsId,
        [switch]$makeParents
    )

    # Get list of files in $srcDir
    $srcFiles = $(Get-LocalFileList $srcDir)

    # Get destId
    if ($destDirIsId) {
        $destId = $destDir
    } else {
        # Use splatting in case $makeParents isn't passed by calling function
        $params = @{
            destDir = $destDir
        }
        if ($makeParents) {
            $params.makeParents = $makeParents
        }
        $destId = $(Resolve-DriveDirId @params)
    }

    # Get list of files in $destDir
    $destFiles = $(Get-DriveFileList $destId)
    # It's rtyring to make dest files with dest id
    foreach ($filename in $srcFiles) {
        $fileType = $(Test-IsDir $srcDir $filename)
        $fileId, $driveFileCreateTime = $(Get-DriveFileInfo $filename $fileType $destFiles)

        # Either skip or recursively dive into directories, depending on -r
        if ($fileType -eq ([FileType]::DIR)) {
            if (!$recursive) { continue }

            if ($fileId -ne "") {
                $newDestId = $fileId
            } else {
                $newDestId = $(gdrive files mkdir --print-only-id --parent $destId $filename)
            }
            Backup-Dir "$srcDir\$filename" $newDestId -destDirIsId -recursive

        # Back up all other file types directly
        } else {
            Backup-File $srcDir $filename $destId $fileId $driveFileCreateTime
        }
    }
}


function Get-LocalFileList {
<#
    .SYNOPSIS
    Return list of all files, including subdirectories, inside a directory.

    .PARAMETER srcDir
    The directory whose files are returned.

    .OUTPUTS
    [string] with the relative path to each file, separated by newlines.
#>
    param (
        [Parameter(Mandatory=$true)][string]$srcDir
    )

    try {
        return $(Get-ChildItem $srcDir -Name)
    } catch [System.Management.Automation.ItemNotFoundException] {
        Write-Output "Error: source $srcDir is not a directory"
        exit
    }
}


function Get-DriveFileList {
<#
    .SYNOPSIS
    Return array of strings, each string containing info about a Drive file.

    .DESCRIPTION
    Gets $destDir's contents as a string, and splits the string into an array. 

    Each entry in the array contains the following information, in order:
    -Google Drive ID
    -Filename
    -File type (folder, regular, document, etc.)
    -File size (for directories, this is blank)
    -Date and time file was created

    The delimiter ":DELIMITER?" separates discreet pieces of information
    in each entry in the array. This string is used because it's unlikely to be
    used in a filename, and it uses a forbidden filename character for both 
    Windows ("?") and MacOS (":").

    .PARAMETER destDir
    The directory holding the files that will be listed.

    .OUTPUTS
    [string[]]: Array of strings, each holding information about a file in
    the directory at $destId
#>
    param (
        [Parameter(Mandatory=$true)][string]$destId
    )

    try {
        $params =
            "--field-separator", ":DELIMITER?",
            "--order-by", "name",
            "--skip-header",
            "--full-name"
        if ($destId -ne "") {
            $params += "--parent", $destId
        }
        return $($(gdrive files list $params) -split "`n`r")

    # Catch any invalid IDs
    } catch [System.Management.Automation.RemoteException] {
        Write-Output "Error: directory with ID $destId not found"
        exit
    }
}


function Get-DriveFileInfo {
<#
    .SYNOPSIS
    Search a Google Drive dir for a file matching a local file's name and type.

    .DESCRIPTION
    Make a case-sensitive search in a Google Drive directory for a file with a
    given filename and type. If a match isn't found, return two "" values.
    Possible file types are directory and file (see enum FileType). Case
    sensitivity is used because Google Drive files are case-sensitive.

    .PARAMETER filename
    The name of the file to search for.

    .PARAMETER fileType
    The type of the file to search for.
    Options are [FileType]::DIR and [FileType]::FILE.

    .PARAMETER driveFileList
    The array of file entries to search through. Each entry holds the following
    information, in order:
    -Google Drive ID
    -Filename
    -File type (folder, regular, document, etc.)
    -File size (for directories, this is blank)
    -Date and time file was created

    If a null value is passed for this parameter, the foreach loop is skipped.

    .OUTPUTS
    [string]: Google Drive ID of the file. Blank if no match found.
    [string]: The creation date and time of the Google Drive file. Blank if no
        match found.
#>
    param (
        [Parameter(Mandatory=$true)][string]$filename,
        [Parameter(Mandatory=$true)][FileType]$fileType,
        [string[]]$driveFileList=@()
    )

    foreach ($line in $driveFileList) {
        $fileInfo = $($line -split ":DELIMITER?", 0, "simplematch")

        if ($fileInfo[1] -ceq $filename) {
            if ($fileType -eq ([FileType]::DIR) -and $fileInfo[2] -eq "folder") {
                return $fileInfo[0], $fileInfo[4]

            } elseif ($fileType -eq ([FileType]::FILE) -and $fileInfo[2] -ne "folder") {
                return $fileInfo[0], $fileInfo[4]
            }
        }
    }
    return "", ""
}
    

function Resolve-DriveDirId {
<#
    .SYNOPSIS
    Gets (or creates) the Google Drive ID for a directory.

    .DESCRIPTION
    Crawls the path $destDir to its last dir and returns its Google Drive ID.
    If the path doesn't exist and makeParents is enabled, then all missing
    directories are created.

    .PARAMETER destDir
    The directory whose ID will be extracted.

    .PARAMETER makeParents
    When $true, any directories in $destDir's path that don't exist will be
    created (case-sensitive). If this option is off and $destDir doesn't exist,
    the script exits.

    .OUTPUTS
    [string] nextDirId: The Google Drive ID of $destDir.
#>
    param (
        [Parameter(Mandatory=$true)][string]$destDir,
        [switch]$makeParents
    )
    $params =
        "--field-separator", ":DELIMITER?",
        "--order-by", "name",
        "--skip-header",
        "--full-name"
    $currFileList = $($(gdrive files list $params) -split "`n`r")
    $currDirId = ""  # The return value if $destDir is root
    # Standardize slashes, remove them from ends to simplify splitting
    $dirsInPath = $destDir.Replace("/", "\").TrimStart("\").TrimEnd("\").Split("\")

    for ($i=0; $i -lt $dirsInPath.Length; $i++) {
        $nextDir = $dirsInPath[$i]
        # We only use the first return value ($destId)
        $nextDirId = $(Get-DriveFileInfo $nextDir ([FileType]::DIR) $currFileList)[0]

        # Directory exists
        if ($nextDirId -ne "") {
            if ($i -eq $($dirsInPath.Length - 1)) {
                break  # Don't need to call gdrive if last dir
            }
            $nextFileList = $($(gdrive files list $params --parent $nextDirId) -split "`n`r")

        # Directory doesn't exist
        } elseif ($makeParents) {

            # Current directory is not root -- make new dir in most recent dir
            if ($currDirId -ne "") {
                $nextDirId = $(gdrive files mkdir --parent $currDirId --print-only-id $nextDir)
            
            # Current directory is root -- make new directory in root
            } else {
                $nextDirId = $(gdrive files mkdir --print-only-id $nextDir)
            }

            # File list is empty, since the new directory is empty
            $nextFileList = @()

        } else {
            Write-Output "Error: destination $destDir is not a directory (case-sensitive)"
            Write-Output "Use option `"-p`" to recursively create parent dirs"
            exit
        }

        $currDirId = $nextDirId
        $currFileList = $nextFileList
    }
    return $nextDirId
}


function Backup-File {
<#
    .SYNOPSIS
    Upload or update a local file into Google Drive.

    .DESCRIPTION
    If a file already exists in the directory at $destId, we check if its last
    write time is more recent than the Drive file's creation time. If so, we
    know it's different, so we delete the file from Drive and re-upload it.

    Deleting and re-uploading is only marginally slower than simply updating,
    and it allows us to reset the Drive file's creation date, since that value
    is set to be the time of upload. This lets us compare that time with the
    local write time to see if changes have been made.

    If a file doesn't exist in the dir at $destId yet, then upload it.

    .PARAMETER srcDir
    The parent directory of the file to back up.

    .PARAMETER filename
    The name of the file to back up, e.g. myfile.txt.

    .PARAMETER destId
    The Google Drive ID of the folder we are copying files into.

    .PARAMETER fileId
    The Google Drive ID of the file we are dealing with, if the file already
    exists in the dir at $destId. If not passed, the default is an empty string.

    .PARAMETER driveFileCreateTime
    The date and time at which the file in Google Drive was uploaded, if it
    exists. If not passed, the default is an empty string.
#>
    param (
        [Parameter(Mandatory=$true)][string]$srcDir,
        [Parameter(Mandatory=$true)][string]$filename,
        [Parameter(Mandatory=$true)][string]$destId,
        [string]$fileId="",
        [string]$driveFileCreateTime=""
    )

    # Pre-existing file
    if ($fileId -ne "") {
        $localWriteTime = (Get-ChildItem "$srcDir\$filename").
            LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        if ($localWriteTime -gt $driveFileCreateTime) {
            gdrive files delete $fileId
            gdrive files upload --parent $destId "$srcDir\$filename"
        }

    # New file
    } else {
        gdrive files upload --parent $destId "$srcDir\$filename"
    }
}


function Test-IsDir {
<#
    .SYNOPSIS
    Categorize a file into one of two types: non-dir file or dir.
    See enum FileType.

    .PARAMETER srcDir
    The file's parent directory. Ex: C:\foo\ (trailing backslash not required)

    .PARAMETER filename
    The file's name, including extension. Ex: my_file.txt

    .OUTPUTS
    [FileType]::DIR if $srcDr\$filename is a dir, otherwise [FileType]::FILE.
#>
    param (
        [Parameter(Mandatory=$true)][string]$srcDir,
        [Parameter(Mandatory=$true)]$filename
    )

    if ($(Get-Item "$srcDir\$filename").PSIsContainer) {
        return ([FileType]::DIR)
    }
    return ([FileType]::FILE)
}


enum FileType {
<#
    .SYNOPSIS
    Categorize a file into one of two types: non-dir file or dir.
#>
    DIR
    FILE
}
    

##########
#        #
# Script #
#        #
##########

# Make sure non-terminating exceptions are caught
$ErrorActionPreference = "Stop"

# Parse parameters
$params = @{
    srcDir = $srcDir
    destDir = $destDir
}
if ($recursive) {
    $params.recursive = $recursive
}
if ($makeParents) {
    $params.makeParents = $makeParents
}
if ($destDirIsId) {
    $params.destDirIsId = $destDirIsId
}

Backup-Dir @params
