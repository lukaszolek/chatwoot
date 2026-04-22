# Read-only window into photographer-directory's `pages` table. The
# chatwoot role has SELECT only — IntroComposer uses content_markdown
# to cite concrete details from the photographer's own site.
class PhotographerDirectory::Page < PhotographerDirectory::ApplicationRecord
  self.table_name = 'pages'
  self.primary_key = 'id'
end
