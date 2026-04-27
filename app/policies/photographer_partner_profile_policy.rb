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

  def create?
    index?
  end

  def enroll?
    index?
  end

  def search?
    index?
  end

  def import?
    index?
  end

  def facets?
    index?
  end

  def pipeline?
    index?
  end

  # Fetching from the external Framky orders endpoint is a privileged
  # operation — it touches prod data and an outbound HTTPS call.
  def refresh_stats?
    @account_user.administrator?
  end

  def opt_out?
    @account_user.administrator?
  end
end
