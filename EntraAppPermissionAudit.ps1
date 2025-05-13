<#
.SYNOPSIS
    Comprehensive Entra Registered Applications Audit Script via MS Graph API
.DESCRIPTION
    This script audits all Entra registered applications and their associated service principals.
    It extracts all permissions (delegated and application) and generates a detailed CSV report
    with identification of high-risk/privileged permissions.
.NOTES
    Requirements: Microsoft.Graph PowerShell module
    Version: 1.0
#>

# Requires -Modules Microsoft.Graph.Applications, Microsoft.Graph.Authentication

# Script configuration
$OutputFolder = ".\EntraAuditReports"
$Timestamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
$OutputFile = "$OutputFolder\$Timestamp-EntraAppPermissionsAudit.csv"
$LogFile = "$OutputFolder\$Timestamp-AuditLog.txt"

# List of industry-standard privileged/high-risk permissions
# This list can be customized based on organizational requirements
$PrivilegedAppPermissions = @(
    # Directory permissions
    'Directory.Read.All',
    'Directory.ReadWrite.All',
    'Directory.AccessAsUser.All',
    
    # User permissions
    'User.Read.All',
    'User.ReadWrite.All',
    'User.ManageIdentities.All',
    
    # Group permissions
    'Group.Read.All',
    'Group.ReadWrite.All',
    
    # Application permissions
    'Application.Read.All',
    'Application.ReadWrite.All',
    'Application.ReadWrite.OwnedBy',
    
    # Mail permissions
    'Mail.Read',
    'Mail.ReadWrite',
    'Mail.Read.All',
    'Mail.ReadWrite.All',
    'Mail.Send',
    'Mail.Send.All',
    
    # Files permissions
    'Files.Read.All',
    'Files.ReadWrite.All',
    
    # Sites permissions
    'Sites.Read.All',
    'Sites.ReadWrite.All',
    'Sites.FullControl.All',
    
    # Device permissions
    'Device.Read.All',
    'Device.ReadWrite.All',
    
    # Role management permissions
    'RoleManagement.Read.All',
    'RoleManagement.ReadWrite.Directory'
)

# Custom client-specific privileged permissions
# This array can be populated with additional permissions specific to the client
$CustomPrivilegedPermissions = @(
    # Add client-specific permissions here
    # Example: 'CustomApp.ReadWrite.All'
    'Directory.ReadWrite.All', 
    'User.ReadWrite.All', 
    'Mail.ReadWrite', 
    'Files.ReadWrite.All', 
    'Group.ReadWrite.All', 
    'Application.ReadWrite.All',
    'Application.ReadWrite.OwnedBy', 
    'Sites.FullControl.All'
)

# Combine standard and custom privileged permissions
$AllPrivilegedPermissions = $PrivilegedPermissions + $CustomPrivilegedPermissions

# Function to write to log file
function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )
    
    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    # Write to console with appropriate color
    switch ($Level) {
        'Info' { Write-Host $LogEntry -ForegroundColor Cyan }
        'Warning' { Write-Host $LogEntry -ForegroundColor Yellow }
        'Error' { Write-Host $LogEntry -ForegroundColor Red }
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $LogEntry
}

# Function to handle errors
function Handle-Error {
    param (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        
        [Parameter(Mandatory = $true)]
        [string]$Operation,
        
        [Parameter(Mandatory = $false)]
        [bool]$TerminateScript = $false
    )
    
    $ErrorMessage = "Error during $Operation. Details: $($ErrorRecord.Exception.Message)"
    Write-Log -Message $ErrorMessage -Level 'Error'
    
    if ($TerminateScript) {
        Write-Log -Message "Script execution terminated due to critical error." -Level 'Error'
        exit 1
    }
}

# Function to ensure output directory exists
function Ensure-OutputDirectory {
    if (-not (Test-Path -Path $OutputFolder)) {
        try {
            New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
            Write-Log -Message "Created output directory: $OutputFolder" -Level 'Info'
        }
        catch {
            Handle-Error -ErrorRecord $_ -Operation "creating output directory" -TerminateScript $true
        }
    }
}

