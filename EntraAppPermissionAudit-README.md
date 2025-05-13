# Entra Application Permission Audit Tool

This PowerShell script provides a comprehensive audit of all Entra (formerly Azure AD) registered applications and their associated permissions via the Microsoft Graph API.

## Features

- Extracts all Entra registered applications with their associated service principals
- Generates a detailed CSV report containing:
  - Application display name, ID, and object ID
  - Service principal details
  - All delegated and application permissions granted to each app
  - Clear identification of industry-standard privileged/high-risk permissions
  - Custom flagging mechanism for client-specific privileged permissions
  - Permission status (granted/not granted)
  - Permission type (delegated/application)
- Provides proper authentication handling and error management
- Optimized for performance with large tenants
- Includes detailed logging for troubleshooting

## Prerequisites

- PowerShell 5.1 or higher
- Microsoft Graph PowerShell SDK modules:
  - Microsoft.Graph.Applications
  - Microsoft.Graph.Authentication
- Appropriate permissions to access Microsoft Graph API:
  - Application.Read.All
  - Directory.Read.All
  - AppRoleAssignment.ReadWrite.All

## Installation

1. Install the required Microsoft Graph PowerShell modules:

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

2. Download the script files:
   - EntraAppPermissionAudit.ps1
   - EntraAppPermissionAudit-README.md

## Usage

1. Run the script from PowerShell:

```powershell
.\EntraAppPermissionAudit.ps1
```

2. When prompted, authenticate with an account that has the necessary permissions.

3. The script will:
   - Connect to Microsoft Graph
   - Retrieve all registered applications and service principals
   - Extract all permissions (both delegated and application)
   - Generate a detailed CSV report
   - Provide a summary of the findings

## Output

The script creates a folder named `EntraAuditReports` in the current directory with:

1. A timestamped CSV file containing the detailed audit report
2. A timestamped log file with execution details

The CSV report includes the following information for each application:
- Application display name, ID, and object ID
- Service principal ID and display name
- Application creation date
- Application owners
- Permission type (Delegated/Application)
- Resource the permission is for
- Permission name and display name
- Whether the permission is granted
- Whether the permission is considered privileged (standard or custom)

## Customization

You can customize the list of privileged/high-risk permissions by modifying the following arrays in the script:

- `$PrivilegedAppPermissions`: Industry-standard privileged permissions
- `$CustomPrivilegedPermissions`: Client-specific privileged permissions

## Troubleshooting

If you encounter issues:

1. Check the log file in the `EntraAuditReports` folder for detailed error messages
2. Ensure you have the required permissions
3. Verify that the Microsoft Graph PowerShell modules are installed correctly

## Notes

- The script uses pagination to handle large tenants efficiently
- For very large tenants, the script may take some time to complete
- The script provides progress indicators during execution

## License

This script is provided as-is with no warranty. Use at your own risk.