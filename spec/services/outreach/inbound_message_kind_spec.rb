# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Outreach::InboundMessageKind do
  def message(content:, subject: nil, from: nil)
    instance_double(
      Message,
      content: content,
      content_attributes: {
        'email' => {
          'subject' => subject,
          'from' => from
        }
      }
    )
  end

  def email_message(content:, reply:, subject: nil, from: nil)
    instance_double(
      Message,
      content: content,
      content_attributes: {
        'email' => {
          'subject' => subject,
          'from' => from,
          'text_content' => {
            'reply' => reply,
            'full' => content
          }
        }
      }
    )
  end

  it 'classifies a standalone STOP as opt-out' do
    expect(described_class.call(message(content: " STOP \n"))).to eq(:opt_out)
  end

  it 'classifies STOP from parsed email reply as opt-out' do
    content = "STOP\n\nOp di 5 mei schreef Framky:\nAls u geen berichten wilt ontvangen, antwoord STOP."

    expect(described_class.call(email_message(content: content, reply: content))).to eq(:opt_out)
  end

  it 'strips localized quoted Dutch history before classifying STOP' do
    content = "STOP\n\nOp di 5 mei schreef Framky:\nAls u geen berichten wilt ontvangen, antwoord STOP."

    expect(described_class.call(message(content: content))).to eq(:opt_out)
  end

  it 'classifies short polite STOP variants as opt-out' do
    expect(described_class.call(message(content: 'Stop aub'))).to eq(:opt_out)
  end

  it 'does not classify quoted STOP text as opt-out' do
    content = "Dank u\n\nOn Tue, Framky wrote:\nAls u geen verdere berichten wilt ontvangen, antwoord STOP."

    expect(described_class.call(message(content: content))).to eq(:reply)
  end

  it 'does not classify a question about STOP as opt-out' do
    expect(described_class.call(message(content: 'Wat betekent STOP?'))).to eq(:reply)
  end

  it 'classifies delivery failures as bounce' do
    expect(
      described_class.call(message(content: 'Address not found', from: 'mailer-daemon@example.com'))
    ).to eq(:bounce)
  end

  it 'classifies vacation notices as auto-reply' do
    expect(described_class.call(message(content: 'Ik ben afwezig tot maandag.'))).to eq(:auto_reply)
  end
end
