# Renders a CampaignTemplate against a CampaignParticipant using Liquid.
#
# Input slots are taken from the participant's profile attributes first
# (first_name, business_name, city, instagram, website, locale, …) and
# then overlaid with the participant's metadata hash. This lets a
# blueprint template address common profile fields by name while still
# allowing per-participant metadata to override or extend the context
# (e.g. signup_link, utm_source, cohort_id).
#
# Locale resolution mirrors SendTemplate's lookup path: the caller is
# expected to have already resolved the correct template for the
# participant's locale (with campaign default_locale fallback).
class Outreach::Engine::TemplateRenderer
  class RenderError < StandardError; end

  def initialize(template:, participant:)
    @template = template
    @participant = participant
  end

  def render
    context = build_context
    {
      subject: render_liquid(@template.subject, context),
      body: render_liquid(@template.body, context)
    }
  end

  private

  def build_context
    profile = @participant.participatable
    metadata = (@participant.metadata || {}).stringify_keys

    profile_context = {}
    if profile.respond_to?(:email)
      profile_context = {
        'email' => profile.email,
        'business_name' => profile.try(:business_name),
        'owner_name' => profile.try(:owner_name),
        'first_name' => first_name_from(profile),
        'website' => profile.try(:website),
        'country_code' => profile.try(:country_code),
        'instagram_handle' => profile.try(:instagram_handle),
        'preferred_language' => profile.try(:preferred_language)
      }.compact
    end

    # `personal_opener` is filled by SendTemplate executor post-Liquid,
    # via Outreach::Llm::IntroComposer (LLM-generated + website snippet).
    # Map it to itself so Liquid leaves the placeholder intact for the
    # caller's string-replace step. Without this mapping, strict_variables
    # being false would collapse the placeholder to an empty string.
    { 'personal_opener' => '{{personal_opener}}' }
      .merge(profile_context)
      .merge(metadata)
  end

  def first_name_from(profile)
    name = profile.try(:owner_name).to_s.strip
    return nil if name.empty?

    name.split(/\s+/).first
  end

  def render_liquid(raw, context)
    Liquid::Template.parse(raw.to_s).render!(context, strict_variables: false)
  rescue Liquid::Error => e
    raise RenderError, "Failed to render template id=#{@template.id}: #{e.message}"
  end
end
