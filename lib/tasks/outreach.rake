# Outreach engine rake tasks.
#
# Usage:
#   # Apply all YAML blueprints in db/campaign_blueprints/ to a specific account
#   bundle exec rake "outreach:blueprints:apply[ACCOUNT_ID]"
#   ACCOUNT_ID=1 bundle exec rake outreach:blueprints:apply
#
#   # Import photographers from photographer-directory for a given country
#   bundle exec rake "outreach:photographers:import[ACCOUNT_ID,pl]"
#   ACCOUNT_ID=1 COUNTRY=pl bundle exec rake outreach:photographers:import
#
#   # Sync knowledge documents (idempotent, run from CI/CD on every deploy)
#   bundle exec rake outreach:knowledge:sync

# rubocop:disable Metrics/BlockLength
namespace :outreach do
  namespace :blueprints do
    desc 'Apply all campaign blueprints in db/campaign_blueprints/ to an account'
    task :apply, [:account_id] => :environment do |_t, args|
      account_id = args[:account_id].presence || ENV.fetch('ACCOUNT_ID', nil)

      raise ArgumentError, 'ACCOUNT_ID is required' if account_id.blank?

      account = Account.find(account_id)
      applied = Outreach::BlueprintApplier.apply_all(account: account)

      puts "Applied #{applied.size} blueprint(s) to account ##{account.id} (#{account.name}):"
      applied.each do |campaign|
        puts "  - #{campaign.program_key} (#{campaign.pipeline_stages.count} stages, " \
             "#{campaign.knowledge_documents.where(active: true).count} knowledge docs)"
      end
    end
  end

  namespace :photographers do
    desc 'Import photographers from photographer-directory (read + write-limited-scope)'
    task :import, %i[account_id country] => :environment do |_t, args|
      account_id = args[:account_id].presence || ENV.fetch('ACCOUNT_ID', nil)
      country = args[:country].presence || ENV.fetch('COUNTRY', nil)

      raise ArgumentError, 'ACCOUNT_ID is required' if account_id.blank?

      account = Account.find(account_id)
      result = Outreach::PhotographerDirectory::Importer.new(account: account, country: country).perform

      puts "Import complete for account ##{account.id} country=#{country || 'all'}:"
      puts "  imported=#{result.imported} updated=#{result.updated} " \
           "skipped=#{result.skipped} failed=#{result.failed} (total=#{result.total})"
    end
  end

  namespace :knowledge do
    # Idempotent rollout of knowledge_documents from
    # Outreach::KnowledgeSeeds::* into every matching campaign. Wired into
    # deployment/framky/deploy.sh so every push to framky/main updates the
    # campaign knowledge base in lockstep with the code that consumes it.
    # Documents are upserted by (kind, locale); operator-added documents
    # whose (kind, locale) is not in the seed list are left untouched.
    desc 'Sync knowledge_documents for all known program seeds across all accounts'
    task sync: :environment do
      seeds = {
        'photographer_partnership' => Outreach::KnowledgeSeeds::PhotographerPartnership
      }

      campaigns = OutboundCampaign.where(program_key: seeds.keys)
      if campaigns.empty?
        puts 'outreach:knowledge:sync — no campaigns matched a seed; nothing to do'
        next
      end

      campaigns.find_each do |campaign|
        seed_module = seeds.fetch(campaign.program_key)
        seed_module.sync!(campaign)
        puts "  synced ##{campaign.id} #{campaign.program_key} (account=#{campaign.account_id}) — " \
             "#{campaign.knowledge_documents.where(active: true).count} active docs"
      end
    end
  end

  namespace :followups do
    desc 'Discard pending reminder/breakup drafts for locales disabled in campaign config. Use APPLY=1 to write.'
    task :discard_disabled, %i[account_id program_key] => :environment do |_t, args|
      account_id = args[:account_id].presence || ENV.fetch('ACCOUNT_ID', nil)
      program_key = args[:program_key].presence || ENV.fetch('PROGRAM_KEY', 'photographer_partnership')

      raise ArgumentError, 'ACCOUNT_ID is required' if account_id.blank?

      campaign = OutboundCampaign.find_by!(account_id: account_id, program_key: program_key)
      configured_locales = (campaign.config || {})['followup_enabled_locales']
      default_locales = Outreach::Engine::Executors::SendTemplate::DEFAULT_FOLLOWUP_ENABLED_LOCALES[campaign.program_key]
      enabled_locales = Array(configured_locales.presence || default_locales).map { |locale| locale.to_s.downcase }
      raise ArgumentError, 'campaign config followup_enabled_locales is empty' if enabled_locales.empty?

      apply = ENV['APPLY'] == '1'
      limit = ENV.fetch('LIMIT', nil)&.to_i
      scope = Message.pending_outreach_drafts
                     .where(account_id: campaign.account_id)
                     .where("messages.additional_attributes->>'outbound_campaign_id' = ?", campaign.id.to_s)
                     .where("messages.additional_attributes->>'template_slot' IN (?)", %w[reminder breakup])
                     .where.not("LOWER(messages.additional_attributes->>'locale') IN (?)", enabled_locales)
                     .order(:created_at)
      scope = scope.limit(limit) if limit&.positive?

      puts "campaign=#{campaign.id} #{campaign.program_key} enabled_followup_locales=#{enabled_locales.join(',')}"
      puts "#{apply ? 'APPLY' : 'DRY_RUN'} pending_disabled_followup_drafts=#{scope.count}"

      scope.find_each do |draft|
        participant = CampaignParticipant.find_by(id: draft.additional_attributes['campaign_participant_id'])
        locale = draft.additional_attributes['locale']
        slot = draft.additional_attributes['template_slot']
        puts "draft=#{draft.id} conversation=#{draft.conversation_id} participant=#{participant&.id} slot=#{slot} locale=#{locale}"
        next unless apply

        Outreach::Drafts::DiscardService.new(draft_message: draft, reason: 'followup_disabled_for_locale').call
        participant&.update!(
          paused: true,
          next_action_at: nil,
          metadata: participant.metadata.to_h.merge('paused_reason' => "followup_disabled_for_locale:#{locale}")
        )
        Outreach::ConversationLabels.mark_sent!(draft.conversation) if draft.conversation&.label_list&.include?('outreach_sent')
      end
    end
  end

  namespace :drafts do
    desc 'Restore approved outreach drafts that never produced a public outgoing message. Use APPLY=1 to write.'
    task :restore_unsent_approved, %i[account_id program_key] => :environment do |_t, args|
      account_id = args[:account_id].presence || ENV.fetch('ACCOUNT_ID', nil)
      program_key = args[:program_key].presence || ENV.fetch('PROGRAM_KEY', 'photographer_partnership')
      slot = ENV.fetch('SLOT', 'intro')

      raise ArgumentError, 'ACCOUNT_ID is required' if account_id.blank?

      campaign = OutboundCampaign.find_by!(account_id: account_id, program_key: program_key)
      apply = ENV['APPLY'] == '1'
      limit = ENV.fetch('LIMIT', nil)&.to_i
      scope = Message.outreach_drafts
                     .where(account_id: campaign.account_id)
                     .where("messages.additional_attributes->>'outbound_campaign_id' = ?", campaign.id.to_s)
                     .where("messages.additional_attributes->>'template_slot' = ?", slot)
                     .where("messages.additional_attributes->>'draft_status' = 'approved'")
                     .order(:created_at)
      scope = scope.limit(limit) if limit&.positive?

      candidates = scope.reject do |draft|
        public_outgoing_after_draft_approval?(draft)
      end

      puts "campaign=#{campaign.id} #{campaign.program_key} slot=#{slot}"
      puts "#{apply ? 'APPLY' : 'DRY_RUN'} approved_drafts_without_public_outgoing=#{candidates.size}"

      candidates.each do |draft|
        participant = CampaignParticipant.find_by(id: draft.additional_attributes['campaign_participant_id'])
        conversation = draft.conversation
        pending_followups = conversation.messages
                                        .pending_outreach_drafts
                                        .where("messages.additional_attributes->>'template_slot' IN (?)", %w[reminder breakup])

        puts "draft=#{draft.id} conversation=#{conversation.id} participant=#{participant&.id} " \
             "stage=#{participant&.current_stage_key} pending_followups=#{pending_followups.count}"
        next unless apply

        pending_followups.find_each do |followup|
          Outreach::Drafts::DiscardService.new(
            draft_message: followup,
            reason: 'superseded_by_restored_unsent_intro'
          ).call
        end

        draft.update!(
          additional_attributes: restored_draft_attributes(draft)
        )
        participant&.update!(
          current_stage_key: slot,
          stage_entered_at: Time.current,
          next_action_at: nil,
          last_outbound_at: nil,
          metadata: participant.metadata.to_h.merge('restored_unsent_approved_draft_at' => Time.current.iso8601)
        )
        restore_conversation_to_draft!(conversation)
      end
    end

    def restored_draft_attributes(draft)
      draft.additional_attributes.to_h.except(
        'approved_by_user_id',
        'approved_at',
        'sent_message_id'
      ).merge(
        'draft_status' => 'pending',
        'restored_from_approved_without_send_at' => Time.current.iso8601
      )
    end

    def restore_conversation_to_draft!(conversation)
      current = Array(conversation.label_list).map(&:to_s)
      labels = ((current - %w[outreach_sent outreach_error]) + ['outreach_draft']).uniq
      conversation.update!(label_list: labels, status: :open)
    end

    def public_outgoing_after_draft_approval?(draft)
      conversation = draft.conversation
      return false unless conversation

      cutoff = draft_approval_cutoff(draft)
      conversation.messages
                  .where(message_type: :outgoing, private: false)
                  .exists?(['messages.created_at >= ?', cutoff])
    end

    def draft_approval_cutoff(draft)
      approved_at = draft.additional_attributes.to_h['approved_at']
      parsed = Time.zone.parse(approved_at.to_s) if approved_at.present?
      (parsed || draft.updated_at || draft.created_at) - 5.minutes
    rescue ArgumentError
      (draft.updated_at || draft.created_at) - 5.minutes
    end
  end
end
# rubocop:enable Metrics/BlockLength
