function Process-Batch {
    param (
        [Parameter(Mandatory)] [System.Collections.Generic.List[System.IO.FileInfo]] $Files,
        [String] $CsvPath,
        [Hashtable] $ExistingHashes
    )

    foreach ($file in $Files) {
        try {
            # Skip hashing if the file is already hashed
            if ($ExistingHashes.ContainsKey($file.FullName)) {
                Write-Host "Skipping file, hash already exists: $($file.FullName)"
                continue
            }

            # Ensure the file object is not null and accessible before hashing
            if ($null -eq $file -or -not (Test-Path $file.FullName)) {
                Write-Host "Skipping invalid file: $($file.FullName)"
                continue
            }

            # Use Get-FileHash to compute the file hash
            $fileHash = Get-FileHash -Path $file.FullName -Algorithm SHA1
            if ($fileHash) {
                # Log the hash calculation for debugging
                Write-Host "Hash computed for: $($file.FullName) - Hash: $($fileHash.Hash)"
                
                # Update the hash table and immediately write the result to the CSV file
                $ExistingHashes[$file.FullName] = $fileHash.Hash
                Add-Content -Path $CsvPath -Value "$($fileHash.Hash),$($file.FullName)"
            }
        } catch {
            Write-Host "Error hashing file: $($file.FullName). Error: $_" -ForegroundColor Red
        }
    }
}

function Find-PSOneDuplicateFile {
    param (
        [String] [Parameter(Mandatory)] $Path,
        [String] $Filter = '*',
        [String[]] $ExcludedFolders = @(),  # Array of folders to exclude
        [String] $HashedCsvPath = "hashedFiles.csv",  # Path to the CSV file storing hashes
        [String] $DuplicatesCsvPath = "duplicate_files.csv"  # Path to the CSV file for duplicates
    )

    # Normalize excluded folder paths to trim trailing backslashes and make them lowercase
    $normalizedExcludedFolders = $ExcludedFolders | ForEach-Object { ($_ -replace '\\$', '').ToLower() }

    # Check if the path exists
    if (-not (Test-Path $Path)) {
        Write-Host "The path $Path does not exist." -ForegroundColor Red
        return
    }

    # Load existing hashes into a hash table for quick lookup
    $existingHashes = @{}
    if (Test-Path $HashedCsvPath) {
        $hashedFiles = Import-Csv -Path $HashedCsvPath
        foreach ($file in $hashedFiles) {
            $existingHashes[$file.Filename] = $file.HASH
        }
    }

    # Initialize the CSV file if it does not exist
    if (-not (Test-Path $HashedCsvPath)) {
        $header = @("HASH", "Filename")
        $header -join "," | Out-File -FilePath $HashedCsvPath -Force
    }

    # Define batch size
    $batchSize = 1000

    # Create a list to hold file paths for the current batch
    $batchFiles = @()

    # Try to get all files recursively
    try {
        Write-Host "Starting to enumerate files in directory: $Path"
        $allFiles = Get-ChildItem -Path $Path -Recurse -Filter $Filter -File -ErrorAction Stop
    } catch {
        Write-Host "Error accessing some directories: $_" -ForegroundColor Red
        return
    }

    $totalFiles = ($allFiles | Measure-Object).Count
    $processedFiles = 0

    foreach ($file in $allFiles) {
        Write-Host "Processing file: $($file.FullName)"  # Log file being processed
        $fileDir = $file.DirectoryName -replace '\\$', ''
        $fileDirLower = $fileDir.ToLower()

        # Optimized exclusion check
        $exclude = $normalizedExcludedFolders | Where-Object { $fileDirLower -like "$_*" }
        if (-not $exclude) {
            # Add file to the current batch
            $batchFiles += $file

            # Update progress
            if ($totalFiles -gt 0) {
                $processedFiles++
                $progressPercent = [math]::Round(($processedFiles / $totalFiles) * 100, 2)
                Write-Progress -Activity "Processing Files" -Status "Processed $processedFiles of $totalFiles files" -PercentComplete $progressPercent
            }

            # Process batch if the batch size is reached
            if ($batchFiles.Count -ge $batchSize) {
                Process-Batch -Files $batchFiles -CsvPath $HashedCsvPath -ExistingHashes $existingHashes
                $batchFiles = @()  # Clear the batch
            }
        }
    }

    # Process any remaining files
    if ($batchFiles.Count -gt 0) {
        Process-Batch -Files $batchFiles -CsvPath $HashedCsvPath -ExistingHashes $existingHashes
    }

    # Complete progress bar
    Write-Progress -Activity "Processing Files" -Status "Completed" -Completed

    Write-Host "Hashing completed."

    # Find duplicates and save them
    Write-Host "Finding duplicates..."
    Find-Duplicates -HashedCsvPath $HashedCsvPath -DuplicatesCsvPath $DuplicatesCsvPath

    # Modify the duplicates CSV to add blank lines between different hashes
    Write-Host "Adding blank lines to duplicates CSV..."
    Add-Blank-Lines-To-DuplicatesCsv -CsvPath $DuplicatesCsvPath -ModifiedCsvPath $DuplicatesCsvPath
}


