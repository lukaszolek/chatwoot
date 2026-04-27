class Outreach::Agent::Tools::SubmitInvoice < Outreach::Agent::Tools::Base
  description <<~DESC
    Forwards an invoice (file URL + period + amount) to the Framky Partner
    Panel for verification and payout queueing. Use when the photographer
    sends an invoice in a reply (their accountant says 'attached for last
    month'). file_url is a public URL or a Chatwoot attachment URL the
    backend can fetch. period_iso is the YYYY-MM the invoice covers.
  DESC

  param :sender_email, desc: 'Email of the photographer who sent the inbound', required: true
  param :file_url, desc: 'Publicly fetchable URL of the invoice PDF', required: true
  param :period_iso, desc: 'Period the invoice covers, ISO YYYY-MM', required: true
  param :amount_eur, desc: 'Invoice gross amount in EUR (number)', required: true
  param :vat_id, desc: 'Optional VAT/Tax ID', required: false

  def execute!(profile:, file_url:, period_iso:, amount_eur:, vat_id: nil, **_params)
    raise ArgumentError, 'profile has no external_id' if profile.external_id.blank?

    Framky::PartnerProgramClient.new.submit_invoice(
      profile.external_id,
      file_url: file_url,
      period_iso: period_iso,
      amount_eur: amount_eur,
      vat_id: vat_id
    )
  end
end
