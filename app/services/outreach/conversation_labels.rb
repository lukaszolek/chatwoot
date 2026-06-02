class Outreach::ConversationLabels
  LABELS = {
    draft: 'outreach_draft',
    sent: 'outreach_sent',
    replied: 'outreach_replied',
    auto_reply: 'outreach_auto_reply',
    bounced: 'outreach_bounced',
    opt_out: 'outreach_opt_out',
    error: 'outreach_error'
  }.freeze

  COLORS = {
    'outreach_draft' => '#f59e0b',
    'outreach_sent' => '#2563eb',
    'outreach_replied' => '#059669',
    'outreach_auto_reply' => '#7c3aed',
    'outreach_bounced' => '#dc2626',
    'outreach_opt_out' => '#64748b',
    'outreach_error' => '#dc2626'
  }.freeze

  class << self
    def mark_draft!(conversation)
      sync!(conversation, add: [:draft], remove: [:error], status: :open)
    end

    def mark_sent!(conversation)
      sync!(conversation, add: [:sent], remove: %i[draft error replied auto_reply], status: :pending)
    end

    def mark_replied!(conversation)
      sync!(
        conversation,
        add: [:replied],
        remove: %i[draft sent auto_reply bounced opt_out error],
        status: :open
      )
    end

    def mark_auto_reply!(conversation, status: :pending)
      sync!(conversation, add: [:auto_reply], remove: %i[draft sent replied], status: status)
    end

    def mark_bounced!(conversation)
      sync!(conversation, add: [:bounced], remove: %i[draft sent replied auto_reply], status: :resolved)
    end

    def mark_opt_out!(conversation)
      sync!(conversation, add: [:opt_out], remove: %i[draft sent replied auto_reply bounced], status: :resolved)
    end

    def mark_error!(conversation)
      sync!(conversation, add: [:error], remove: [], status: :open)
    end

    def mark_delivery_failed!(conversation, sent_successfully:)
      remove = sent_successfully ? [] : [:sent]
      sync!(conversation, add: [:error], remove: remove, status: :open)
    end

    def clear_error!(conversation)
      sync!(conversation, add: [], remove: [:error])
    end

    def clear_draft!(conversation)
      sync!(conversation, add: [], remove: [:draft])
    end

    private

    def sync!(conversation, add:, remove:, status: nil)
      return unless conversation

      labels_to_add = labels_for(add)
      labels_to_remove = labels_for(remove)
      ensure_account_labels!(conversation.account, labels_to_add)

      current = Array(conversation.label_list).map(&:to_s)
      next_labels = ((current - labels_to_remove) + labels_to_add).uniq
      updates = updates_for(conversation, current, next_labels, status)
      return if updates.empty?

      conversation.update!(updates)
    rescue StandardError => e
      Rails.logger.warn(
        "[outreach.conversation_labels] conversation=#{conversation&.id} error=#{e.class}: #{e.message}"
      )
    end

    def labels_for(keys)
      Array(keys).filter_map { |key| LABELS[key.to_sym] }
    end

    def updates_for(conversation, current_labels, next_labels, status)
      {}.tap do |updates|
        updates[:label_list] = next_labels unless next_labels.sort == current_labels.sort
        updates[:status] = status if status && conversation.status != status.to_s
      end
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
