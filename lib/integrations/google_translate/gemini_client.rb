# Translates and detects language with Gemini on Vertex AI, reusing the
# service account stored on the google_translate hook. Replaces Cloud
# Translation NMT ($20 / 1M chars) with Flash (~$0.85 / 1M chars). Flash-Lite
# was cheaper but mistranslated "Rahmen" (frame) as bike/picture.
# The service account needs the Vertex AI User role and the Vertex AI API
# enabled on the hook's project.
class Integrations::GoogleTranslate::GeminiClient
  MODEL = 'gemini-2.5-flash'.freeze
  SCOPE = 'https://www.googleapis.com/auth/cloud-platform'.freeze
  LANGUAGE_FORMAT = 'Language codes are BCP-47 as used by Google Translate, lowercase primary subtag (e.g. en, pl, de, pt-BR, zh-CN).'.freeze

  TRANSLATE_PROMPT = <<~PROMPT.freeze
    You translate customer support emails for Framky, an online shop selling custom photo frames and framed prints.
    Translate the user's text into the target language given below.
    Keep the meaning, tone, names, numbers, URLs, email addresses and line breaks. Output plain text, no markdown.
    If the text is already in the target language, return it unchanged.
    Also report the language the original text is written in.
    #{LANGUAGE_FORMAT}
  PROMPT

  DETECT_PROMPT = <<~PROMPT.freeze
    Detect the language the user's text is written in.
    #{LANGUAGE_FORMAT}
  PROMPT

  pattr_initialize [:hook!]

  # Returns { 'language' => detected source language, 'translation' => text in target_language }
  def translate(text, target_language)
    generate(
      "#{TRANSLATE_PROMPT}\nTarget language: #{target_language}",
      text,
      { language: { type: 'STRING' }, translation: { type: 'STRING' } }
    )
  end

  def detect_language(text)
    generate(DETECT_PROMPT, text, { language: { type: 'STRING' } })['language']
  end

  private

  def generate(system_prompt, text, properties)
    body = {
      systemInstruction: { parts: [{ text: system_prompt }] },
      contents: [{ role: 'user', parts: [{ text: text }] }],
      generationConfig: {
        temperature: 0,
        thinkingConfig: { thinkingBudget: 0 },
        responseMimeType: 'application/json',
        responseSchema: { type: 'OBJECT', properties: properties, required: properties.keys }
      }
    }
    response = connection.post(endpoint, body.to_json)
    JSON.parse(response.body.dig('candidates', 0, 'content', 'parts', 0, 'text'))
  end

  def endpoint
    "https://aiplatform.googleapis.com/v1/projects/#{hook.settings['project_id']}/locations/global/publishers/google/models/#{MODEL}:generateContent"
  end

  def connection
    Faraday.new(headers: { 'Authorization' => "Bearer #{access_token}", 'Content-Type' => 'application/json' }) do |f|
      f.response :raise_error
      f.response :json
    end
  end

  def access_token
    Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(hook.settings['credentials'].to_json),
      scope: SCOPE
    ).fetch_access_token!['access_token']
  end
end
