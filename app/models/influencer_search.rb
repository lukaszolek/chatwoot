# == Schema Information
#
# Table name: influencer_searches
#
#  id                :bigint           not null, primary key
#  credits_used      :float
#  last_credits_left :float
#  page_size         :integer          default(5), not null
#  pages_fetched     :integer          default(0), not null
#  query_params      :jsonb
#  query_signature   :string           not null
#  results           :jsonb
#  results_count     :integer          default(0)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
# Indexes
#
#  index_influencer_searches_on_account_id                      (account_id)
#  index_influencer_searches_on_account_id_and_created_at       (account_id,created_at)
#  index_influencer_searches_on_account_id_and_query_signature  (account_id,query_signature) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class InfluencerSearch < ApplicationRecord
  belongs_to :account

  validates :query_params, presence: true
  validates :query_signature, presence: true
  validates :page_size, numericality: { greater_than: 0 }

  def page_results(page)
    Array(results).slice(page_offset(page), page_size) || []
  end

  def page_cached?(page)
    return true if results_count.to_i.zero? && pages_fetched.to_i.positive? && page.to_i == 1

    start_index = page_offset(page)
    cached_results = page_results(page)

    return true if cached_results.size == page_size
    return false if start_index >= results_count.to_i

    last_page = (start_index + page_size) >= results_count.to_i
    last_page && cached_results.present?
  end

  def append_page_results(page_results)
    self.results = Array(results) + Array(page_results)
  end

  def loaded_count
    Array(results).size
  end

  private

  def page_offset(page)
    ([page.to_i, 1].max - 1) * page_size
  end
end
