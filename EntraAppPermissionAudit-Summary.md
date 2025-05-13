# Entra Application Permission Audit - Implementation Summary

## Overview

The `EntraAppPermissionAudit.ps1` script provides a comprehensive solution for auditing Entra (formerly Azure AD) registered applications and their associated permissions via the Microsoft Graph API. This document explains how the implementation meets all the requirements specified in the task.

## Requirements Fulfilled

### 1. Extract all Entra registered applications with their associated service principals

The script retrieves all registered applications and their corresponding service principals using:
- `Get-AllRegisteredApplications` function - Gets all registered applications with pagination support
- `Get-AllServicePrincipals` function - Gets all service principals with pagination support
- The script then matches applications with their service principals based on the AppId

### 2. Generate a detailed CSV report containing required information

The CSV report includes all the requested information:

#### Application and Service Principal Details
- Application display name, ID, and object ID
- Service principal ID and display name
- Application creation date
- Application owners (retrieved using `Get-ApplicationOwners` function)

#### Permission Details
- All delegated permissions (retrieved using `Get-DelegatedPermissions` function)
- All application permissions (retrieved using `Get-ApplicationPermissions` function)
- Requested but not granted permissions (retrieved using `Get-RequestedPermissions` function)

#### Permission Classification
- Clear identification of industry-standard privileged/high-risk permissions
  - Implemented via the `$PrivilegedAppPermissions` array which contains a comprehensive list of high-risk permissions
- Custom flagging mechanism for client-specific privileged permissions
  - Implemented via the `$CustomPrivilegedPermissions` array which can be customized for client-specific needs
- Permission status (granted/not granted)
  - Each permission is marked with `IsGranted` property
- Permission type (delegated/application)
  - Each permission is marked with `PermissionType` property

### 3. Authentication, Error Management, and Performance Optimization

#### Authentication Handling
- The script uses the Microsoft Graph PowerShell SDK for authentication
- It requests the minimum required permissions for the audit
- It verifies the connection before proceeding

#### Error Management
- Comprehensive error handling with the `Handle-Error` function
- Detailed logging with the `Write-Log` function
- All operations are wrapped in try-catch blocks
- Non-critical errors are logged but don't terminate the script

#### Performance Optimization
- Pagination is used for retrieving large sets of data
- The Microsoft Graph service principal is cached to avoid repeated API calls
- Progress indicators show completion percentage for long-running operations
- The script is designed to handle large tenants efficiently

## Implementation Details

### Key Functions

1. **Connect-ToMicrosoftGraph**
   - Handles authentication to Microsoft Graph with appropriate scopes

2. **Get-MicrosoftGraphServicePrincipal**
   - Retrieves and caches the Microsoft Graph service principal

3. **Get-ApplicationPermissions & Get-DelegatedPermissions**
   - Extract granted permissions of both types

4. **Get-RequestedPermissions**
   - Identifies permissions that are requested but not granted

5. **Get-ApplicationOwners**
   - Retrieves owner information for each application

6. **Generate-AuditReport**
   - Combines all data into a comprehensive report
   - Exports to CSV and provides summary statistics

### Logging and Error Handling

- All operations are logged to a timestamped log file
- Different log levels (Info, Warning, Error) with color-coding
- Detailed error messages with context about the operation that failed

### Customization Options

- The script allows customization of what constitutes a "privileged" permission
- Both standard industry-recognized privileged permissions and custom client-specific permissions can be defined

## Improvements Over Original Script

The original `query-graph-api.ps1` script was focused only on privileged permissions to Microsoft Graph. The new script:

1. Audits ALL applications, not just those with privileged permissions
2. Examines ALL permissions, not just Microsoft Graph permissions
3. Includes both granted AND requested-but-not-granted permissions
4. Provides more detailed information about each permission
5. Includes comprehensive error handling and logging
6. Is optimized for performance with large tenants
7. Generates a more detailed and customizable report

## Conclusion

The `EntraAppPermissionAudit.ps1` script provides a comprehensive solution for auditing Entra registered applications and their permissions. It meets all the requirements specified in the task and includes additional features for error handling, logging, and performance optimization.