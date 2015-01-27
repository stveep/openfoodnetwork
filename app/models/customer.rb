class Customer < ActiveRecord::Base
  belongs_to :enterprise
  attr_accessible # none yet
end
