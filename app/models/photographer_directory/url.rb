# Read-only window into photographer-directory's `urls` table.
# See PhotographerDirectory::Photographer for the role's write
# boundary; this table is SELECT-only for the chatwoot role.
# == Schema Information
#
# Table name: urls
#
#  id                        :bigint           not null, primary key
#  changefreq                :text
#  classification_confidence :integer
#  classification_method     :enum
#  classification_status     :enum             default("pending")
#  classified_at             :datetime
#  classified_type           :enum
#  crawl_priority            :integer          default(50)
#  domain                    :text             not null
#  lastmod                   :datetime
#  priority                  :decimal(2, 1)
#  should_crawl              :boolean          default(FALSE)
#  url_path                  :text             not null
#  created_at                :datetime
#  sitemap_id                :bigint           not null
#
# Indexes
#
#  url_domain_idx          (domain)
#  url_domain_path_unique  (domain,url_path) UNIQUE
#  url_should_crawl_idx    (should_crawl,crawl_priority)
#  url_sitemap_idx         (sitemap_id)
#  url_type_idx            (classified_type)
#
# Foreign Keys
#
#  urls_domain_websites_domain_fk  (domain => websites.domain)
#  urls_sitemap_id_sitemaps_id_fk  (sitemap_id => sitemaps.id) ON DELETE => cascade
#
class PhotographerDirectory::Url < PhotographerDirectory::ApplicationRecord
  self.table_name = 'urls'
  self.primary_key = 'id'
end