# Function to connect to Microsoft Graph with appropriate permissions
function Connect-ToMicrosoftGraph {
    try {
        # Check if already connected
        $graphConnection = Get-MgContext
        if ($null -eq $graphConnection) {
            Write-Log -Message "Connecting to Microsoft Graph..." -Level 'Info'
            
            # Required permissions for this script
            $requiredScopes = @(
                'Application.Read.All',
                'Directory.Read.All',
                'AppRoleAssignment.ReadWrite.All'
            )
            
            Connect-MgGraph -Scopes $requiredScopes
            
            # Verify connection
            $graphConnection = Get-MgContext
            if ($null -eq $graphConnection) {
                throw "Failed to connect to Microsoft Graph."
            }
            
            Write-Log -Message "Successfully connected to Microsoft Graph as $($graphConnection.Account)" -Level 'Info'
        }
        else {
            Write-Log -Message "Already connected to Microsoft Graph as $($graphConnection.Account)" -Level 'Info'
        }
    }
    catch {
        Handle-Error -ErrorRecord $_ -Operation "connecting to Microsoft Graph" -TerminateScript $true
    }
}

# Function to get Microsoft Graph service principal
function Get-MicrosoftGraphServicePrincipal {
    try {
        Write-Log -Message "Retrieving Microsoft Graph service principal..." -Level 'Info'
        
        # Microsoft Graph App ID is a well-known GUID
        $graphAppId = '00000003-0000-0000-c000-000000000000'
        $graphSP = Get-MgServicePrincipal -Filter "appId eq '$graphAppId'"
        
        if ($null -eq $graphSP) {
            throw "Microsoft Graph service principal not found."
        }
        
        Write-Log -Message "Successfully retrieved Microsoft Graph service principal." -Level 'Info'
        return $graphSP
    }
    catch {
        Handle-Error -ErrorRecord $_ -Operation "retrieving Microsoft Graph service principal" -TerminateScript $true
    }
}

# Function to get all registered applications
function Get-AllRegisteredApplications {
    try {
        Write-Log -Message "Retrieving all registered applications..." -Level 'Info'
        
        # Get all applications with pagination to handle large tenants
        $allApps = @()
        $pageSize = 999  # Maximum page size
        $params = @{
            All = $true
            PageSize = $pageSize
        }
        
        $allApps = Get-MgApplication @params
        
        $appCount = $allApps.Count
        Write-Log -Message "Retrieved $appCount registered applications." -Level 'Info'
        
        return $allApps
    }
    catch {
        Handle-Error -ErrorRecord $_ -Operation "retrieving registered applications" -TerminateScript $true
    }
}

# Function to get all service principals
function Get-AllServicePrincipals {
    try {
        Write-Log -Message "Retrieving all service principals..." -Level 'Info'
        
        # Get all service principals with pagination to handle large tenants
        $allSPs = @()
        $pageSize = 999  # Maximum page size
        $params = @{
            All = $true
            PageSize = $pageSize
        }
        
        $allSPs = Get-MgServicePrincipal @params
        
        $spCount = $allSPs.Count
        Write-Log -Message "Retrieved $spCount service principals." -Level 'Info'
        
        return $allSPs
    }
    catch {
        Handle-Error -ErrorRecord $_ -Operation "retrieving service principals" -TerminateScript $true
    }
}

