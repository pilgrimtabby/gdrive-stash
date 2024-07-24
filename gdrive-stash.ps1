param (
    [Parameter(Mandatory=$true)][string]$src,
    [Parameter(Mandatory=$true)][string]$dest,
    [switch][Alias("r")]$recursive = $false,
    [switch][Alias("p")]$parents = $false,
    [switch][Alias("i")]$dest_is_id = $false
)

enum FileType {
    DIR
    FILE
}

function FileIsDir($src, $filename) {
    $file_path = $(Get-Item "$src\$filename")
    if ($file_path.PSIsContainer) {
        return [FileType]::DIR
    }
    return [FileType]::FILE
}

function GetDriveDirIdFromPath($dest) {
    $dest = $dest.Replace("/", "\").TrimStart("\").TrimEnd("\")
    $path_dirs = $dest.Split("\")
    $dir_count = $path_dirs.Length

    $cur_dir_id = ""
    $cur_dir_info = gdrive files list --field-separator ":DELIMITER?" --order-by name --skip-header --full-name
    $cur_dir_files = $cur_dir_info -split "`n`r"
    for ($i = 0; $i -le $dir_count; $i++) {
        if ($i -eq $dir_count) {
            return $cur_dir_id
        }

        $next_dir = $path_dirs[$i]
        $found_file = $false
        ForEach ($cur_file in $cur_dir_files) {
            $cur_file = $cur_file -split ":DELIMITER?", 0, "simplematch"
            if ($cur_file[1] -ceq $next_dir -and $cur_file[2] -eq "folder") {
                $found_file = $true
                $cur_dir_id = $cur_file[0]
                $cur_dir_info = gdrive files list --parent $cur_dir_id --field-separator ":DELIMITER?" --order-by name --skip-header --full-name
                $cur_dir_files = $cur_dir_info -split "`n`r"
                break
            }
        }

        if ($found_file) {
            continue
        } elseif ($parents) {
            if ($cur_dir_id -eq "") {
                $cur_dir_id = $(gdrive files mkdir --print-only-id $path_dirs[$i])
            } else {
                $cur_dir_id = $(gdrive files mkdir --parent $cur_dir_id --print-only-id $path_dirs[$i])
            }
            $cur_dir_info = gdrive files list --parent $cur_dir_id --field-separator ":DELIMITER?" --order-by name --skip-header --full-name
            $cur_dir_files = $cur_dir_info -split "`n`r"
            continue
        } else {
            Write-Output "Error: $dest is not a directory"
            Write-Output "Use option `"-p`" to recursively create parent dirs"
            exit
        }
    }
}

function GetDriveFileInfo($src, $filename, $drive_files) {
    $file_type = $(FileIsDir $src $filename)

    ForEach ($drive_line in $drive_files) {
        $drive_line = $drive_line -split ":DELIMITER?", 0, "simplematch"
        # Case sensitive, since Google Drive can contain files w/ the same name but different case
        if ($drive_line[1] -ceq $filename) {
            if ($file_type -eq [FileType]::DIR -and $drive_line[2] -eq "folder") {
                return @($drive_line[0], [FileType]::DIR, $drive_line[4])
            } elseif ($file_type -eq [FileType]::FILE -and $drive_line[2] -ne "folder") {
                return @($drive_line[0], $file_type, $drive_line[4])
            }
        }
    }
    return @($null, $file_type, $null)
}

function GetFileLists($src, $dest, $dest_is_id) {
    try {
        $local_files = $(Get-ChildItem $src -Name)
    } catch [System.Management.Automation.ItemNotFoundException] {
        Write-Output "Invalid local directory path: " + $src + " not found"
        exit
    }

    if (!$dest_is_id) {
        $dest_id = $(GetDriveDirIdFromPath $dest)
    } else {
        $dest_id = $dest
    }

    try {
        if ($dest_id -eq "") {
            $drive_info = gdrive files list --field-separator ":DELIMITER?" --order-by name --skip-header --full-name
        } else {
            $drive_info = gdrive files list --parent $dest_id --field-separator ":DELIMITER?" --order-by name --skip-header --full-name
        }
        $drive_files = $drive_info -split "`n`r"
    } catch [System.Management.Automation.RemoteException] {
        echo "Invalid Google Drive id: Dir not found"
        exit
    }
    
    return $local_files, $drive_files, $dest_id
}

function BackUpFolder($src, $filename, $dest_id, $drive_file_id, $drive_file_create_time) {
    if (!$recursive) { return }

    if ($null -ne $drive_file_id) {
        $dest_id = $drive_file_id
    } else {
        $dest_id = $(gdrive files mkdir --print-only-id --parent $dest_id $filename)
    }
    LoopThroughSrc "$src\$filename" $dest_id $true
}

function BackUpFile($src, $filename, $dest_id, $drive_file_id, $drive_file_create_time) {
    if ($null -ne $drive_file_id) {
        $local_write_time = (Get-ChildItem "$src\$filename").LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        if ($local_write_time -gt $drive_file_create_time) {
            $current_datetime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            (Get-Item "$src\$filename").LastWriteTime = $current_datetime
            gdrive files delete $drive_file_id
            gdrive files upload --parent $dest_id "$src\$filename"
        }
    } else {
        gdrive files upload --parent $dest_id "$src\$filename"
    }
}

function LoopThroughSrc($src, $dest, $dest_is_id) {
    $local_files, $drive_files, $dest_id = $(GetFileLists $src $dest $dest_is_id)

    ForEach ($filename in $local_files) {
        $drive_file_id, $file_type, $drive_file_create_time = $(GetDriveFileInfo $src $filename $drive_files)
        if ($file_type -eq [FileType]::DIR) {
            BackUpFolder $src $filename $dest_id $drive_file_id $drive_file_create_time
        } else {
            BackUpFile $src $filename $dest_id $drive_file_id $drive_file_create_time
        }
    }
}

# Make sure non-terminating exceptions are caught
$ErrorActionPreference = "Stop"


LoopThroughSrc $src $dest $dest_is_id
