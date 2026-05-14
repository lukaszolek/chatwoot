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

    statuses = profiles.map { |p| PhotographerPartnerProfile.partnership_statuses[p.partnership_status] }
    stages = [
      { key: 'sent',       label: 'Wysłane',        min_rank: 0 },
      { key: 'contacted',  label: 'Skontaktowani',  min_rank: 2 },
      { key: 'replied',    label: 'Odpowiedzieli',  min_rank: 3 },
      { key: 'interested', label: 'Zainteresowani', min_rank: 4 },
      { key: 'signed_up',  label: 'Zarejestrowani', min_rank: 5 }
    ]
    cohort = statuses.size
    rows = stages.map do |s|
      count = statuses.count { |r| r >= s[:min_rank] }
      pct   = cohort.zero? ? 0 : (count.to_f / cohort * 100).round(1)
      s.merge(count: count, pct: pct)
    end

    render json: { window_days: window, cohort_size: cohort, stages: rows }
  end

  private

  def check_authorization
    authorize(PhotographerPartnerProfile)
  end
end