# Function to get application permissions (AppRoles)
function Get-ApplicationPermissions {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalId,
        
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphServicePrincipal]$GraphServicePrincipal
    )
    
    try {
        # Get all app role assignments for the service principal
        $appRoleAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ServicePrincipalId -All
        
        $permissions = @()
        
        foreach ($assignment in $appRoleAssignments) {
            # Get the resource service principal
            $resourceSP = $null
            if ($assignment.ResourceId -eq $GraphServicePrincipal.Id) {
                $resourceSP = $GraphServicePrincipal
            }
            else {
                try {
                    $resourceSP = Get-MgServicePrincipal -ServicePrincipalId $assignment.ResourceId -ErrorAction Stop
                }
                catch {
                    Write-Log -Message "Could not retrieve resource SP for ID: $($assignment.ResourceId). Error: $($_.Exception.Message)" -Level 'Warning'
                    continue
                }
            }
            
            # Find the app role in the resource service principal
            $appRole = $resourceSP.AppRoles | Where-Object { $_.Id -eq $assignment.AppRoleId }
            
            if ($null -ne $appRole) {
                $isPrivileged = $AllPrivilegedPermissions -contains $appRole.Value
                $isCustomPrivileged = $CustomPrivilegedPermissions -contains $appRole.Value
                
                $permissionInfo = [PSCustomObject]@{
                    PermissionType = 'Application'
                    ResourceDisplayName = $resourceSP.DisplayName
                    ResourceId = $resourceSP.Id
                    ResourceAppId = $resourceSP.AppId
                    PermissionId = $appRole.Id
                    PermissionName = $appRole.Value
                    PermissionDisplayName = $appRole.DisplayName
                    PermissionDescription = $appRole.Description
                    IsGranted = $true  # App role assignments are always granted
                    IsPrivileged = $isPrivileged
                    IsCustomPrivileged = $isCustomPrivileged
                }
                
                $permissions += $permissionInfo
            }
        }
        
        return $permissions
    }
    catch {
        Handle-Error -ErrorRecord $_ -Operation "retrieving application permissions for SP: $ServicePrincipalId"
        return @()
    }
}

# Function to get delegated permissions (OAuth2PermissionGrants)
function Get-DelegatedPermissions {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ServicePrincipalId,
        
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphServicePrincipal]$GraphServicePrincipal
    )
    
    try {
        # Get all OAuth2 permission grants for the service principal
        $oauth2PermissionGrants = Get-MgOauth2PermissionGrant -Filter "clientId eq '$ServicePrincipalId'" -All
        
        $permissions = @()
        
        foreach ($grant in $oauth2PermissionGrants) {
            # Get the resource service principal
            $resourceSP = $null
            if ($grant.ResourceId -eq $GraphServicePrincipal.Id) {
                $resourceSP = $GraphServicePrincipal
            }
            else {
                try {
                    $resourceSP = Get-MgServicePrincipal -ServicePrincipalId $grant.ResourceId -ErrorAction Stop
                }
                catch {
                    Write-Log -Message "Could not retrieve resource SP for ID: $($grant.ResourceId). Error: $($_.Exception.Message)" -Level 'Warning'
                    continue
                }
            }
            
            # Process each scope in the grant
            $scopes = $grant.Scope -split ' '
            
            foreach ($scope in $scopes) {
                # Find the permission in the resource service principal
                $permission = $resourceSP.OAuth2PermissionScopes | Where-Object { $_.Value -eq $scope }
                
                if ($null -ne $permission) {
                    $isPrivileged = $AllPrivilegedPermissions -contains $scope
                    $isCustomPrivileged = $CustomPrivilegedPermissions -contains $scope
                    
                    $permissionInfo = [PSCustomObject]@{
                        PermissionType = 'Delegated'
                        ResourceDisplayName = $resourceSP.DisplayName
                        ResourceId = $resourceSP.Id
                        ResourceAppId = $resourceSP.AppId
                        PermissionId = $permission.Id
                        PermissionName = $permission.Value
                        PermissionDisplayName = $permission.AdminConsentDisplayName
                        PermissionDescription = $permission.AdminConsentDescription
                        IsGranted = $true  # OAuth2 permission grants are always granted
                        IsPrivileged = $isPrivileged
                        IsCustomPrivileged = $isCustomPrivileged
                        ConsentType = $grant.ConsentType
                        PrincipalId = $grant.PrincipalId  # User who granted consent (for user consent)
                    }
                    
                    $permissions += $permissionInfo
                }
            }
        }
        
        return $permissions
    }
    catch {
        Handle-Error -ErrorRecord $_ -Operation "retrieving delegated permissions for SP: $ServicePrincipalId"
        return @()
    }
}

