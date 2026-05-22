require 'uri'

# ============================================================
# WRITES PII FIELDS BACK TO photographer-directory.
# Companion to ConsentWriter — same DB, different column band.
# Do not bypass with direct `update!` calls elsewhere.
# ============================================================
#
# Single source of truth for PII (email, business_name, owner_name,
# website, country_code, instagram_handle, phone, native_language,
# preferred_language) lives in photographer-directory. When an operator
# edits the photographer in chatwoot's edit-sidebar, this service
# propagates the change to the directory and writes a
# CampaignAttributionEvent (event_type=:profile_edit) so we have a
# trail of who changed what and when.
#
# Failure modes:
#   - Permission denied at DB level → raise GrantsMissing with the
#     specific column. Operator sees a hint to expand grants.
#   - Email format invalid → raise ValidationError before we touch DB.
#   - Source row gone → raise PhotographerNotFound.
class Outreach::PhotographerDirectory::ProfileWriter
  class WriterError < StandardError; end
  class PhotographerNotFound < WriterError; end
  class ValidationError < WriterError; end
  class GrantsMissing < WriterError; end
  class UniqueConflict < WriterError; end
  class ForeignKeyMissing < WriterError; end

  ALLOWED_FIELDS = %i[
    email
    business_name
    owner_name
    website
    country_code
    instagram_handle
    phone
    native_language
    preferred_language
  ].freeze

  EMAIL_RE = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  def initialize(profile, user: nil)
    @profile = profile
    @user = user
  end

  def update!(attrs)
    sanitized = sanitize(attrs)
    return { ok: true, changed: {} } if sanitized.empty?

    validate!(sanitized)
    source = find_source!
    previous = previous_values(source, sanitized)
    return { ok: true, changed: {} } if previous == sanitized.transform_keys(&:to_s)

    persist_update!(source, sanitized, previous)
    reload_profile!

    { ok: true, changed: diff(previous, sanitized) }
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::InvalidForeignKey, ActiveRecord::StatementInvalid => e
    handle_write_error!(e)
  end

  private

  attr_reader :profile, :user

  def persist_update!(source, sanitized, previous)
    ActiveRecord::Base.transaction do
      source.update!(sanitized)
      record_audit!(previous: previous, new_values: sanitized)
    end
  end

  def reload_profile!
    # Bust the per-instance cache on the chatwoot side so subsequent
    # reads see the new values.
    profile.reload
  end

  def handle_write_error!(error)
    raise UniqueConflict, friendly_unique_message(error) if error.is_a?(ActiveRecord::RecordNotUnique)
    raise ForeignKeyMissing, friendly_fk_message(error) if error.is_a?(ActiveRecord::InvalidForeignKey)
    raise GrantsMissing, grants_missing_message(error) if error.message.include?('permission denied')
    raise UniqueConflict, friendly_unique_message(error) if error.message.include?('duplicate key value violates unique constraint')
    raise ForeignKeyMissing, friendly_fk_message(error) if error.message.include?('foreign key constraint')

    raise error
  end

  def grants_missing_message(error)
    'directory DB rejected the write — most likely missing column UPDATE grants. ' \
      "Original: #{error.message.truncate(180)}"
  end

  def sanitize(attrs)
    return {} unless attrs.is_a?(Hash)

    out = {}
    attrs.each do |k, v|
      key = k.to_sym
      next unless ALLOWED_FIELDS.include?(key)

      val = v.to_s.strip
      val = val.presence  # blank → nil so directory can clear a field
      val = normalize_website(val) if key == :website && val.present?
      out[key] = val
    end
    out
  end

  def normalize_website(value)
    raw = value.to_s.strip
    raw = "https://#{raw}" unless raw.match?(%r{\Ahttps?://}i)
    uri = URI.parse(raw)
    host = uri.host.presence || value
    host.to_s.downcase.delete_prefix('www.')
  rescue URI::InvalidURIError
    value.to_s.strip.downcase.sub(%r{\Ahttps?://}i, '').split('/').first.to_s.delete_prefix('www.')
  end

  def validate!(attrs)
    validate_email!(attrs[:email]) if attrs.key?(:email)
    validate_country_code!(attrs[:country_code]) if attrs.key?(:country_code)
    # native_language / preferred_language: just lowercase, no strict
    # whitelist (directory accepts whatever it accepts).
    %i[native_language preferred_language].each do |k|
      attrs[k] = attrs[k].downcase if attrs[k].is_a?(String)
    end
  end

  def validate_email!(email_value)
    email = email_value.to_s
    raise ValidationError, 'email is required (cannot be blank)' if email.empty?
    raise ValidationError, "email '#{email}' does not look like a valid address" unless email.match?(EMAIL_RE)
  end

  def validate_country_code!(country_code)
    cc = country_code.to_s
    return if cc.empty? || cc.length == 2

    raise ValidationError, "country_code must be a 2-letter ISO code (got '#{cc}')"
  end

  # Pull the conflicting column out of the PG error so the operator
  # sees "website 'pixelcatcher.de' is already used by another
  # photographer" instead of a raw stack trace.
  def friendly_unique_message(error)
    m = error.message.match(/Key \((?<col>[^)]+)\)=\((?<val>[^)]+)\) already exists/)
    if m
      "value '#{m[:val]}' for #{m[:col]} is already used by another photographer in the directory"
    else
      "directory rejected the write — value conflicts with another photographer (#{error.message.truncate(120)})"
    end
  end

  # photographer_directory has a websites_domain_fk on photographer_photographers.website
  # — i.e. the value must already exist as a row in the `websites`
  # table before we can point a photographer at it. Same pattern may
  # apply to other look-up'd columns down the line.
  def friendly_fk_message(error)
    m = error.message.match(/Key \((?<col>[^)]+)\)=\((?<val>[^)]+)\) is not present/)
    if m
      col = m[:col]
      val = m[:val]
      if col == 'website'
        "Domena '#{val}' nie jest zarejestrowana w tabeli websites photographer-directory. " \
          'Dodaj ją najpierw w directory UI, dopiero potem przypisz fotografowi tutaj.'
      else
        "Wartość '#{val}' dla #{col} nie istnieje w referenced table — dodaj ją najpierw w directory."
      end
    else
      "directory FK constraint blocked the write — referenced row does not exist (#{error.message.truncate(120)})"
    end
  end

  def find_source!
    source = ::PhotographerDirectory::Photographer.find_by(id: profile.external_id)
    raise PhotographerNotFound, "directory row missing for external_id=#{profile.external_id}" unless source

    source
  end

  def previous_values(source, attrs)
    attrs.keys.index_with { |k| source.public_send(k).to_s }.transform_keys(&:to_s)
  end

  def diff(prev, new_values)
    new_values.each_with_object({}) do |(k, v), acc|
      old = prev[k.to_s].to_s
      new_str = v.to_s
      acc[k.to_s] = { from: old, to: new_str } if old != new_str
    end
  end

  def record_audit!(previous:, new_values:)
    participant = last_participant_for(profile)
    return unless participant

    participant.attribution_events.create!(
      event_type: 'profile_edit',
      occurred_at: Time.current,
      payload: {
        'applied_by' => 'profile_writer',
        'operator_user_id' => user&.id,
        'previous' => previous,
        'new' => new_values.transform_keys(&:to_s).transform_values(&:to_s)
      }
    )
  rescue StandardError => e
    Rails.logger.warn("[outreach.profile_writer] audit log failed: #{e.class}: #{e.message}")
  end

  def last_participant_for(profile)
    CampaignParticipant
      .where(participatable: profile, account: profile.account)
      .order(created_at: :desc)
      .first
  end
end
