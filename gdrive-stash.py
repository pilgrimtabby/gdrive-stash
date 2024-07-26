#!/usr/bin/env python3

# MIT License
#
# Copyright (c) 2024 pilgrim_tabby
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Copy a directory's files to a directory in Google Drive.

An add-on for the gdrive CLI (https://github.com/glotlabs/gdrive).
Loops through files in a local directory src_dir (and its subdirectories if
recursive is True) and puts them directly into a Google Drive directory
dest_dir.

Command line args:
    src_dir (str): The locally stored parent directory of the directory to be
        backed up. Ex: ~/tools/ (trailing slash optional). Required.

    dest_dir (str): The full path OR the Google Drive ID of the target folder.
        Files inside srcDir will be copied directly inside destDir. Using an ID
        is faster but the full path is easier to obtain. Required.
        
        Paths begin with "\" (forward slashes are converted to backslashes in
        resolve_drive_dir_id). Passing "\" will copy the files in srcDir into
        Google Drive's root directory. To copy files into a folder called "My
        Backups" in your drive's root, you would pass destDir as "\My Backups".

    recursive (bool): Tells function to recursively back up subdirectories in
        src_dir. Default is False. Optional.

    make_parents (bool): When enabled, tells Resolve-DriveDirId to create any
        directories in dest_dir's path that don't already exist. If this is
        False and dest_dir doesn't exist, the script will exit. Default is
        False. Optional.

    dest_dir_is_id (bool): Tells function to treat dest_dir as a Google Drive
        ID, not a pathname. Default is False. Optional.

Usage examples:
    gdrive-stash "C:\foo\bar\mystuff" "\"
    Result: All files in "mystuff" are copied into Google Drive's root dir,
    excluding subdirectories.

    gdrive-stash "C:\foo\bar\mystuff" "\mybackups"
    Result: All files in "mystuff", excluding subdirectories, are copied into
    "mybackups", which resides in Google Drive's root directory. If "mybackups"
    doesn't exist, the script will exit.

    gdrive-stash "C:\foo\bar\mystuff" "\mybackups\todays-date" -p
    Result: All files in "mystuff", excluding subdirectories, are copied
    into "mybackups\todays-date", which resides in Google Drive's root dir.
    If either of those directories doesn't exist, they will be created.

    gdrive-stash "C:\foo\bar\mystuff" "\mybackups" -r
    Result: All files in "mystuff", including subdirectories, are recursively
    copied into "mybackups", which resides in Google Drive's root directory.

    gdrive-stash "C:\foo\bar\mystuff" "1Fn7xLIHE_iIY8o5MHbjQaAX20PdnE0ZD" -r -i
    Result: All files in "mystuff", including subdirectories, are recursively
    copied into the dir with Google Drive ID 1Fn7xLIHE_iIY8o5MHbjQaAX20PdnE0ZD.
    This is much faster than having to crawl through an entire directory path,
    but it may not be worth the effort...