# Function to get requested (but not necessarily granted) permissions
function Get-RequestedPermissions {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphApplication]$Application,
        
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphServicePrincipal]$ServicePrincipal,
        
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphServicePrincipal]$GraphServicePrincipal,
        
        [Parameter(Mandatory = $false)]
        [array]$GrantedAppPermissions = @(),
        
        [Parameter(Mandatory = $false)]
        [array]$GrantedDelegatedPermissions = @()
    )
    
    try {
        $requestedPermissions = @()
        
        # Get requested application permissions (RequiredResourceAccess)
        foreach ($resource in $Application.RequiredResourceAccess) {
            # Get the resource service principal
            $resourceSP = $null
            if ($resource.ResourceAppId -eq $GraphServicePrincipal.AppId) {
                $resourceSP = $GraphServicePrincipal
            }
            else {
                try {
                    $resourceSP = Get-MgServicePrincipal -Filter "appId eq '$($resource.ResourceAppId)'" -ErrorAction Stop
                }
                catch {
                    Write-Log -Message "Could not retrieve resource SP for AppID: $($resource.ResourceAppId). Error: $($_.Exception.Message)" -Level 'Warning'
                    continue
                }
            }
            
            if ($null -eq $resourceSP) {
                continue
            }
            
            # Process each resource access
            foreach ($access in $resource.ResourceAccess) {
                $permissionInfo = $null
                
                # Application permission
                if ($access.Type -eq "Role") {
                    $appRole = $resourceSP.AppRoles | Where-Object { $_.Id -eq $access.Id }
                    
                    if ($null -ne $appRole) {
                        # Check if this permission is already granted
                        $isGranted = $GrantedAppPermissions | Where-Object { 
                            $_.ResourceAppId -eq $resourceSP.AppId -and 
                            $_.PermissionId -eq $access.Id 
                        }
                        
                        $isPrivileged = $AllPrivilegedPermissions -contains $appRole.Value
                        $isCustomPrivileged = $CustomPrivilegedPermissions -contains $appRole.Value
                        
                        $permissionInfo = [PSCustomObject]@{
                            PermissionType = 'Application'
                            ResourceDisplayName = $resourceSP.DisplayName
                            ResourceId = $resourceSP.Id
                            ResourceAppId = $resourceSP.AppId
                            PermissionId = $appRole.Id
                            PermissionName = $appRole.Value
                            PermissionDisplayName = $appRole.DisplayName
                            PermissionDescription = $appRole.Description
                            IsGranted = ($null -ne $isGranted)
                            IsPrivileged = $isPrivileged
                            IsCustomPrivileged = $isCustomPrivileged
                        }
                    }
                }
                # Delegated permission
                elseif ($access.Type -eq "Scope") {
                    $permission = $resourceSP.OAuth2PermissionScopes | Where-Object { $_.Id -eq $access.Id }
                    
                    if ($null -ne $permission) {
                        # Check if this permission is already granted
                        $isGranted = $GrantedDelegatedPermissions | Where-Object { 
                            $_.ResourceAppId -eq $resourceSP.AppId -and 
                            $_.PermissionName -eq $permission.Value 
                        }
                        
                        $isPrivileged = $AllPrivilegedPermissions -contains $permission.Value
                        $isCustomPrivileged = $CustomPrivilegedPermissions -contains $permission.Value
                        
                        $permissionInfo = [PSCustomObject]@{
                            PermissionType = 'Delegated'
                            ResourceDisplayName = $resourceSP.DisplayName
                            ResourceId = $resourceSP.Id
                            ResourceAppId = $resourceSP.AppId
                            PermissionId = $permission.Id
                            PermissionName = $permission.Value
                            PermissionDisplayName = $permission.AdminConsentDisplayName
                            PermissionDescription = $permission.AdminConsentDescription
                            IsGranted = ($null -ne $isGranted)
                            IsPrivileged = $isPrivileged
                            IsCustomPrivileged = $isCustomPrivileged
                        }
                    }
                }
                
                if ($null -ne $permissionInfo) {
                    $requestedPermissions += $permissionInfo
                }
            }
        }
        
        return $requestedPermissions
    }
    catch {
        Handle-Error -ErrorRecord $_ -Operation "retrieving requested permissions for app: $($Application.DisplayName)"
        return @()
    }
}

