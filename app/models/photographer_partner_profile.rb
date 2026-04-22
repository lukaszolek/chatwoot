class PhotographerPartnerProfile < ApplicationRecord
  belongs_to :account
  belongs_to :contact, optional: true

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
