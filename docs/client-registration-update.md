# WASLA STUDIO — Client registration update

Branch: `feature/wasla-v6`

This update documents the tenant-scoped client registration work included in the Windows build:
- Company-specific client registration links.
- Client signup fields: full name, phone, email, optional company name.
- Tenant-scoped pending approval queue with approve/reject actions.
- On approval, create the client record and link the client account to the tenant.

## Deployment prerequisite

The database migration `supabase/migrations/20261120070000_tenant_client_self_registration.sql` must be reviewed and applied to the target Supabase project before the registration workflow is enabled in production. A successful Windows build does not apply database migrations or deploy the web app.

## Test checklist

- Create a registration link while signed in as a tenant owner/admin.
- Register a new client using that link.
- Verify the request appears only for that tenant's manager.
- Approve the request and verify the client record and client account mapping.
- Sign in as the client and verify access is limited to the client portal and visible projects.
- Repeat with a second tenant and verify isolation.