# Function to get application owners
function Get-ApplicationOwners {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ApplicationId
    )
    
    try {
        $owners = Get-MgApplicationOwner -ApplicationId $ApplicationId -All
        
        $ownerDetails = @()
        foreach ($owner in $owners) {
            $ownerInfo = $null
            
            # Owner can be a user or a service principal
            if ($owner.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.user') {
                try {
                    $user = Get-MgUser -UserId $owner.Id -ErrorAction Stop
                    $ownerInfo = [PSCustomObject]@{
                        Type = 'User'
                        Id = $user.Id
                        DisplayName = $user.DisplayName
                        UserPrincipalName = $user.UserPrincipalName
                    }
                }
                catch {
                    Write-Log -Message "Could not retrieve user owner for ID: $($owner.Id). Error: $($_.Exception.Message)" -Level 'Warning'
                }
            }
            elseif ($owner.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.servicePrincipal') {
                try {
                    $sp = Get-MgServicePrincipal -ServicePrincipalId $owner.Id -ErrorAction Stop
                    $ownerInfo = [PSCustomObject]@{
                        Type = 'ServicePrincipal'
                        Id = $sp.Id
                        DisplayName = $sp.DisplayName
                        AppId = $sp.AppId
                    }
                }
                catch {
                    Write-Log -Message "Could not retrieve service principal owner for ID: $($owner.Id). Error: $($_.Exception.Message)" -Level 'Warning'
                }
            }
            
            if ($null -ne $ownerInfo) {
                $ownerDetails += $ownerInfo
            }
        }
        
        return $ownerDetails
    }
    catch {
        Handle-Error -ErrorRecord $_ -Operation "retrieving owners for application: $ApplicationId"
        return @()
    }
}

