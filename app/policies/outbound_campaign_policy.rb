class OutboundCampaignPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def pause?
    @account_user.administrator?
  end

  def resume?
    @account_user.administrator?
  end

  def archive?
    @account_user.administrator?
  end

  def approve_pending?
    @account_user.administrator?
  end

  def counts?
    index?
  end
end
