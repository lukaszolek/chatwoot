class Api::V1::Accounts::Outreach::StatsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  # GET /api/v1/accounts/:account_id/outreach/stats/daily_new?days=14
  def daily_new
    days = (params[:days] || 14).to_i.clamp(1, 90)
    since = days.days.ago.beginning_of_day

    profiles = Current.account.photographer_partner_profiles
                      .where('created_at >= ?', since)
                      .to_a
    PhotographerPartnerProfile.preload_sources!(profiles)

    buckets = Hash.new { |h, k| h[k] = Hash.new(0) }
    profiles.each do |p|
      day = p.created_at.in_time_zone.to_date.iso8601
      cc  = (p.country_code.presence || '__unknown__').to_s.upcase
      buckets[day][cc] += 1
    end

    render json: {
      days: days,
      buckets: buckets,
      countries: buckets.values.flat_map(&:keys).uniq.sort
    }
  end

  # GET /api/v1/accounts/:account_id/outreach/stats/funnel?window_days=7
  def funnel
    window = (params[:window_days] || 7).to_i.clamp(1, 90)
    since  = window.days.ago

    first_sent = CampaignParticipant
                 .where(account_id: Current.account.id,
                        participatable_type: 'PhotographerPartnerProfile')
                 .group(:participatable_id)
                 .minimum(:created_at)
    cohort_ids = first_sent.select { |_, ts| ts >= since }.keys
    profiles   = Current.account.photographer_partner_profiles.where(id: cohort_ids).to_a

    statuses = profiles.map { |p| p.partnership_status.to_s }
    # Enum rank is misleading for funnel — `declined` (6) / `do_not_contact` (7) sort
    # higher than `signed_up` (5) but are side-exits, not deeper progress. We
    # whitelist current statuses per stage instead so the funnel matches the
    # pipeline view (e.g. Zarejestrowani == pipeline "signed_up" only).
    stages = [
      { key: 'sent',       label: 'Wysłane',
        statuses: %w[imported qualified contacted replied interested signed_up declined do_not_contact completed] },
      { key: 'contacted',  label: 'Skontaktowani',  statuses: %w[contacted replied interested signed_up declined do_not_contact completed] },
      { key: 'replied',    label: 'Odpowiedzieli',  statuses: %w[replied interested signed_up declined do_not_contact completed] },
      { key: 'interested', label: 'Zainteresowani', statuses: %w[interested signed_up completed] },
      { key: 'signed_up',  label: 'Zarejestrowani', statuses: %w[signed_up completed] }
    ]
    cohort = statuses.size
    rows = stages.map do |s|
      allowed = s[:statuses].to_set
      count = statuses.count { |st| allowed.include?(st) }
      pct   = cohort.zero? ? 0 : (count.to_f / cohort * 100).round(1)
      { key: s[:key], label: s[:label], count: count, pct: pct }
    end

    render json: { window_days: window, cohort_size: cohort, stages: rows }
  end

  private

  def check_authorization
    authorize(PhotographerPartnerProfile)
  end
end
