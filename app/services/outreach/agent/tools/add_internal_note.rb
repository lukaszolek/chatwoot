class Outreach::Agent::Tools::AddInternalNote < Outreach::Agent::Tools::Base
  description <<~DESC
    Appends an internal note to the photographer's profile (visible only
    to operators). Use to capture context that doesn't fit a status
    transition — e.g. "asked to be contacted again in Q3", "mentioned a
    wedding-photographer collective they're part of".
  DESC

  param :sender_email, desc: 'Email of the photographer who sent the inbound', required: true
  param :content, desc: 'Free-form note; will be stamped with timestamp + agent prefix', required: true

  def execute!(profile:, content:, **_params)
    stamped = "[#{Time.current.iso8601}] [agent] #{content.to_s.truncate(2000)}"
    new_notes = [profile.notes.to_s.strip, stamped].reject(&:empty?).join("\n\n")
    profile.update!(notes: new_notes)
    { ok: true, profile_id: profile.id, note_appended_chars: stamped.length }
  end
end
