class Outreach::ConversationLabels
  LABELS = {
    draft: 'outreach_draft',
    sent: 'outreach_sent',
    replied: 'outreach_replied',
    auto_reply: 'outreach_auto_reply',
    bounced: 'outreach_bounced',
    error: 'outreach_error'
  }.freeze

  COLORS = {
    'outreach_draft' => '#f59e0b',
    'outreach_sent' => '#2563eb',
    'outreach_replied' => '#059669',
    'outreach_auto_reply' => '#7c3aed',
    'outreach_bounced' => '#dc2626',
    'outreach_error' => '#dc2626'
  }.freeze

  class << self
    def mark_draft!(conversation)
      sync!(conversation, add: [:draft], remove: [:error])
    end

    def mark_sent!(conversation)
      sync!(conversation, add: [:sent], remove: %i[draft error])
    end

    def mark_replied!(conversation)
      sync!(conversation, add: [:replied], remove: %i[draft sent auto_reply bounced])
    end

    def mark_auto_reply!(conversation)
      sync!(conversation, add: [:auto_reply], remove: %i[draft replied])
    end

    def mark_bounced!(conversation)
      sync!(conversation, add: [:bounced], remove: %i[draft replied auto_reply])
    end

    def mark_error!(conversation)
      sync!(conversation, add: [:error], remove: [])
    end

    def clear_error!(conversation)
      sync!(conversation, add: [], remove: [:error])
    end

    def clear_draft!(conversation)
      sync!(conversation, add: [], remove: [:draft])
    end

    private

    def sync!(conversation, add:, remove:)
      return unless conversation

      labels_to_add = labels_for(add)
      labels_to_remove = labels_for(remove)
      ensure_account_labels!(conversation.account, labels_to_add)

      current = Array(conversation.label_list).map(&:to_s)
      next_labels = ((current - labels_to_remove) + labels_to_add).uniq
      return if next_labels.sort == current.sort

      conversation.update!(label_list: next_labels)
    rescue StandardError => e
      Rails.logger.warn(
        "[outreach.conversation_labels] conversation=#{conversation&.id} error=#{e.class}: #{e.message}"
      )
    end

    def labels_for(keys)
      Array(keys).filter_map { |key| LABELS[key.to_sym] }
    end

    def ensure_account_labels!(account, titles)
      Array(titles).each do |title|
        account.labels.find_or_create_by!(title: title) do |label|
          label.color = COLORS.fetch(title, '#1f93ff')
          label.show_on_sidebar = true
        end
      end
    end
  end
end
