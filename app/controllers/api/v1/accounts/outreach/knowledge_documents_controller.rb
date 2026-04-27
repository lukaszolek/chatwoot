# Operator-facing CRUD for the campaign knowledge base. Documents
# (kind: goal | product | program_rules | faq | tone | open_issues |
# custom) are consumed by Outreach::Llm::MessageComposer::* via
# OutboundCampaign#knowledge_dump(locale:).
class Api::V1::Accounts::Outreach::KnowledgeDocumentsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :campaign
  before_action :document, only: [:update, :destroy]

  def index
    @documents = @campaign.knowledge_documents.order(:kind, :position, :id)
  end

  def create
    @document = @campaign.knowledge_documents.create!(document_params)
    render :show, status: :created
  end

  def update
    @document.update!(document_params)
    render :show
  end

  def destroy
    @document.destroy!
    head :no_content
  end

  private

  def campaign
    @campaign ||= Current.account.outbound_campaigns.find(params[:campaign_id])
  end

  def document
    @document ||= @campaign.knowledge_documents.find(params[:id])
  end

  def document_params
    params.require(:campaign_knowledge_document)
          .permit(:kind, :title, :content, :locale, :position, :active)
  end

  def check_authorization
    authorize(OutboundCampaign)
  end
end
