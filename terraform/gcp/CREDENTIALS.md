# Vexa GCP Credentials Management

## Overview
This directory implements a secure, centralized credential management system following industry best practices. All sensitive credentials are stored in `terraform.auto.tfvars` which is git-ignored for security.

## Quick Setup

1. **Copy the example file:**
   ```bash
   cp terraform.auto.tfvars.example terraform.auto.tfvars
   ```

2. **Edit the credentials:**
   ```bash
   # Edit with your preferred editor
   nano terraform.auto.tfvars
   ```

3. **Fill in the values:**
   - `gcp_project_id`: Your GCP project ID
   - `admin_api_token`: Secure token for admin API access
   - `db_password`: Database password (optional - auto-generated if not provided)

## Security Features

### ✅ Centralized Management
- All credentials in one place: `terraform.auto.tfvars`
- Clear separation between infrastructure config and secrets
- Easy to rotate credentials by updating one file

### ✅ Git Security
- `*.auto.tfvars` files are automatically git-ignored
- Example file provides template without exposing secrets
- Prevents accidental commits of sensitive data

### ✅ Industry Best Practices
- Follows Terraform conventions for credential management
- Compatible with CI/CD pipelines and environment variables
- Prepared for future migration to HashiCorp Vault

### ✅ Database Security
- Supports both auto-generated and custom passwords
- Passwords stored in GCP Secret Manager
- Database credentials synchronized between Terraform and Nomad

## File Structure

```
terraform/gcp/
├── terraform.auto.tfvars.example  # Template (safe to commit)
├── terraform.auto.tfvars          # Your secrets (git-ignored)
├── variables.tf                   # Variable definitions
└── CREDENTIALS.md                 # This documentation
```

## Environment Variables (Alternative)

You can also provide credentials via environment variables:

```bash
export TF_VAR_gcp_project_id="your-project-id"
export TF_VAR_admin_api_token="your-admin-token"
export TF_VAR_db_password="your-db-password"
```

## Future: HashiCorp Vault Migration

This system is designed to easily migrate to HashiCorp Vault:

1. **Phase 1** (Current): terraform.auto.tfvars
2. **Phase 2** (Future): Vault integration with vault provider
3. **Phase 3** (Future): Dynamic secrets and rotation

## Credential Flow

```
terraform.auto.tfvars → Terraform → [GCP Secret Manager + Nomad Variables] → Applications
```

1. **terraform.auto.tfvars**: Source of truth for credentials
2. **Terraform**: Reads credentials and distributes them securely
3. **GCP Secret Manager**: Stores database passwords
4. **Nomad Variables**: Provides runtime access to applications
5. **Applications**: Access credentials via environment variables

## Troubleshooting

### Database Authentication Issues
If you see "password authentication failed" errors:

1. Check the `db_password` in `terraform.auto.tfvars`
2. Run `terraform apply` to sync passwords
3. Verify with: `nomad var get secret/vexa/db`

### Missing Credentials
If Terraform asks for variables:

1. Ensure `terraform.auto.tfvars` exists
2. Check file permissions (readable by your user)
3. Verify all required variables are set

## Security Notes

⚠️ **NEVER** commit `terraform.auto.tfvars` to version control  
⚠️ **NEVER** store credentials in `terraform.tfvars` (this file IS committed)  
⚠️ **ALWAYS** use the `.auto.tfvars` extension for credentials  
⚠️ **ALWAYS** rotate credentials regularly  

## Support

For questions about credential management, refer to:
- [Terraform Documentation on Variables](https://terraform.io/docs/language/values/variables.html)
- [Nomad Variables Guide](https://nomadproject.io/docs/concepts/variables)
- [GCP Secret Manager](https://cloud.google.com/secret-manager/docs) 