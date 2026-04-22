# Read-only view of photographer-directory's `photographer_campaign_status`
# table. Used by the outreach importer to exclude photographers currently
# enrolled in another campaign (e.g., the onboarding CRM) per the Option C
# "parallel campaigns" decision (see docs/plans/2026-04-22-001-*).
#
# This table is never written from chatwoot.
class PhotographerDirectory::CampaignStatus < PhotographerDirectory::ApplicationRecord
  self.table_name = 'photographer_campaign_status'

  scope :active_enrolment, lambda {
    where(completed_at: nil, unsubscribed_from_campaign: false)
  }
end
