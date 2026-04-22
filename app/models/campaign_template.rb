class CampaignTemplate < ApplicationRecord
  belongs_to :outbound_campaign

  validates :slot, presence: true
  validates :locale, presence: true
  validates :subject, presence: true
  validates :body, presence: true

  scope :active_templates, -> { where(active: true) }

  def self.lookup(outbound_campaign:, slot:, locale:)
    active_templates
      .where(outbound_campaign: outbound_campaign, slot: slot, locale: locale)
      .first
  end
end
