$INCLUDE_LIST = @(
    '.\lib\_Settings.ps1',
    '.\lib\Engine.ps1'
)
$DEPENDENCIES_LIST = @(
    '.\_EXDtoCSV_Weblate.ps1'
)
foreach ($file in $INCLUDE_LIST) {
    try {
        . $file
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        "$file was not found!"
        $error_var = $true
    }
}
foreach ($file in $DEPENDENCIES_LIST) {
    if (-not $(Test-Path $file)) {
        Write-Error "$file was not found!" -Category ObjectNotFound
        $error_var = $true
    }
}
if ($error_var) {
    "Make sure that Engine.ps1 and _Settings.ps1 are 'lib' folder"
    "and that _EXDtoCSV_Weblate.ps1 is in the same folder as this script."
    "Then restart the script."
    Pause
    break
}
if (-not $(Test-Path -Path .\config.cfg)) {
	Copy-Item -Path .\config_sample.cfg -Destination .\config.cfg -ErrorAction Stop
}


function Compare-Files {
    param (
        # First file
        [string] $File1,
        # Second file
        [string] $File2
    )

    if ( -not ( $(Test-Path $File1) -and $(Test-Path $File2) ) ) {
        return $false
    }

    $hash1 = $(Get-FileHash $File1).hash
    $hash2 = $(Get-FileHash $File2).hash
    return ($hash1 -eq $hash2)
}

