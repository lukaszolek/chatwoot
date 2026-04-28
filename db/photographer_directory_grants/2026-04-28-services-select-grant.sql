-- Run this on the photographer_directory PostgreSQL instance (NOT chatwoot's DB).
-- Required so chatwoot's outreach UI can filter photographers by service
-- category (wedding, maternity, family, …). The outreach role already has
-- SELECT on photographer_photographers; this adds the join target.
--
-- Run as a superuser or the table owner:
--   psql -U postgres -d photographer_directory -f 2026-04-28-services-select-grant.sql

\echo '=== Granting SELECT on photographer_services to photographer_directory_outreach ==='

GRANT SELECT ON photographer_services TO photographer_directory_outreach;

\echo '=== Verification ==='

SELECT table_name, privilege_type
  FROM information_schema.table_privileges
 WHERE grantee = 'photographer_directory_outreach'
   AND table_name = 'photographer_services';
