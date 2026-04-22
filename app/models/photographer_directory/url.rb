# Read-only window into photographer-directory's `urls` table.
# See PhotographerDirectory::Photographer for the role's write
# boundary; this table is SELECT-only for the chatwoot role.
class PhotographerDirectory::Url < PhotographerDirectory::ApplicationRecord
  self.table_name = 'urls'
  self.primary_key = 'id'
end
