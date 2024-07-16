param ([string]$folderPath, [string]$accessRight, [string]$user)

# Define the function to update public folder permissions
function Update-FolderPermissions {
    param (
        [string]$Folder,
        [string]$AccessRights,
        [string]$Users,
        [bool]$Recursive
    )

    $ErrorActionPreference = "Stop"

    try {
        # Convert the comma-separated users string into an array
        $UsersArray = $Users -split ','

        # Define a helper function to set permissions on a folder
        function Set-Permissions {
            param (
                [string]$FolderPath
            )

            foreach ($user in $UsersArray) {
                Add-PublicFolderClientPermission -Identity $FolderPath -User $user -AccessRights $AccessRights -ErrorAction Stop
            }
        }

        # Set permissions on the specified folder
        Set-Permissions -FolderPath $Folder

        # Recursively apply permissions if specified
        if ($Recursive) {
            # Get all subfolders recursively
            $subfolders = Get-PublicFolder -Recurse -ResultSize Unlimited | Where-Object { $_.Identity -like "$Folder\*" }
            foreach ($subfolder in $subfolders) {
                Set-Permissions -FolderPath $subfolder.Identity
            }
        }

        Write-Output "Permissions updated successfully."

    } catch {
        Write-Error "Error updating folder permissions: $($_.Exception.Message)"
    }
}

# Call the function with the provided parameters
Update-FolderPermissions -Folder $folderPath -AccessRights $accessRight -Users $user -Recursive $true