# Function to generate the audit report
function Generate-AuditReport {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Applications,
        
        [Parameter(Mandatory = $true)]
        [array]$ServicePrincipals,
        
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.IMicrosoftGraphServicePrincipal]$GraphServicePrincipal
    )
    
    try {
        Write-Log -Message "Generating audit report..." -Level 'Info'
        
        $reportData = @()
        $appCounter = 0
        $totalApps = $Applications.Count
        
        foreach ($app in $Applications) {
            $appCounter++
            $progressPercentage = [math]::Round(($appCounter / $totalApps) * 100, 2)
            Write-Progress -Activity "Auditing Applications" -Status "Processing $appCounter of $totalApps ($progressPercentage%)" -PercentComplete $progressPercentage -CurrentOperation "App: $($app.DisplayName)"
            
            Write-Log -Message "Processing application ${appCounter} of ${totalApps}: $($app.DisplayName) (AppId: $($app.AppId))" -Level 'Info'
            
            # Find the corresponding service principal
            $sp = $ServicePrincipals | Where-Object { $_.AppId -eq $app.AppId }
            
            if ($null -eq $sp) {
                Write-Log -Message "No service principal found for application: $($app.DisplayName) (AppId: $($app.AppId))" -Level 'Warning'
                continue
            }
            
            # Get application owners
            $owners = Get-ApplicationOwners -ApplicationId $app.Id
            $ownerString = ($owners | ForEach-Object { 
                if ($_.Type -eq 'User') {
                    "$($_.DisplayName) ($($_.UserPrincipalName))"
                }
                else {
                    "$($_.DisplayName) (SP: $($_.AppId))"
                }
            }) -join '; '
            
            # Get granted permissions
            $appPermissions = Get-ApplicationPermissions -ServicePrincipalId $sp.Id -GraphServicePrincipal $GraphServicePrincipal
            if ($null -eq $appPermissions) { $appPermissions = @() }
            $delegatedPermissions = Get-DelegatedPermissions -ServicePrincipalId $sp.Id -GraphServicePrincipal $GraphServicePrincipal
            if ($null -eq $delegatedPermissions) { $delegatedPermissions = @() }
            
            # Get requested permissions (including those not granted)
            $allPermissions = Get-RequestedPermissions -Application $app -ServicePrincipal $sp -GraphServicePrincipal $GraphServicePrincipal -GrantedAppPermissions $appPermissions -GrantedDelegatedPermissions $delegatedPermissions
            
            # If no permissions found, add a placeholder entry
            if ($allPermissions.Count -eq 0) {
                $reportEntry = [PSCustomObject]@{
                    ApplicationDisplayName = $app.DisplayName
                    ApplicationId = $app.AppId
                    ApplicationObjectId = $app.Id
                    ServicePrincipalId = $sp.Id
                    ServicePrincipalDisplayName = $sp.DisplayName
                    CreatedDateTime = $app.CreatedDateTime
                    Owners = $ownerString
                    PermissionType = "None"
                    ResourceDisplayName = "N/A"
                    PermissionName = "No permissions found"
                    PermissionDisplayName = "No permissions found"
                    IsGranted = "N/A"
                    IsPrivileged = "N/A"
                    IsCustomPrivileged = "N/A"
                }
                
                $reportData += $reportEntry
            }
            else {
                # Add each permission as a separate row in the report
                foreach ($permission in $allPermissions) {
                    $reportEntry = [PSCustomObject]@{
                        ApplicationDisplayName = $app.DisplayName
                        ApplicationId = $app.AppId
                        ApplicationObjectId = $app.Id
                        ServicePrincipalId = $sp.Id
                        ServicePrincipalDisplayName = $sp.DisplayName
                        CreatedDateTime = $app.CreatedDateTime
                        Owners = $ownerString
                        PermissionType = $permission.PermissionType
                        ResourceDisplayName = $permission.ResourceDisplayName
                        ResourceId = $permission.ResourceAppId
                        PermissionName = $permission.PermissionName
                        PermissionDisplayName = $permission.PermissionDisplayName
                        PermissionDescription = $permission.PermissionDescription
                        IsGranted = $permission.IsGranted
                        IsPrivileged = $permission.IsPrivileged
                        IsCustomPrivileged = $permission.IsCustomPrivileged
                    }
                    
                    $reportData += $reportEntry
                }
            }
        }
        
        Write-Progress -Activity "Auditing Applications" -Completed
        
        # Export the report to CSV
        $reportData | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
        
        Write-Log -Message "Audit report generated successfully: $OutputFile" -Level 'Info'
        
        # Generate summary statistics
        $totalAppsWithPermissions = ($reportData | Select-Object ApplicationId -Unique).Count
        $totalPermissions = $reportData.Count
        $totalPrivilegedPermissions = ($reportData | Where-Object { $_.IsPrivileged -eq $true }).Count
        $totalCustomPrivilegedPermissions = ($reportData | Where-Object { $_.IsCustomPrivileged -eq $true }).Count
        $totalUngrantedPermissions = ($reportData | Where-Object { $_.IsGranted -eq $false }).Count
        
        $summaryReport = @"
Entra Application Permission Audit Summary
=========================================
Total Applications: $totalAppsWithPermissions
Total Permissions: $totalPermissions
Total Privileged Permissions: $totalPrivilegedPermissions
Total Custom Privileged Permissions: $totalCustomPrivilegedPermissions
Total Ungrated Permissions: $totalUngrantedPermissions
Report Location: $OutputFile
"@
        
        Write-Host "`n$summaryReport" -ForegroundColor Green
        Add-Content -Path $LogFile -Value "`n$summaryReport"
        
        return $reportData
    }
    catch {
        Handle-Error -ErrorRecord $_ -Operation "generating audit report" -TerminateScript $true
    }
}

# Main script execution
try {
    # Display script banner
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host "  Entra Registered Applications Permission Audit Tool  " -ForegroundColor Cyan
    Write-Host "=======================================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Ensure output directory exists
    Ensure-OutputDirectory
    
    # Start logging
    Write-Log -Message "Script execution started" -Level 'Info'
    
    # Connect to Microsoft Graph
    Connect-ToMicrosoftGraph
    
    # Get Microsoft Graph service principal
    $graphSP = Get-MicrosoftGraphServicePrincipal
    
    # Get all registered applications
    $allApps = Get-AllRegisteredApplications
    
    # Get all service principals
    $allSPs = Get-AllServicePrincipals
    
    # Generate the audit report
    $reportData = Generate-AuditReport -Applications $allApps -ServicePrincipals $allSPs -GraphServicePrincipal $graphSP
    
    # Script completed successfully
    Write-Log -Message "Script execution completed successfully" -Level 'Info'
    
    # Return the path to the generated report
    return $OutputFile
}
catch {
    Handle-Error -ErrorRecord $_ -Operation "script execution" -TerminateScript $true
}
