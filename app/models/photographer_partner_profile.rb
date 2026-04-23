class PhotographerPartnerProfile < ApplicationRecord
  belongs_to :account
  belongs_to :contact, optional: true

  # Tri-state consent, source of truth on the chatwoot side.
  #   unknown  — operator has not asked / photographer has not answered
  #   granted  — explicit yes for partnership outreach
  #   declined — explicit no / unsubscribed
  # boolean `marketing_consent` stays on the row for interop with
  # photographer-directory (which only has a bool + unsubscribed flag).
  enum :marketing_consent_state, {
    unknown: 0,
    granted: 1,
    declined: 2
  }, prefix: :consent

  enum :partnership_status, {
    imported: 0,
    qualified: 1,
    contacted: 2,
    replied: 3,
    interested: 4,
    signed_up: 5,
    declined: 6,
    do_not_contact: 7,
    completed: 8
  }

  validates :external_id, presence: true,
                          uniqueness: { scope: :account_id }
  validates :email, presence: true,
                    uniqueness: { scope: :account_id, case_sensitive: false }

  scope :active_outreach, -> { where.not(partnership_status: %i[do_not_contact completed]) }

  def transition_to!(new_status)
    update!(
      partnership_status: new_status,
      partnership_status_changed_at: Time.current
    )
  end
end
