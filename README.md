# gdrive-stash

Quickly and easily up local files and directories to your Google Drive from the command line.

# About

gdrive-stash is a simple script intended as an addon for [glotlabs' gdrive](https://github.com/glotlabs/gdrive?tab=MIT-1-ov-file). Specify a local directory and a destination Google Drive path, and the script takes care of the rest. It saves time by only uploading files that have been overwritten since their  last backup, so runtime is generally pretty good unless you have a lot of files.

# Usage

gdrive-stash takes two required parameters, `$srcDir` and `$destDir`:

- `$srcDir`: The path to the folder to back up

- `$destDir`: The path to the folder where you will save the backed-up files (they are copied directly into `$srcDir`; a subfolder called `$destDir` is NOT created)

For `$destDir`, `"\"` is treated as Google Drive's root directory (the folder called "My Drive" in Google Drive).

By default, gdrive-stash only copies files from the top level of `$srcDir`. To copy all subdirectories and their contents, pass the flag `-r` (short for `-recursive`).

Additionally, by default gdrive-stash will exit if you pass a nonexistant path as your `$destDir` value. To force gdrive-stash to create the `$destDir` path if it doesn't exist, pass the flag `-p` (short for `-makeParents`).

Finally, to speed up runtime, you can optionally pass a Google Drive ID instead of a path into `$destDir`. If you do this, make sure to pass the flag `-i` too (short for `$destDirIsId`).

IMPORTANT: Any flags must be passed after `$srcDir` and `$destDir`, not before, unless you specify them explicity by preceding them with `-srcDir` and `-destDir`.

- Wrong: `.\gdrive-stash.ps1 "C:\path\to\my\stuff" -r "\"`

- Ok: `.\gdrive-stash.ps1 "C:\path\to\my\stuff" "\" -r`

- Also ok: `.\gdrive-stash.ps1 -srcDir "C:\path\to\my\stuff" -r -destDir "\"` 

## Examples

`gdrive-stash "C:\foo\bar\mystuff" "\"`

Result: All files in `mystuff` are copied into Google Drive's root directory,
excluding subdirectories.

`gdrive-stash "C:\foo\bar\mystuff" "\mybackups"`

Result: All files in `mystuff`, excluding subdirectories, are copied into
`mybackups`, which resides in Google Drive's root directory. If `mybackups`
doesn't exist, the script will exit.

`gdrive-stash "C:\foo\bar\mystuff" "\mybackups\todays-date" -p`

Result: All files in `mystuff`, excluding subdirectories, are copied
into `mybackups\todays-date`, which resides in Google Drive's root directory.
If either of those directories doesn't exist, they will be created.

`gdrive-stash "C:\foo\bar\mystuff" "\mybackups" -r`

Result: All files in `mystuff`, including subdirectories, are recursively
copied into `mybackups`, which resides in Google Drive's root directory.

`gdrive-stash "C:\foo\bar\mystuff" "1Fn7xLIHE_iIY8o5MHbjQaAX20PdnE0ZD" -r -i`

Result: All files in `mystuff`, including subdirectories, are recursively
copied into the directory with Google Drive ID `1Fn7xLIHE_iIY8o5MHbjQaAX20PdnE0ZD`. 

You can get the Google Drive ID of a file by calling `gdrive files list`; the first value on each row is the ID. From there, you can get the IDs of subdirectories by calling `gdrive files list --parent [ID]`, using the ID of the subdirectory you want to examine.

# Installation

Download `gdrive-stash.ps1` and call it from the command prompt, use it in a script, or do whatever you want with it. You may want to place it in a folder that's on your path.
