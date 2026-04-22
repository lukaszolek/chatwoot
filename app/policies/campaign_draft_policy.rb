class CampaignDraftPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def update?
    index?
  end

  def approve?
    index?
  end

  def reject?
    index?
  end
end
