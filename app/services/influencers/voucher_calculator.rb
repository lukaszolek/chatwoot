class Influencers::VoucherCalculator
  RATE = 0.019
  CONTENT_WEIGHTS = { reel: 0.5, carousel: 0.2, stories: 0.3 }.freeze
  RIGHTS_MULTIPLIERS = { 'standard' => 1.0, 'extended' => 1.5 }.freeze
  CONTENT_FLOOR = 0.1
  EXCHANGE_RATES = { 'EUR' => 1.0, 'GBP' => 0.86, 'PLN' => 4.28 }.freeze

  def initialize(followers:, fqs_score:, packages:, rights: 'standard', multiplier: 1.0)
    @followers = followers.to_f
    @fqs_score = fqs_score.present? ? fqs_score.to_f : 50.0
    @packages = packages || {}
    @rights = rights
    @multiplier = multiplier.to_f
  end

  # Returns value in EUR
  def value
    content_mult = @packages.sum { |pkg, on| ActiveModel::Type::Boolean.new.cast(on) ? CONTENT_WEIGHTS.fetch(pkg.to_sym, 0) : 0 }
    content_mult = content_mult.positive? ? [content_mult, CONTENT_FLOOR].max : 0
    rights_mult = RIGHTS_MULTIPLIERS.fetch(@rights, 1.0)

    (@followers * (@fqs_score / 100.0) * RATE * content_mult * rights_mult * @multiplier).round(2)
  end

  def self.convert(eur_value, target_currency)
    rate = EXCHANGE_RATES.fetch(target_currency, 1.0)
    (eur_value * rate).round(2)
  end
end
