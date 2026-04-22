module Outreach
  module PhotographerDirectory
    # Async wrapper around ConsentWriter. All operator-facing consent
    # mutations (opt-out, bounce, GDPR delete) should enqueue this job so
    # a transient DB failure against the secondary connection retries
    # rather than surfacing as a 5xx or a dropped signal.
    #
    # After 5 attempts the job fails permanently; the retry callback logs
    # to ErrorTracker so an operator can intervene.
    class PropagateConsentJob < ApplicationJob
      queue_as :outreach

      retry_on ActiveRecord::StatementInvalid,
               PG::ConnectionBad,
               ActiveRecord::ConnectionNotEstablished,
               wait: :polynomially_longer,
               attempts: 5

      def perform(profile_id, action, **kwargs)
        profile = PhotographerPartnerProfile.find(profile_id)
        writer = ConsentWriter.new(profile)

        case action.to_s
        when 'opt_out'      then writer.propagate_opt_out(reason: kwargs[:reason].to_s)
        when 'gdpr_delete'  then writer.propagate_gdpr_delete
        when 'bounce'       then writer.propagate_bounce(reason: kwargs.fetch(:reason, 'hard_bounce'))
        else raise ArgumentError, "unknown consent propagation action: #{action.inspect}"
        end
      end
    end
  end
end
