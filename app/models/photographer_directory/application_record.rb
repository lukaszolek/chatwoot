# Abstract base for read + write-limited-scope access to the
# photographer-directory secondary database. All concrete models must
# inherit from this class — direct AR access to the secondary connection
# is not allowed.
class PhotographerDirectory::ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  connects_to database: { reading: :photographer_directory, writing: :photographer_directory }
end
