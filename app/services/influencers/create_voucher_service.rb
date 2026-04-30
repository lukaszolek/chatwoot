class Influencers::CreateVoucherService
  API_URL = ENV.fetch('FRAMKY_API_URL', 'https://api.framky.com')
  PARTNER_PUBLIC_DISCOUNT_PERCENT = 25

  class VoucherCreationError < StandardError; end

  def initialize(offer:)
    @offer = offer
  end

  def perform
    # 1) Public partner coupon for customers (link coupon)
    create_coupon!(public_partner_coupon_payload, label: 'partner public coupon')

    # 2) One-time amount voucher for influencer's test order
    voucher_response = create_coupon!(voucher_coupon_payload, label: 'influencer voucher')

    {
      voucher_code: voucher_response.parsed_response['code'],
      referral_link: build_referral_link
    }
  end

  private

  def voucher_coupon_payload
    {
      code: generate_voucher_code,
      discount_amount: @offer.voucher_value.to_f,
      discount_amount_currency: @offer.voucher_currency,
      redeem_limit: 1,
      redeem_by: 90.days.from_now.strftime('%Y-%m-%d')
    }
  end

  def public_partner_coupon_payload
    {
      # Must match referral link handle (`framky.com/{handle}`).
      code: public_partner_coupon_code,
      discount_tiers: { default: PARTNER_PUBLIC_DISCOUNT_PERCENT },
      redeem_limit: 0, # unlimited
      kind: 'partner_public',
      revenue_share_to: nil,
      revenue_percentage: 0
    }
  end

  def create_coupon!(payload, label:)
    response = HTTParty.post(
      "#{API_URL}/orders/coupons/",
      headers: auth_headers,
      body: payload.to_json
    )
    raise VoucherCreationError, "Failed to create #{label}: #{response.code} — #{response.body}" unless response.success?

    response
  end

  def generate_voucher_code
    username = @offer.influencer_profile.username.upcase.gsub(/[^A-Z0-9]/, '')
    suffix = rand(100..999).to_s
    "#{username}#{suffix}"
  end

  def public_partner_coupon_code
    @offer.influencer_profile.username.upcase
  end

  def build_referral_link
    username = @offer.influencer_profile.username
    "https://framky.com/#{username}"
  end

  def auth_headers
    {
      'Authorization' => "Token #{ENV.fetch('FRAMKY_API_TOKEN')}",
      'Content-Type' => 'application/json'
    }
  end
end
