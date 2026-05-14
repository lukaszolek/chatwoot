# == Schema Information
#
# Table name: contact_pipeline_stages
#
#  id                :bigint           not null, primary key
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  contact_id        :bigint           not null
#  pipeline_stage_id :bigint           not null
#
# Indexes
#
#  idx_contact_pipeline_stages_unique                  (contact_id,pipeline_stage_id) UNIQUE
#  index_contact_pipeline_stages_on_account_id         (account_id)
#  index_contact_pipeline_stages_on_contact_id         (contact_id)
#  index_contact_pipeline_stages_on_pipeline_stage_id  (pipeline_stage_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (pipeline_stage_id => pipeline_stages.id)
#
class ContactPipelineStage < ApplicationRecord
  belongs_to :contact
  belongs_to :pipeline_stage
  belongs_to :account
end
