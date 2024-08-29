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

    # Initialize CSV file with correct headers
    if (Test-Path $HashedCsvPath) {
        Remove-Item $HashedCsvPath -Force
    }
    $header = "HASH,Filename"
    Out-File -FilePath $HashedCsvPath -InputObject $header -Encoding UTF8

    # Define batch size
    $batchSize = 1000
    $fileIndex = 0

    # Create a list to hold file paths for the current batch
    $batchFiles = @()

    # Get total file count for progress calculation
    $totalFiles = (Get-ChildItem -Path $Path -Filter $Filter -File -Recurse -ErrorAction SilentlyContinue | Where-Object {
        $fileDir = $_.DirectoryName -replace '\\$', ''
        $fileDirLower = $fileDir.ToLower()
        $normalizedExcludedFolders -notcontains $fileDirLower
    }).Count

    # Calculate the total number of batches
    $totalBatches = [math]::Ceiling($totalFiles / $batchSize)

    # Enumerate files and process in batches
    Get-ChildItem -Path $Path -Filter $Filter -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $file = $_
        $fileDir = $file.DirectoryName -replace '\\$', ''
        $fileDirLower = $fileDir.ToLower()

        $exclude = $false
        foreach ($excludedFolder in $normalizedExcludedFolders) {
            if ($fileDirLower -like "$excludedFolder*") {
                $exclude = $true
                break
            }
        }
        if (-not $exclude) {
            # Add file to current batch
            $batchFiles += $file

            # Process batch if the batch size is reached
            if ($batchFiles.Count -ge $batchSize) {
                $fileIndex++
                Write-Host "Processing batch $fileIndex of $totalBatches..."
                Process-Batch -Files $batchFiles -CsvPath $HashedCsvPath
                $batchFiles = @()  # Clear the batch
                [GC]::Collect()  # Force garbage collection
                [GC]::WaitForPendingFinalizers()  # Ensure all garbage is collected
            }
        }
    }

    # Process any remaining files
    if ($batchFiles.Count -gt 0) {
        $fileIndex++
        Write-Host "Processing batch $fileIndex of $totalBatches..."
        Process-Batch -Files $batchFiles -CsvPath $HashedCsvPath
        [GC]::Collect()  # Force garbage collection
        [GC]::WaitForPendingFinalizers()  # Ensure all garbage is collected
    }

    Write-Host "Hashing completed."

    # Find duplicates and save them
    Find-Duplicates -HashedCsvPath $HashedCsvPath -DuplicatesCsvPath $DuplicatesCsvPath
}

function Process-Batch {
    param (
        [Parameter(Mandatory)] [System.Collections.Generic.List[System.IO.FileInfo]] $Files,
        [String] $CsvPath
    )

    $totalFiles = $Files.Count
    $processedFiles = 0

    foreach ($file in $Files) {
        try {
            $filePath = $file.FullName

            # Ensure the file is accessible before hashing
            if (-not (Test-Path $filePath)) {
                continue
            }

            # Use certutil to compute the file hash with quoted file path
            $certutilCommand = "certutil -hashfile `"$filePath`" SHA1"
            
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

                # Write results to CSV dynamically
                "$hashKey,$filePath" | Out-File -FilePath $CsvPath -Append -Encoding UTF8
            }

        } catch {
            Write-Warning "Could not hash file: $filePath. Error: $_"
        }

        # Update progress output
        $processedFiles++
        Write-Progress -Activity "Computing hashes" -PercentComplete (($processedFiles / $totalFiles) * 100) -Status "Processing Files" -CurrentOperation "$processedFiles of $totalFiles files processed"
    }
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