"""


#########################
#                       #
# Function Declarations #
#                       #
#########################

import argparse
import os
import platform
import subprocess
import sys
from datetime import datetime, timezone
from enum import Enum, auto
from pathlib import Path
from typing import Union


class FileType(Enum):
    """Categorize a file into one of two types: non-dir file or dir."""
    DIR = auto()
    FILE = auto()


def back_up_dir(src_dir: str, dest_dir: str, recursive: bool, make_parents: bool, dest_dir_is_id: bool) -> None:
    """Back up a directory (and optionally, its subdirectories) to Google Drive.

    Iterates through all non-directory files, calling back_up_file on each one.
    If "recursive" is True, also recursively backs up subdirectories.
    See module docstring for arg information and examples.
    """
    # Get list of files in src_dir
    src_files = get_local_files(src_dir)

    # Get destId
    if dest_dir_is_id:
        dest_id = dest_dir
    else:
        dest_id = resolve_drive_dir_id(dest_dir, make_parents)

    # Get list of files in dest_dir
    dest_files = get_drive_file_list(dest_id)

    # Iterate through files
    for filename in src_files:
        file_type = get_file_type(src_dir, filename)
        file_id, drive_file_create_time = get_drive_file_info(filename, file_type, dest_files)

        # Either skip or recursively dive into directories, depending on -r
        if recursive and file_type == FileType.DIR:

            # Subdir doesn't exist in Google Drive, so we create it
            if file_id is None:
                gdrive_args = [
                    get_exec_path("gdrive"),
                    "files",
                    "mkdir",
                    "--print-only-id",
                    "--parent",
                    dest_id,
                    filename,
                ]

                # Calling `.strip()` removes trailing newline from check_output
                new_dest_id = subprocess.check_output(gdrive_args).decode().strip()

            # Subdir exists in Google Drive
            else:
                new_dest_id = file_id
            
            new_src = f"{src_dir}/{filename}"
            back_up_dir(new_src, new_dest_id, True, make_parents, True)

        # Back up all other file types directly
        elif file_type == FileType.FILE:
            back_up_file(src_dir, filename, dest_id, file_id, drive_file_create_time)


def get_local_files(src_dir: str) -> list[str]:
    """Return list of all files, including subdirectories, inside a directory.

    Args:
        src_dir (str): The directory whose files are returned.

    Returns:
        list[str]: List containing the relative path to each file in src_dir.
    """
    try:
        return os.listdir(src_dir)
    
    # Folder doesn't exist
    except FileNotFoundError:
        sys.exit(f"Error: directory {src_dir} does not exist")


def get_drive_file_list(dest_id: str | None) -> list[str]:
    """Return list of strings, each string containing info about a Drive file.

    Each entry in the list contains the following information, in order:
    -Google Drive ID (obtained by calling `gdrive files list`)
    -Filename
    -File type (folder, regular, document, etc.)
    -File size (for directories, this is blank)
    -Date and time file was created

    The delimiter ":DELIMITER?" separates discreet pieces of information in
    each entry in the array. This string is used because it's unlikely to be
    used in a filename, and it uses a forbidden filename character for both 
    Windows ("?") and MacOS (":").

    Args:
        dest_id (str | None): The Google Drive ID of the target directory.

    Returns:
        list[str]: The list of file information.
    """
    gdrive_args = [
        get_exec_path("gdrive"),
        "files",
        "list",
        "--field-separator",
        ":DELIMITER?",
        "--skip-header",
        "--full-name",
    ]
    try:
        if dest_id is not None:  # Not listing files in Google Drive's root
            gdrive_args += ["--parent", dest_id]
        return subprocess.check_output(gdrive_args).decode().strip().split("\n")
    
    # Returned if dest_id doesn't point to a valid Google Drive directory
    except subprocess.CalledProcessError:
        sys.exit(f"Error: directory with ID {dest_id} not found")


def get_drive_file_info(
    filename: str, file_type: FileType, drive_files: list
) -> tuple[Union[str, None], Union[datetime, None]]:
    """Search a Drive dir for a file matching a local file's name and type.

    Make a case-sensitive search in a Google Drive directory for a file with a
    given filename and type (Google Drive files aren't case sensitive, but
    local files generally are). Possible file types are directory and file (see
    enum FileType).

    Args:
        filename (str): The name of the file to search for.
        file_type (FileType): The type of the file to search for.
        drive_files (list): The array of file entries to search through. See the
            docstring for get_drive_file_list for more information.

    Returns:
        file_id (str | None): The Google Drive ID of the file. If the directory
            is empty or the file isn't found, returns None.
        file_create_time (datetime | None): The time and date the Google Drive
            file was created (in the machine's time zone). None if the file
            doesn't exist.
        
    """
    if drive_files == [""]:  # Empty directory
        return None, None

    for line in drive_files:
        file_info = line.split(":DELIMITER?")
        drive_name = file_info[1]
        drive_type = file_info[2]

        if drive_name == filename and (
            (file_type == FileType.DIR and drive_type == "folder")
            or (file_type == FileType.FILE and drive_type != "folder")
        ):
            # Drive file creation timestamp is stored in this format
            fmt = "%Y-%m-%d %H:%M:%S"
            # Calling astimezone makes value aware, allowing us to compare it
            file_create_time = datetime.strptime(file_info[4], fmt).astimezone()

            file_id = file_info[0]
            return file_id, file_create_time

    return None, None


def resolve_drive_dir_id(dest_dir: str, make_parents: bool) -> Union[str, None]:
    """Get (or create) the Google Drive ID for a directory.

    Crawls the path dest_dir to its last dir and returns its Google Drive ID.
    If the path doesn't exist and make_parents is True, then all missing
    directories are created in Google Drive.

    Args:
        dest_dir (str): The directory whose ID is extracted.
        make_parents (bool): If true, any directories that don't exist in
            Google Drive are created. If false and dest_dir doesn't exist, the
            script exits.

    Returns:
        next_dir_id (str | None): The Google Drive ID of the directory. If the
            directory is Google Drive's root directory, returns None.
    """
    gdrive_path = get_exec_path("gdrive")
    gdrive_args = [
        gdrive_path,
        "files",
        "list",
        "--field-separator",
        ":DELIMITER?",
        "--skip-header",
        "--full-name",
    ]
    curr_file_list = subprocess.check_output(gdrive_args).decode().strip().split("\n")
    curr_dir_id = None
    curr_dir_count = 1
    # Standardize slash direction and remove leading and trailing slashes
    dirs_in_path = dest_dir.replace("/", "\\").strip("\\").split("\\")

    # Special case -- user requested root dir as dest_dir
    if dirs_in_path == [""]:
        return get_root_id()

    # Get Google Drive ID of each directory in order
    for next_dir in dirs_in_path:
        next_dir_id, _ = get_drive_file_info(next_dir, FileType.DIR, curr_file_list)

        # Next directory exists
        if next_dir_id is not None:
            # It's the last directory, we don't need to call gdrive
            if curr_dir_count == len(dirs_in_path):
                break

            gdrive_args = [
                gdrive_path,
                "files",
                "list",
                "--field-separator",
                ":DELIMITER?",
                "--skip-header",
                "--full-name",
                "--parent",
                next_dir_id,
            ]
            next_file_list = subprocess.check_output(gdrive_args).decode().strip().split("\n")

        # Next directory doesn't exist
        elif make_parents:

            # Current directory is root
            if curr_dir_id is None:
                gdrive_args = [
                    gdrive_path,
                    "files",
                    "mkdir",
                    "--print-only-id",
                    next_dir
                ]
                next_dir_id = subprocess.check_output(gdrive_args).decode().strip()
            
            # Current directory is not root
            else:
                gdrive_args = [
                    gdrive_path,
                    "files",
                    "mkdir",
                    "--print-only-id",
                    "--parent",
                    curr_dir_id,
                    next_dir,
                ]
                next_dir_id = subprocess.check_output(gdrive_args).decode().strip()

            next_file_list = [""]

        # Current directory doesn't exist, we don't have permission to make it
        else:
            sys.exit(f"Error: destination {dest_dir} is not a directory (case-sensitive)\n"
                     "Use option \"-p\" to recursively create parent dirs"
            )
        
        # Update vars for next loop
        curr_dir_id = next_dir_id
        curr_file_list = next_file_list
        curr_dir_count += 1
    
    return next_dir_id


def back_up_file(src_dir: str, filename: str, dest_id: str, file_id: str | None, drive_file_create_time: datetime | None) -> None:
    """Upload or update a local file into Google Drive.

    If a file already exists in the directory at dest_id, we check if its last
    write time is more recent than the Drive file's creation time. If so, we
    know it has been modified, so we delete and re-upload it.

    Deleting and re-uploading is only marginally slower than simply updating,
    and it allows us to reset the Drive file's creation date, since that value
    is set to be the time of upload. This lets us compare that time with the
    local write time later on to see if changes have been made (it's much more
    difficult to access Drive files' most recent write date).

    If a file doesn't exist in the dir at dest_id yet, then upload it.

    .DS_Store files are never uploaded.

    Args:
        src_dir (str): The parent directory of the file to back up.
        filename (str): The name of the file to back up, e.g. myfile.txt.
        dest_id (str): The Drive ID of the folder we're copying files into.
        file_id (str | None): The Google Drive ID of the file we are dealing
            with, if the file already exists in the dir at dest_id. If None,
            it is assumed the file doesn't exist, and the file is then uploded.
        drive_file_create_time (datetime): The Google Drive creation date
            (upload date) of the file we are dealing with. If None, it is
            assumed the file doesn't exist, and the file is then uploaded.
    """
    if filename == ".DS_Store":
        return
    
    gdrive_path = get_exec_path("gdrive")
    gdrive_args_upload = [
        gdrive_path,
        "files",
        "upload",
        "--parent",
        dest_id,
        f"{src_dir}/{filename}",
    ]

    # File isn't in Drive yet
    if file_id is None:
        subprocess.Popen(gdrive_args_upload)

    # Check if file has been updated since last upload
    else:
        # Get local file's last write time in machine's timezone
        last_write_raw = os.path.getmtime(f"{src_dir}/{filename}")
        local_tz = datetime.now(timezone.utc).astimezone().tzinfo
        last_write = datetime.fromtimestamp(last_write_raw, local_tz)

        if last_write > drive_file_create_time:
            # Delete & re-upload the file
            gdrive_args_del = [gdrive_path, "files", "delete", file_id]
            subprocess.Popen(gdrive_args_del)
            subprocess.Popen(gdrive_args_upload)


def get_root_id() -> str:
    """Return the Google Drive ID of the Drive root directory.

    There's no way to query it directly, so we create a temporary directory
    in the root, access its parent ID, then delete the temporary directory.

    Returns:
        root_id (str): The root directory's ID.
    """
    # Create tmp directory in root
    gdrive_path = get_exec_path("gdrive")
    gdrive_args = [
        gdrive_path,
        "files",
        "mkdir",
        "tmp",
        "--print-only-id",
    ]
    tmp_dir_id = subprocess.check_output(gdrive_args).decode().strip()

    # Get tmp directory's information
    gdrive_args = [
        gdrive_path,
        "files",
        "info",
        tmp_dir_id,
    ]
    tmp_dir_info = subprocess.check_output(gdrive_args).decode().strip().split("\n")

    # Extract the root dir's ID
    root_id = None
    for line in tmp_dir_info:
        if "Parents: " in line:
            root_id = line.split("Parents: ")[1]
            break

    # Delete the tmp directory by ID
    gdrive_args = [
        gdrive_path,
        "files",
        "delete",
        "--recursive",
        tmp_dir_id,
    ]
    subprocess.Popen(gdrive_args)

    # Return the root ID if everything went ok
    if root_id is None:
        sys.exit("Error: Could not save files to Google Drive root directory at this time.")
    return root_id


def get_file_type(src_dir: str, filename: str):
    """Get a file's type (i.e. directory or not directory).

    Args:
        src_dir (str): The file's parent dir.
        filename (str): The file's name, including extension. Ex: my_file.txt

    Returns:
        FileType: FileType.DIR if directory, otherwise FileType.FILE.
    """
    if Path(f"{src_dir}/{filename}").is_dir():
        return FileType.DIR
    return FileType.FILE


def get_exec_path(name: str) -> str:
    """Return the path to an executable file, if it exists.

    Args:
        exec_name (str): The name (not path) of an exectable file. Ex: "grep"

    Returns:
        str: The path to the executable, if it exists.
    """
    if platform.system() == "Windows":
        search = "where"
    else:
        search = "which"
    try:
        return subprocess.check_output([search, name]).decode().strip()
    
    # The executable doesn't exist (or at least isn't on PATH)
    except subprocess.CalledProcessError:
        sys.exit(f"Error: executable {name} not found.\n"
                 f"Please verify {name} is installed and on PATH.")


##########
#        #
# Script #
#        #
##########

# Parse args
parser = argparse.ArgumentParser(
    prog="gdrive-stash",
    description="Quickly and easily upload local files and directories to your Google Drive "
                "from the command line.",
)
parser.add_argument("-r", "-recursive", action="store_true")
parser.add_argument("-p", "-makeParents", action="store_true")
parser.add_argument("-i", "-destDirIsId", action="store_true")
parser.add_argument("src_dir", type=str)
parser.add_argument("dest_dir", type=str)

args = parser.parse_args()
back_up_dir(args.src_dir, args.dest_dir, args.r, args.p, args.i)
