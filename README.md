# gdrive-stash

Quickly and easily upload local files and directories to your Google Drive from the command line.

# About

gdrive-stash is a simple script intended as an addon for [glotlabs's gdrive](https://github.com/glotlabs/gdrive). Older, deprecated versions of gdrive offered the ability to upload the contents of entire local folders to Drive, but it is no longer possible to do so with gdrive's currently maintained API.

This script restores this functionality: any files added or modified in the local directory are updated in Drive; files deleted locally are NOT deleted in Drive, though that functionality could be added fairly easily if there is interest.

The `.py` version of this script works on Windows, Linux, and MacOS. The `.ps1` script has only been tested on Windows and may not be compatible with other platforms.

# Usage

gdrive-stash takes two required parameters, `srcDir` and `destDir`:

- `srcDir`: The path to the folder to back up

- `destDir`: The path to the folder where you will save the backed-up files (they are copied directly into `srcDir`; a subfolder called `scrDir` is NOT created)

For `destDir`, `"\"` (or `"/"` on *NIX OSs) is treated as Google Drive's root directory (the folder called "My Drive" in Google Drive).

By default, gdrive-stash only copies files from the top level of `srcDir`. To copy all subdirectories and their contents, pass the flag `-r` (short for `-recursive`).

Additionally, by default gdrive-stash will exit if you pass a nonexistant path as your `destDir` value. To force gdrive-stash to create the `destDir` path if it doesn't exist, pass the flag `-p` (short for `-makeParents`).

Finally, to speed up runtime, you can optionally pass a Google Drive ID instead of a path into `destDir`. If you do this, make sure to pass the flag `-i` too (short for `destDirIsId`).

### NOTE (Powershell script only)

Any optional flags must be passed after `srcDir` and `destDir`, not before, unless you specify the required parameters explicity by preceding them with `-srcDir` and `-destDir`.

- Wrong: `.\gdrive-stash.ps1 "C:\path\to\my\stuff" -r "\"`

- Ok: `.\gdrive-stash.ps1 "C:\path\to\my\stuff" "\" -r`

- Also ok: `.\gdrive-stash.ps1 -srcDir "C:\path\to\my\stuff" -r -destDir "\"` 

## Examples

### NOTE: These examples use the Powershell script and Windows-style paths, but they apply equally when using the Python script and *NIX-style paths.

`.\gdrive-stash.ps1 "C:\foo\bar\mystuff" "\"`

Result: All files in `mystuff` are copied into Google Drive's root directory,
excluding subdirectories.

`.\gdrive-stash.ps1 "C:\foo\bar\mystuff" "\mybackups"`

Result: All files in `mystuff`, excluding subdirectories, are copied into
`mybackups`, which resides in Google Drive's root directory. If `mybackups`
doesn't exist, the script will exit.

`.\gdrive-stash.ps1 "C:\foo\bar\mystuff" "\mybackups\todays-date" -p`

Result: All files in `mystuff`, excluding subdirectories, are copied
into `mybackups\todays-date`, which resides in Google Drive's root directory.
If either of those directories doesn't exist, they will be created.

`.\gdrive-stash.ps1 "C:\foo\bar\mystuff" "\mybackups" -r`

Result: All files in `mystuff`, including subdirectories, are recursively
copied into `mybackups`, which resides in Google Drive's root directory.

`.\gdrive-stash.ps1 "C:\foo\bar\mystuff" "1Fn7xLIHE_iIY8o5MHbjQaAX20PdnE0ZD" -r -i`

Result: All files in `mystuff`, including subdirectories, are recursively
copied into the directory with Google Drive ID `1Fn7xLIHE_iIY8o5MHbjQaAX20PdnE0ZD`. 

You can get the Google Drive ID of a file by calling `gdrive files list`; the first value on each row is the ID. From there, you can get the IDs of subdirectories by calling `gdrive files list --parent [ID]`, using the ID of the subdirectory you want to examine.

# Installation

First, make sure that [glotlabs's gdrive tool](https://github.com/glotlabs/gdrive) is downloaded, on your path, and configured with Google OAuth Client credentials (this is easy to do with a basic Google account -- see their [guide](https://github.com/glotlabs/gdrive/blob/main/docs/create_google_api_credentials.md)).

Download `gdrive-stash.ps1` (Windows only) or `gdrive-stash.py` (Windows, Linux, MacOS) and call it from the command prompt, use it in a script, or do whatever you want with it. For easy access, you may want to place it in a folder that's on your path.
