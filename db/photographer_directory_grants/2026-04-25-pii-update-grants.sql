-- Run this on the photographer_directory PostgreSQL instance (NOT chatwoot's DB).
-- Required by chatwoot's Outreach::PhotographerDirectory::ProfileWriter — without
-- these grants, operators editing PII in the chatwoot edit-sidebar will hit
-- "permission denied for table photographer_photographers" at the wire.
--
-- Run as a superuser or the table owner:
--   psql -U postgres -d photographer_directory -f 2026-04-25-pii-update-grants.sql
--
-- Existing UPDATE grants (kept):
--   marketing_consent, unsubscribed_from_all_campaigns, unsubscribed_from_all_at,
--   gdpr_delete_requested_at
--
-- New UPDATE grants (this file adds):
--   email, business_name, owner_name, website, country_code, instagram_handle,
--   phone, native_language, preferred_language

\echo '=== Granting UPDATE on PII columns to photographer_directory_outreach role ==='

GRANT UPDATE (email)              ON photographer_photographers TO photographer_directory_outreach;
GRANT UPDATE (business_name)      ON photographer_photographers TO photographer_directory_outreach;
GRANT UPDATE (owner_name)         ON photographer_photographers TO photographer_directory_outreach;
GRANT UPDATE (website)            ON photographer_photographers TO photographer_directory_outreach;
GRANT UPDATE (country_code)       ON photographer_photographers TO photographer_directory_outreach;
GRANT UPDATE (instagram_handle)   ON photographer_photographers TO photographer_directory_outreach;
GRANT UPDATE (phone)              ON photographer_photographers TO photographer_directory_outreach;
GRANT UPDATE (native_language)    ON photographer_photographers TO photographer_directory_outreach;
GRANT UPDATE (preferred_language) ON photographer_photographers TO photographer_directory_outreach;

\echo '=== Verification — UPDATE grants currently held by photographer_directory_outreach ==='

SELECT column_name
  FROM information_schema.column_privileges
 WHERE table_name = 'photographer_photographers'
   AND grantee    = 'photographer_directory_outreach'
   AND privilege_type = 'UPDATE'
 ORDER BY column_name;