function Update-Csv {
    ################################################################
    #.Synopsis
    # Perform an update of the given current CSV file to the
    # given new CSV file. This function edits current CSV and
    # outputs a list of changes in an ArrayList. Keep in mind
    # that we always expect new (source) CSV to exist so this
    # function expects a FileInfo object of the new CSV, not
    # a path!
    #.Parameter CurrentCsv
    # Path to the current CSV.
    #.Parameter NewCsv
    # FileInfo object of the new CSV. Do not confuse with path -
    # you get FileInfo object from Get-ChildItem command.
    ################################################################
    [CmdletBinding()] Param (
        [Parameter(Mandatory=$true)] [String] $CurrentCsvPath,
        [Parameter(Mandatory=$true)] [System.IO.FileInfo] $NewCsv,
        [Parameter(Mandatory=$true)] [String] $LanguageCode
    )

try {

    $changelog = [System.Collections.ArrayList]::new()
    $file_name = "\$sub_path\$base_name\$(Split-Path $CurrentCsvPath -Leaf)"

    if (Test-Path $CurrentCsvPath) {
        $CurrentCsv = Get-ChildItem -Path $CurrentCsvPath

        # Shortcut: If the files are the same then return
        if ( $(Get-FileHash $CurrentCsv -Algorithm SHA1).Hash -eq $(Get-FileHash $NewCsv -Algorithm SHA1).Hash ) {
            $changelog = @()
            "$file_name - No changes, left as is." | Tee-Object $log -Append | Write-Host
            Return ,$changelog
        }

        $curr_csv_rows = [System.Collections.ArrayList]@(Import-Csv -Path $CurrentCsv -Encoding UTF8)
        $new_csv_rows = @(Import-Csv -Path $NewCsv -Encoding UTF8)

		# Clean sublanguage of translations.
		#  OR
        # Add index to new target strings for components listed in $UPDATE_ADD_INDEX.
        # That way any changed or new strings will have index on them in the game.
		if ( $SUBLANGUAGES.$LanguageCode ) {
			foreach ( $row in $new_csv_rows ) {
				$row.target = ''
			}
		} elseif ($NewCsv.Directory.Name -in $UPDATE_ADD_INDEX -and $LanguageCode -notin $OFFICIAL_LANGUAGES) {
            foreach ($row in $new_csv_rows) {
                $index_hex = "{0:X}_" -f [uint32]$row.context
                if (!$row.target.StartsWith($index_hex)) {
                    $row.target = $index_hex + $row.target
                }
            }
        }

        # Comparison cases:
        # Case 1. Current and new strings exist, current index == new index
		#         - Compare source strings
		#         - If same - skip, else - record string update
        # Case 2. Current and new strings exist, current index > new index
		#         - Insert new string row into current strings table
        # Case 3. Current and new strings exist, current index < new index
		#         - Keep removing rows from current table until we reach new index
        # Case 4. Only new string exists
		#         - Add new string row to the end of current strings table
        # Case 5. Only current string exists (a.k.a. we reached the end of new table)
		#         - Keep removing rows from the end of current table
		#           until current and new tables have the same size
        # Reminder that for Weblate index is 'context'
		# The order of case checking: 4 > 2 > 3 > 1 > 5
        for ($row_count = 0; $row_count -lt $new_csv_rows.Count; $row_count++) {
            # Case 4 
            if ($row_count -ge $curr_csv_rows.Count) {
                $null = $curr_csv_rows.Add($new_csv_rows[$row_count])
                if ($LanguageCode -notin $OFFICIAL_LANGUAGES) {
                    $curr_csv_rows[-1].fuzzy = 'True'
                }
                if ($LanguageCode -eq 'en') {
                    $null = $changelog.Add(
                        [PSCustomObject]@{
                            'File Name' = $base_name
                            'Index' = $new_csv_rows[$row_count].context
                            'Weblate URL' = '[N/A]'
                            'Old Source' = '[N/A]'
                            'New Source' = $new_csv_rows[$row_count].source
                        }
                    )    
                } else {
                    $null = $changelog.Add(
                        [PSCustomObject]@{
                            'File Name' = $base_name
                            'Index' = $new_csv_rows[$row_count].context
                            'Weblate URL' = '[N/A]'
                            'Old Translation' = '[N/A]'
                            'New Translation' = $new_csv_rows[$row_count].target
                            'Old Source' = '[N/A]'
                            'New Source' = $new_csv_rows[$row_count].source
                        }
                    )
                }
                continue
            }

            $curr_index = [uint32] $curr_csv_rows[$row_count].context
            $new_index = [uint32] $new_csv_rows[$row_count].context

            # Case 2
            if ($curr_index -gt $new_index) {
                $null = $curr_csv_rows.Insert($row_count, $new_csv_rows[$row_count])
                if ($LanguageCode -notin $OFFICIAL_LANGUAGES) {
                    $curr_csv_rows[$row_count].fuzzy = 'True'
                }
                if ($LanguageCode -eq 'en') {
                    $null = $changelog.Add(
                        [PSCustomObject]@{
                            'File Name' = $base_name
                            'Index' = $new_csv_rows[$row_count].context
                            'Weblate URL' = '[N/A]'
                            'Old Source' = '[N/A]'
                            'New Source' = $new_csv_rows[$row_count].source
                        }
                    )
                } else {
                    $null = $changelog.Add(
                        [PSCustomObject]@{
                            'File Name' = $base_name
                            'Index' = $new_csv_rows[$row_count].context
                            'Weblate URL' = '[N/A]'
                            'Old Translation' = '[N/A]'
                            'New Translation' = $new_csv_rows[$row_count].target
                            'Old Source' = '[N/A]'
                            'New Source' = $new_csv_rows[$row_count].source
                        }
                    )
                }
                continue
            }
            # Case 3
            while ($curr_index -lt $new_index) {
                if ($LanguageCode -eq 'en') {
                    $null = $changelog.Add(
                        [PSCustomObject]@{
                            'File Name' = $base_name
                            'Index' = $curr_csv_rows[$row_count].context
                            'Weblate URL' = '[N/A]'
                            'Old Source' = $curr_csv_rows[$row_count].source
                            'New Source' = '[Removed]'
                        }
                    )
                } else {
                    $null = $changelog.Add(
                        [PSCustomObject]@{
                            'File Name' = $base_name
                            'Index' = $curr_csv_rows[$row_count].context
                            'Weblate URL' = '[N/A]'
                            'Old Translation' = $curr_csv_rows[$row_count].target
                            'New Translation' = '[Removed]'
                            'Old Source' = $curr_csv_rows[$row_count].source
                            'New Source' = '[Removed]'
                        }
                    )
                }
                $curr_csv_rows.RemoveAt($row_count)
				# In case we reached the end of current table
                if ($row_count -ge $curr_csv_rows.Count) {
					# Go through the same new string again to reach case 4
					$row_count--
                    break
                }
                $curr_index = [uint32]$curr_csv_rows[$row_count].context
            }
            # Case 1
            # This is the only case where we can safely reference the change on translation server
            if ($curr_csv_rows[$row_count].source -ne $new_csv_rows[$row_count].source) {
				$component = $CurrentCsv.FullName.Replace("$PROJECT_PATH\$CURRENT_DIR\csv\exd\", '') `
                    -replace '\\[^\\]*$' -replace '\\','-'
                $lang = $CurrentCsv.BaseName
                $query = $new_csv_rows[$row_count].context

				# Since a certain patch CompleteJournal is now auto-generated on SE's side,
				# which leads to all of the file's strings be moved, which in turn leads
				# to thousands of useless changes and slow API calls.
				if ($component -ne 'completejournal') {
					try {
						$reply = Invoke-RestMethod -Method Get -Headers $headers `
							-Uri "https://$base_uri/api/translations/ffxiv-translation/$component/$lang/units/?q=$query"
						$weblate_link = $reply.results[0].web_url
					}
					catch {
						$weblate_link = 'Не удалось получить ссылку'
					}
				} else {
					$weblate_link = ''
				}

                if ($LanguageCode -eq 'en') {
                    $null = $changelog.Add(
                        [PSCustomObject]@{
                            'File Name' = $base_name
                            'Index' = $new_csv_rows[$row_count].context
                            'Weblate URL' = $weblate_link
                            'Old Source' = $curr_csv_rows[$row_count].source
                            'New Source' = $new_csv_rows[$row_count].source
                        }
                    )
                } else {
                    $null = $changelog.Add(
                        [PSCustomObject]@{
                            'File Name' = $base_name
                            'Index' = $new_csv_rows[$row_count].context
                            'Weblate URL' = $weblate_link
                            'Old Translation' = $curr_csv_rows[$row_count].target
                            'New Translation' = $new_csv_rows[$row_count].target
                            'Old Source' = $curr_csv_rows[$row_count].source
                            'New Source' = $new_csv_rows[$row_count].source
                        }
                    )
                }
                $curr_csv_rows[$row_count] = $new_csv_rows[$row_count]
                if ($LanguageCode -notin $OFFICIAL_LANGUAGES) {
                    $curr_csv_rows[$row_count].fuzzy = 'True'
                }
            }
        }
        # Case 5
        while ($curr_csv_rows.Count -gt $new_csv_rows.Count) {
            if ($LanguageCode -eq 'en') {
                $null = $changelog.Add(
                    [PSCustomObject]@{
                        'File Name' = $base_name
                        'Index' = '[N/A]'
                        'Weblate URL' = '[N/A]'
                        'Old Source' = $curr_csv_rows[$row_count].source
                        'New Source' = '[Removed]'
                    }
                )
            } else {
                $null = $changelog.Add(
                    [PSCustomObject]@{
                        'File Name' = $base_name
                        'Index' = '[N/A]'
                        'Weblate URL' = '[N/A]'
                        'Old Translation' = $curr_csv_rows[$row_count].target
                        'New Translation' = '[Removed]'
                        'Old Source' = $curr_csv_rows[$row_count].source
                        'New Source' = '[Removed]'
                    }
                )
            }
            $curr_csv_rows.RemoveAt($curr_csv_rows.Count-1)
        }

        if ($changelog) {
            $curr_csv_rows | Export-Csv $CurrentCsv -NoTypeInformation -Encoding UTF8
			Remove-BomFromFile -Path $CurrentCsv
            "$file_name - Done. $($changelog.Count) lines changed." | Tee-Object $log -Append | Write-Host
        } else {
            $changelog = @()
            "$file_name - No changes, left as is." | Tee-Object $log -Append | Write-Host
        }
        # The weird comma is a workaround for PowerShell because
        # for some reason 'return' behaves differently, and if you
        # ask it to return an empty array, it will return $null instead.
        Return ,$changelog
    }
    $null = New-Item $current_csv_dir_path -ItemType Directory -ErrorAction Ignore
    $null = Copy-Item $NewCsv "$current_csv_dir_path\$($NewCsv.Name)"

    if ($LanguageCode -notin $OFFICIAL_LANGUAGES) {
		$curr_csv_rows = @(Import-Csv -Path $CurrentCsvPath -Encoding UTF8)
        foreach ($row in $curr_csv_rows) {
            $row.fuzzy = 'True'
        }
		$curr_csv_rows | Export-Csv $CurrentCsvPath -NoTypeInformation -Encoding UTF8
		Remove-BomFromFile -Path $CurrentCsvPath
    }

    if ($LanguageCode -eq 'en') {
        $null = $changelog.Add(
            [PSCustomObject]@{
                'File Name' = $base_name
                'Index' = '[N/A]'
                'Weblate URL' = '[N/A]'
                'Old Source' = '[N/A]'
                'New Source' = '[New file]'
            }
        )
    } else {
        $null = $changelog.Add(
            [PSCustomObject]@{
                'File Name' = $base_name
                'Index' = '[N/A]'
                'Weblate URL' = '[N/A]'
                'Old Translation' = '[N/A]'
                'New Translation' = '[New file]'
                'Old Source' = '[N/A]'
                'New Source' = '[New file]'
            }
        )
    }
    "$file_name - New file, copied as is." | Tee-Object $log -Append | Write-Host
    Return ,$changelog

}
catch {
    $_ | Tee-Object $log -Append | Write-Host
    Return ,@()
}

}


Add-Type -AssemblyName System.Web

$CONFIG = Get-Content -Path .\config.cfg | ConvertFrom-StringData
if ([int] $CONFIG.Verbose) {
	$VerbosePreference = "Continue"
} else {
	$VerbosePreference = "SilentlyContinue"
}
if (-not $CONFIG.WeblateToken) {
    "Weblate token was not found, there will be no links to the strings."
}
$headers = @{
    Authorization = "Bearer {0}" -f $CONFIG.WeblateToken
}
$base_uri = $CONFIG.WeblateURI


$PROJECT_PATH = $PWD
# $CURRENT_DIR name is set in _Settings.ps1
$OLD_DIR = 'old'
$NEW_DIR = 'new'

if (-not $(Test-Path "$PROJECT_PATH\$CURRENT_DIR\exd_source")) {
    "There's no 'exd_source' in 'current' folder, aborting."
}
if (-not $(Test-Path "$PROJECT_PATH\$CURRENT_DIR\exh_source")) {
    "There's no 'exh_source' in 'current' folder, aborting."
}

$new_exh_list = Get-ChildItem "$PROJECT_PATH\$NEW_DIR\*.exh" -Recurse
"Found {0} EXH files in 'new' folder." -f $new_exh_list.Count
$_answer = Read-Host "Initiate update? (Y/n)"
if ($_answer.ToLower() -eq 'n') { break }

$total_start_time = Get-Date
if (New-Item ".\logs" -ItemType Directory -ErrorAction SilentlyContinue) {
    Write-Verbose "Created folder .\logs"
}
$log = ".\logs\Update_{0:yyyy-MM-ddTHH-mm-ss}.log" -f $total_start_time


"Copying current CSV, source EXHs and EXDs to 'old\x.xx' folder..."
Copy-Item "$PROJECT_PATH\$CURRENT_DIR\csv\*"      "$PROJECT_PATH\$OLD_DIR\x.xx\csv\exd\" -Recurse -Force -Exclude ('README.md', '.git')
Copy-Item "$PROJECT_PATH\$CURRENT_DIR\exh_source" "$PROJECT_PATH\$OLD_DIR\x.xx\" -Recurse -Force
Copy-Item "$PROJECT_PATH\$CURRENT_DIR\exd_source" "$PROJECT_PATH\$OLD_DIR\x.xx\" -Recurse -Force
"Done."


$changelog_table = @{}
foreach ($lang in $OFFICIAL_LANGUAGES) {
    $changelog_table.$lang = [System.Collections.ArrayList]::new()
}

try {

foreach ($new_exh_file in $new_exh_list) {
    $sub_path = $new_exh_file.FullName.Replace("$PROJECT_PATH\$NEW_DIR\exh_source\", '').
		Replace("$PROJECT_PATH\$NEW_DIR\exd_source\", '') -replace "\\$($new_exh_file.Name)`$"
    $base_name = $new_exh_file.BaseName

    $current_csv_dir_path = "$PROJECT_PATH\$CURRENT_DIR\csv\$sub_path\$base_name"
    $current_exd_dir_path = "$PROJECT_PATH\$CURRENT_DIR\exd_source\$sub_path"
    $current_exh_dir_path = "$PROJECT_PATH\$CURRENT_DIR\exh_source\$sub_path"
    $new_csv_dir_path = "$PROJECT_PATH\$NEW_DIR\csv\$sub_path\$base_name"
    $new_exd_dir_path = "$PROJECT_PATH\$NEW_DIR\exd_source\$sub_path"
    $new_exh_dir_path = "$PROJECT_PATH\$NEW_DIR\exh_source\$sub_path"

    # Move .exh file to new\exh_source if it's in new\exd_source
    if ($new_exh_file.FullName -cmatch [regex]::Escape($new_exd_dir_path)) {
        $new_exh_path = "$new_exh_dir_path\$base_name.exh"

        if (New-Item $(Split-Path $new_exh_path) -ItemType Directory -Force) {
            Write-Verbose "$(Split-Path $new_exh_path) was created." *>&1 | Tee-Object $log -Append
        }
        Move-Item -Path $new_exh_file -Destination $new_exh_path -Force
        $new_exh_file = Get-ChildItem $new_exh_path

        Write-Verbose ("{0}.exh was moved to 'exh_source'" -f $base_name) *>&1 | Tee-Object $log -Append
    }

    $conversion_flags = @{}
    $remove_cache_flag_exh = $false

    $new_exd_list = Get-ChildItem "$new_exd_dir_path\$($base_name)_*.exd"
    $current_exh_path = "$current_exh_dir_path\$base_name.exh"

    # Comparison 1. Compare EXH
    # If EXH was changed then we must copy all new files and re-convert everything.
	if (Compare-Files $new_exh_file $current_exh_path) {
        "{0} - No changes" -f $new_exh_file.Name *>&1 | Tee-Object $log -Append
    } else {
		if (-not (Test-Path $current_exh_path) ) {
			New-Item $(Split-Path $current_exh_path) -ItemType Directory -ErrorAction SilentlyContinue -Force
			Copy-Item -Path $new_exh_file -Destination $current_exh_path -Force
			"\{0}\{1} - New EXH file" -f $sub_path, $new_exh_file.Name *>&1 | Tee-Object $log -Append
		} else {
			"\{0}\{1} - EXH changed" -f $sub_path, $new_exh_file.Name *>&1 | Tee-Object $log -Append
		}
		
		$current_exh_file = Get-ChildItem $current_exh_path
        Copy-Item -Path $new_exh_file -Destination $current_exh_file -Force

        foreach ($new_exd_file in $new_exd_list) {
            $current_exd_path = "$current_exd_dir_path\$($new_exd_file.Name)"
			New-Item $(Split-Path $current_exd_path) -ItemType Directory -ErrorAction SilentlyContinue -Force
            Copy-Item -Path $new_exd_file -Destination $current_exd_path -Force
        }

        $conversion_flags.en = $true
        $remove_cache_flag_exh = $true
    }

    # Comparison 2. Compare all EXDs
    # If EN EXD was changed then we must copy only EN EXD and re-convert everything,
    # since in CSVs EN is considered as a source language.
    # If any other EXD was changed then we must copy this EXD and re-convert only this
    # language.
    if ($conversion_flags.Count -eq 0) {
        foreach ($new_exd_file in $new_exd_list) {
            $current_exd_file = Get-ChildItem "$current_exd_dir_path\$($new_exd_file.Name)"

            if (Compare-Files $new_exd_file $current_exd_file) {
                "\{0}\{1} - No changes" -f $sub_path, $new_exd_file.Name *>&1 | Tee-Object $log -Append
            } else {
                $null = $new_exd_file -match '_([A-Za-z]+)\.exd$'
                $lang = $Matches[1]

                Copy-Item -Path $new_exd_file -Destination $current_exd_file -Force
                $conversion_flags.$lang = $true
                "\{0}\{1} - {2} changed" -f $sub_path, $new_exd_file.Name, $lang.ToUpper() *>&1 | Tee-Object $log -Append
            }
        }
    }

    # Convert new EXDs and compare CSVs
    if ($conversion_flags.Count -gt 0) {
        .\_EXDtoCSV_Weblate.ps1 $new_exh_file.FullName -CurrentDir 'new' *>&1 | Tee-Object $log -Append

        $new_csv_list = Get-ChildItem "$new_csv_dir_path\*.csv"

        foreach ($new_csv in $new_csv_list) {
            $lang = $new_csv.BaseName
            $current_csv = "$current_csv_dir_path\$lang.csv"
            $changelog_table.$lang.InsertRange(
                $changelog_table.$lang.Count,
                $(Update-Csv -CurrentCsvPath $current_csv -NewCsv $new_csv -LanguageCode $lang)
            )
        }

        $current_csv_list = Get-ChildItem "$current_csv_dir_path\*.csv"
        $new_en_csv = Get-ChildItem "$new_csv_dir_path\en.csv"

        if ($current_csv_list.Count -gt $new_csv_list.Count) {
            foreach ($current_csv in $current_csv_list) {
                $lang = $current_csv.BaseName

                if ($lang -notin $OFFICIAL_LANGUAGES) {
                    if (-not $changelog_table.ContainsKey($lang)) {
                        $changelog_table.$lang = [System.Collections.ArrayList]::new()
                    }

                    $changelog_size_before = $changelog_table.$lang.Count

                    $changelog_table.$lang.InsertRange(
                        $changelog_table.$lang.Count,
                        $(Update-Csv -CurrentCsvPath $current_csv -NewCsv $new_en_csv -LanguageCode $lang)
                    )

					$remove_cache_flag_lang = $false
                    if ( $changelog_size_before -eq $changelog_table.$lang.Count ) {
                        $remove_cache_flag_lang = $true
                    }

					$csv_cache_path = "$PROJECT_PATH\$CURRENT_DIR\exd_mod_$lang\csv_cache\$sub_path\$($base_name)_cache.csv"
					if ( Test-Path $csv_cache_path ) {
						if ( $remove_cache_flag_exh ) {
							$reason = 'EXH changed'
						}
						if ( $remove_cache_flag_lang ) {
							$reason = 'EN changed w/o changing strings'
							$remove_cache_flag_lang = $false
						}
						Write-Warning "$($base_name): $reason - deleting CSV cache at`n  $csv_cache_path" *>&1 | Tee-Object $log -Append
						Remove-Item -Path $csv_cache_path
					}
                }
            }
        }
    }
}

}
catch {
    $_ *>&1 | Tee-Object $log -Append
}

foreach ($lang in $changelog_table.Keys) {
    if ($changelog_table[$lang].Count) {
        New-Item -Path "$PROJECT_PATH\changelogs" -ItemType Directory -Force -ErrorAction Ignore
        $changelog_table[$lang] | Export-Csv "$PROJECT_PATH\changelogs\x.xx-x.xx Changes $lang.csv" -NoTypeInformation -Encoding UTF8
    }
}

$time_diff = $($(Get-Date) - $total_start_time)
Write-Host ("Done in {0:hh}:{0:mm}:{0:ss}.{0:fff}`n" -f $time_diff) -ForegroundColor Green *>&1 | Tee-Object $log -Append
Pause
