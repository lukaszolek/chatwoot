module Outreach
  module PhotographerDirectory
    # ============================================================
    # THE ONLY PATH THAT WRITES TO photographer-directory.
    # Do not bypass with direct `update!` calls elsewhere.
    # ============================================================
    #
    # Propagates consent-state mutations (opt-out, GDPR delete, bounce) from
    # chatwoot into the photographer-directory source-of-truth. Every call
    # emits a CampaignAttributionEvent audit record on the chatwoot side, so
    # we always have a trail of who changed what and why.
    #
    # Idempotent within a 24h window: repeated calls for the same
    # (profile, event_type) on the same day produce one attribution event,
    # not many. Re-running tomorrow creates a new event — that's
    # intentional: if an operator opts someone out again, we want the record.
    #
    # Used by:
    #   - List-unsubscribe webhook (C7)
    #   - Operator "opt out" action in PhotographerDetail.vue (C5)
    #   - Reply classifier on explicit decline (C4)
    #   - Email bounce handler (C3/C7)
    #   - GDPR delete request form (post-MVP)
    class ConsentWriter
      class PhotographerNotFound < StandardError; end

      IDEMPOTENCY_WINDOW = 24.hours

      def initialize(profile)
        @profile = profile
      end

      def propagate_opt_out(reason:)
        with_idempotency(:unsubscribe, reason: reason) do |source|
          source.opt_out!
          @profile.transition_to!(:do_not_contact)
        end
      end

      def propagate_gdpr_delete
        with_idempotency(:gdpr_delete) do |source|
          source.request_gdpr_delete!
          @profile.transition_to!(:do_not_contact)
        end
      end

      def propagate_bounce(reason: 'hard_bounce')
        with_idempotency(:email_bounce, reason: reason) do |source|
          source.opt_out!
          @profile.transition_to!(:do_not_contact)
        end
      end

      private

      attr_reader :profile

      def with_idempotency(event_type, payload = {})
        return if recent_event?(event_type)

        source = find_source!

        ActiveRecord::Base.transaction do
          yield source
          last_participant_for(profile).attribution_events.create!(
            event_type: event_type,
            occurred_at: Time.current,
            payload: payload.merge(applied_by: 'consent_writer').stringify_keys
          )
        end
      end

      def recent_event?(event_type)
        participant = last_participant_for(profile)
        return false unless participant

        participant.attribution_events
                   .where(event_type: CampaignAttributionEvent.event_types[event_type])
                   .where(occurred_at: IDEMPOTENCY_WINDOW.ago..)
                   .exists?
      end

      def find_source!
        source = ::PhotographerDirectory::Photographer.find_by(id: profile.external_id)
        raise PhotographerNotFound, "photographer_directory row missing for external_id=#{profile.external_id}" unless source

        source
      end

      # Every ConsentWriter mutation attaches its audit trail to the most
      # recent CampaignParticipant for this profile. If none exists yet
      # (e.g., opt-out arrives before the profile entered any campaign),
      # create a bare-minimum "synthetic" participant scoped to the current
      # program so the event has a home.
      def last_participant_for(profile)
        participant = CampaignParticipant
                      .where(participatable: profile, account: profile.account)
                      .order(created_at: :desc).first
        return participant if participant

        campaign = OutboundCampaign.find_by(account: profile.account, program_key: 'photographer_partnership')
        return nil unless campaign

        CampaignParticipant.create!(
          outbound_campaign: campaign,
          account: profile.account,
          participatable: profile,
          contact: profile.contact,
          current_stage_key: 'terminal',
          stage_entered_at: Time.current,
          paused: true,
          metadata: { 'synthetic_for_consent_audit' => true }
        )
      end
    end
  end
end
