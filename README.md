# Find-PSOneDuplicateFile PowerShell Script

## Overview

`Find-PSOneDuplicateFile` is a PowerShell script designed to identify and manage duplicate files within a specified directory. The script recursively scans files, computes SHA1 hashes using `certutil`, and identifies duplicates based on these hashes. The results are saved to CSV files for easy review and further action.

## Features

- **Recursive File Search**: Scans all files in the specified directory and its subdirectories.
- **Batch Processing**: Processes files in batches to optimize memory usage and performance.
- **Exclusion of Folders**: Specify folders to exclude from the duplicate check.
- **SHA1 Hashing**: Uses `certutil` to compute SHA1 hashes for files.
- **CSV Output**: Saves both hashed file data and duplicate file information to CSV files.
- **Error Handling**: Includes mechanisms to handle file access issues and retry hashing operations.

## Prerequisites

- PowerShell 5.0 or later.
- Windows OS with `certutil` available (default on Windows).

## Script Parameters

| Parameter           | Type    | Description                                                                 |
|---------------------|---------|-----------------------------------------------------------------------------|
| `-Path`             | String  | The root directory path to scan for duplicate files. Mandatory.             |
| `-Filter`           | String  | File filter to apply (e.g., `*.txt`). Defaults to `*`.                      |
| `-ExcludedFolders`  | String[]| Array of folders to exclude from scanning.                                  |
| `-HashedCsvPath`    | String  | Path to the CSV file where file hashes are stored. Default is `hashedFiles.csv`. |
| `-DuplicatesCsvPath`| String  | Path to the CSV file where duplicate file information is stored. Default is `duplicate_files.csv`. |

## Usage

### Basic Example

```powershell
# Example of running the script
$Path = "C:\Your\Directory\Path"
$ExcludedFolders = @("C:\Your\Directory\Path\ExcludeThis")
$HashedCsvPath = "hashedFiles.csv"
$DuplicatesCsvPath = "duplicate_files.csv"

Find-PSOneDuplicateFile -Path $Path -ExcludedFolders $ExcludedFolders -HashedCsvPath $HashedCsvPath -DuplicatesCsvPath $DuplicatesCsvPath
```
### Parameters Explained

- **`Path`**: The directory path where you want to search for duplicate files. This is the main input parameter.
  
- **`ExcludedFolders`**: A list of folders you want to exclude from the search. For example, if there are temporary directories or system directories that you do not wish to include, list them here.

- **`HashedCsvPath`**: The CSV file where the script will store the hashes of the files it processes. You can specify a custom path or use the default.

- **`DuplicatesCsvPath`**: The CSV file where the script will save information about duplicate files it finds. You can specify a custom path or use the default.

## Output

### Hashed Files CSV (`hashedFiles.csv`)

This CSV file contains the SHA1 hashes of all processed files, along with their paths.

- **Columns**:
  - `HASH`: The SHA1 hash of the file.
  - `Filename`: The full path of the file.

### Duplicates CSV (`duplicate_files.csv`)

This CSV file lists all files identified as duplicates based on their SHA1 hashes.

- **Columns**:
  - `HASH`: The SHA1 hash shared by duplicate files.
  - `Path`: The full path of each duplicate file.

## Error Handling

The script includes mechanisms to handle common issues, such as inaccessible files or temporary file access errors. It will retry failed hash computations up to 3 times before skipping a file.

## Acknowledgments

This script is based on the original work done by PSOne Tools. You can find the original script at the [PowerShell Gallery](https://www.powershellgallery.com/packages/PSOneTools/1.8/Content/Find-PSOneDuplicateFile.ps1).

## Contributing

If you'd like to contribute to this script, feel free to fork the repository and submit a pull request. Any improvements or additional features are welcome!
