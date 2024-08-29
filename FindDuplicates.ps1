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

    # Initialize CSV files
    if (Test-Path $HashedCsvPath) {
        Remove-Item $HashedCsvPath -Force
    }
    $header = @("HASH", "Filename")
    $header -join "," | Out-File -FilePath $HashedCsvPath -Force

    # Define batch size
    $batchSize = 1000

    # Create a list to hold file paths for the current batch
    $batchFiles = @()

    # Enumerate files using .NET method for better performance
    $allFiles = [System.IO.Directory]::EnumerateFiles($Path, $Filter, [System.IO.SearchOption]::AllDirectories)
    $totalFiles = ($allFiles | Measure-Object).Count
    $processedFiles = 0

    foreach ($filePath in $allFiles) {
        $file = New-Object -TypeName System.IO.FileInfo -ArgumentList $filePath
        $fileDir = $file.DirectoryName -replace '\\$', ''
        $fileDirLower = $fileDir.ToLower()

        # Optimized exclusion check
        $exclude = $normalizedExcludedFolders | Where-Object { $fileDirLower -like "$_*" }
        if (-not $exclude) {
            # Add file to current batch
            $batchFiles += $file

            # Update progress
            if ($totalFiles -gt 0) {
                $processedFiles++
                $progressPercent = [math]::Round(($processedFiles / $totalFiles) * 100, 2)
                Write-Progress -Activity "Processing Files" -Status "Processed $processedFiles of $totalFiles files" -PercentComplete $progressPercent
            }

            # Process batch if the batch size is reached
            if ($batchFiles.Count -ge $batchSize) {
                Process-Batch -Files $batchFiles -CsvPath $HashedCsvPath
                $batchFiles = @()  # Clear the batch
            }
        }
    }

    # Process any remaining files
    if ($batchFiles.Count -gt 0) {
        Process-Batch -Files $batchFiles -CsvPath $HashedCsvPath
    }

    # Complete progress bar
    Write-Progress -Activity "Processing Files" -Status "Completed" -Completed

    Write-Host "Hashing completed."

    # Find duplicates and save them
    Find-Duplicates -HashedCsvPath $HashedCsvPath -DuplicatesCsvPath $DuplicatesCsvPath
}


function Process-Batch {
    param (
        [Parameter(Mandatory)] [System.Collections.Generic.List[System.IO.FileInfo]] $Files,
        [String] $CsvPath
    )

    # Accumulate CSV data in memory
    $csvData = @()

    foreach ($file in $Files) {
        try {
            # Ensure the file is accessible before hashing
            if (-not (Test-Path $file.FullName)) {
                continue
            }

            # Use certutil to compute the file hash with quoted file path
            $certutilCommand = "certutil -hashfile `"$($file.FullName)`" SHA1"
            
            # Retry mechanism for certutil command
            $maxRetries = 3
            $retryCount = 0
            $fileHashOutput = $null
            while ($retryCount -lt $maxRetries -and $fileHashOutput -eq $null) {
                $fileHashOutput = & cmd.exe /c $certutilCommand 2>&1
                if ($fileHashOutput -match "ERROR_FILE_INVALID") {
                    $retryCount++
                    Start-Sleep -Seconds 1
                } else {
                    break
                }
            }

            # Extract hash from the output
            $fileHash = $fileHashOutput | Select-String -Pattern "^[0-9a-fA-F]{40}$"
            if ($fileHash) {
                $hashKey = $fileHash.ToString().Trim()

                # Accumulate results for batch writing
                $csvData += "$hashKey,$($file.FullName)"
            }

        } catch {
            Write-Warning "Could not hash file: $($file.FullName). Error: $_"
        }
    }

    # Write the entire batch to the CSV file at once
    $csvData | Out-File -FilePath $CsvPath -Append
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
$Path = "C:\Path\To\Folder"  # Ensure this directory exists and has files
$ExcludedFolders = @("C:\Path\To\Folder\Excluded1","C:\Path\To\Folder\Excluded2")  # Example excluded folders
$HashedCsvPath = "hashedFiles.csv"  # Path to the CSV file storing hashes
$DuplicatesCsvPath = "duplicate_files.csv"  # Path to the CSV file for duplicates
Find-PSOneDuplicateFile -Path $Path -ExcludedFolders $ExcludedFolders -HashedCsvPath $HashedCsvPath -DuplicatesCsvPath $DuplicatesCsvPath
