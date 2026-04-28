# Read-only window into photographer-directory's `photographer_services`
# table. Used by the outreach search UI to filter photographers by what
# they shoot (wedding, maternity, family, …). The chatwoot role has
# SELECT only — see db/photographer_directory_grants/2026-04-28-services-select-grant.sql.
class PhotographerDirectory::Service < PhotographerDirectory::ApplicationRecord
  self.table_name = 'photographer_services'
  self.primary_key = 'id'
end
