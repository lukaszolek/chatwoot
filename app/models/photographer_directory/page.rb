# Read-only window into photographer-directory's `pages` table. The
# chatwoot role has SELECT only — IntroComposer uses content_markdown
# to cite concrete details from the photographer's own site.
# == Schema Information
#
# Table name: pages
#
#  id               :bigint           not null, primary key
#  content_markdown :text
#  crawled_at       :datetime
#  error_message    :text
#  external_links   :text             is an Array
#  http_status_code :integer
#  image_count      :integer          default(0)
#  images           :jsonb
#  internal_links   :text             is an Array
#  language         :text
#  meta_description :text
#  primary_image    :text
#  retry_count      :integer          default(0)
#  status           :enum             default("pending")
#  title            :text
#  created_at       :datetime
#  updated_at       :datetime
#  url_id           :bigint           not null
#
# Indexes
#
#  domain_page_status_idx  (status)
#  domain_page_url_idx     (url_id)
#
# Foreign Keys
#
#  pages_url_id_urls_id_fk  (url_id => urls.id) ON DELETE => cascade
#
class PhotographerDirectory::Page < PhotographerDirectory::ApplicationRecord
  self.table_name = 'pages'
  self.primary_key = 'id'
end
