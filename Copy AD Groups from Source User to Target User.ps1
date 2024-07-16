
param (
    [string]$SourceUser = "samofthesourceuser",
    [string]$TargetUser= "samoftarget",
    [string]$ExclusionList= "HR*, IT*",
    [string]$InclusionList= "Finance - Japan"
)

# Function to convert comma-separated string to array
function ConvertTo-Array($inputString) {
    if ([string]::IsNullOrWhiteSpace($inputString)) {
        return @()
    }
    return $inputString -split ',' | ForEach-Object { $_.Trim() }
}

# Convert exclusion and inclusion lists to arrays
$exclusions = ConvertTo-Array $ExclusionList
$inclusions = ConvertTo-Array $InclusionList

# Initialize result object
$addedGroups = @()
$failedGroups = @()
$errors = @()

# Get the source user object
try {
    $sourceADUser = Get-ADUser $SourceUser -Properties MemberOf -ErrorAction Stop
} catch {
    $errors += "Error getting SourceUser '$SourceUser': $_"
    $sourceADUser = $null
}

# Get the target user object
try {
    $targetADUser = Get-ADUser $TargetUser -ErrorAction Stop
} catch {
    $errors += "Error getting TargetUser '$TargetUser': $_"
    $targetADUser = $null
}

if (-not $sourceADUser -or -not $targetADUser) {
    $result = @{
        SourceUser = $SourceUser
        TargetUser = $TargetUser
        AddedGroups = $addedGroups
        FailedGroups = $failedGroups
        Errors = $errors
    }
    return $result | ConvertTo-Json
}

# Get groups of the source user
try {
    $sourceGroups = $sourceADUser.MemberOf | ForEach-Object { 
        try {
            (Get-ADGroup $_).Name
        } catch {
            $errors += "Error getting group '$_' for SourceUser '$SourceUser': $_"
            $null
        }
    } | Where-Object { $_ -ne $null }
} catch {
    $errors += "Error getting groups for SourceUser '$SourceUser': $_"
    $sourceGroups = @()
}

# Initialize groups to copy
$groupsToCopy = @()

# Add groups from the source user that are not in the exclusion list
$groupsToCopy += $sourceGroups | Where-Object { 
    $excluded = $false
    foreach ($exclusion in $exclusions) {
        if ($_ -like $exclusion) {
            $excluded = $true
            break
        }
    }
    -not $excluded
}

# Add groups from the inclusion list, respecting exclusions
foreach ($inclusion in $inclusions) {
    if ($inclusion -match '\\*') {
        # If the inclusion contains a wildcard, find matching groups
        try {
            $matchingGroups = Get-ADGroup -Filter "Name -like '$inclusion'" | 
                              Select-Object -ExpandProperty Name |
                              Where-Object { 
                                  $excluded = $false
                                  foreach ($exclusion in $exclusions) {
                                      if ($_ -like $exclusion) {
                                          $excluded = $true
                                          break
                                      }
                                  }
                                  -not $excluded
                              }
            $groupsToCopy += $matchingGroups
        } catch {
            $errors += "Error finding matching groups for inclusion pattern '$inclusion': $_"
        }
    } else {
        # If no wildcard, add the group name if it's not excluded
        $excluded = $false
        foreach ($exclusion in $exclusions) {
            if ($inclusion -like $exclusion) {
                $excluded = $true
                break
            }
        }
        if (-not $excluded) {
            try {
                $groupExists = Get-ADGroup -Identity $inclusion -ErrorAction Stop
                $groupsToCopy += $inclusion
            } catch {
                $errors += "Group '$inclusion' specified in InclusionList does not exist: $_"
            }
        }
    }
}

# Remove duplicates
$groupsToCopy = $groupsToCopy | Select-Object -Unique

# Copy groups to the target user
$addedGroups = @()
$failedGroups = @()

foreach ($group in $groupsToCopy) {
    try {
        $adGroup = Get-ADGroup -Identity $group
        Add-ADGroupMember -Identity $adGroup.DistinguishedName -Members $targetADUser.DistinguishedName
        $addedGroups += $group
    } catch {
        $failedGroups += @{
            GroupName = $group
            ErrorMessage = $_.Exception.Message
        }
    }
}

# Prepare the result
$result = @{
    SourceUser = $SourceUser
    TargetUser = $TargetUser
    AddedGroups = $addedGroups
    FailedGroups = $failedGroups
    Errors = $errors
}

# Convert the result to JSON and return
return $result | ConvertTo-Json -Depth 3