function Add-Blank-Lines-To-DuplicatesCsv {
    param (
        [String] $CsvPath,
        [String] $ModifiedCsvPath
    )

    # Read the existing CSV
    $csvContent = Import-Csv -Path $CsvPath

    # Create a list to hold the new CSV content
    $newCsvContent = @()

    # Group by hash and add blank lines between different hashes
    $currentHash = ""
    foreach ($row in $csvContent) {
        if ($row.HASH -ne $currentHash) {
            if ($currentHash -ne "") {
                # Add a blank line to separate different hashes
                $newCsvContent += ""
            }
            $currentHash = $row.HASH
        }
        $newCsvContent += "$($row.HASH),$($row.Path)"
    }

    # Write the modified content back to the CSV file
    $newCsvContent | Out-File -FilePath $ModifiedCsvPath -Encoding UTF8
    Write-Host "Modified CSV with blank lines between different hashes has been saved to $ModifiedCsvPath."
}

function Find-Duplicates {
    param (
        [String] $HashedCsvPath,
        [String] $DuplicatesCsvPath
    )

    if (-not (Test-Path $HashedCsvPath)) {
        Write-Host "Hashed CSV file not found." -ForegroundColor Red
        return
    }

    # Read the hashed file information
    $hashedFiles = Import-Csv -Path $HashedCsvPath

    # Group files by hash and find duplicates
    $duplicates = $hashedFiles | Group-Object -Property HASH | Where-Object { $_.Count -gt 1 } | ForEach-Object {
        $group = $_
        $group.Group | ForEach-Object {
            [PSCustomObject]@{
                HASH = $group.Name
                Path = $_.Filename
            }
        }
    }

    # Write results to CSV
    if (Test-Path $DuplicatesCsvPath) {
        Remove-Item $DuplicatesCsvPath -Force
    }
    $duplicates | Export-Csv -Path $DuplicatesCsvPath -NoTypeInformation -Force
    Write-Host "Duplicates have been saved to $DuplicatesCsvPath."
}


# Example Path and Excluded Folders
$Path = "C:\Sample\Path"  # Ensure this directory exists and has files

$ExcludedFolders = @(
    "C:\Excluded\Folder1",
    "C:\Excluded\Folder2"
)  # Example excluded folders

$HashedCsvPath = "C:\Users\SampleUser\hashedFiles.csv"  # Path to the CSV file storing hashes
$DuplicatesCsvPath = "C:\Users\SampleUser\duplicate_files.csv"  # Path to the CSV file for duplicates
Find-PSOneDuplicateFile -Path $Path -ExcludedFolders $ExcludedFolders -HashedCsvPath $HashedCsvPath -DuplicatesCsvPath $DuplicatesCsvPath
