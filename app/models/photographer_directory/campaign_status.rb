# Read-only view of photographer-directory's `photographer_campaign_status`
# table. Used by the outreach importer to exclude photographers currently
# enrolled in another campaign (e.g., the onboarding CRM) per the Option C
# "parallel campaigns" decision (see docs/plans/2026-04-22-001-*).
#
# This table is never written from chatwoot.
# == Schema Information
#
# Table name: photographer_campaign_status(Photographer enrollment and progress in campaigns (Kanban cards))
#
#  id                                                                              :bigint           not null, primary key
#  completed_at                                                                    :timestamptz
#  emails_clicked                                                                  :integer          default(0)
#  emails_delivered(Number of successfully delivered emails)                       :integer          default(0)
#  emails_opened                                                                   :integer          default(0)
#  emails_sent                                                                     :integer          default(0)
#  enrolled_at                                                                     :timestamptz      not null
#  last_email_sent_at                                                              :timestamptz
#  last_status_change_at(Timestamp of last status change (for auto-advance logic)) :timestamptz      not null
#  notes                                                                           :text
#  replies_received                                                                :integer          default(0)
#  status                                                                          :text             default("enrolled"), not null
#  tags                                                                            :text             is an Array
#  unsubscribe_reason                                                              :enum
#  unsubscribed_at                                                                 :timestamptz
#  unsubscribed_from_campaign                                                      :boolean          default(FALSE)
#  updated_at                                                                      :timestamptz      not null
#  campaign_id                                                                     :bigint           not null
#  photographer_id                                                                 :bigint           not null
#
# Indexes
#
#  campaign_status_campaign_idx            (campaign_id)
#  campaign_status_last_status_change_idx  (last_status_change_at)
#  campaign_status_photographer_idx        (photographer_id)
#  campaign_status_status_idx              (status)
#  campaign_status_unsubscribed_idx        (unsubscribed_from_campaign)
#  photographer_campaign_unique            (photographer_id,campaign_id) UNIQUE
#
# Foreign Keys
#
#  photographer_campaign_status_campaign_id_email_campaigns_id_fk  (campaign_id => email_campaigns.id) ON DELETE => cascade
#
class PhotographerDirectory::CampaignStatus < PhotographerDirectory::ApplicationRecord
  self.table_name = 'photographer_campaign_status'

  scope :active_enrolment, lambda {
    where(completed_at: nil, unsubscribed_from_campaign: false)
  }
end
