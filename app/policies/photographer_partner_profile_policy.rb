class PhotographerPartnerProfilePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    index?
  end

  def update?
    index?
  end

  def opt_out?
    @account_user.administrator?
  end
end
