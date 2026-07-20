class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  def display_name
    local_part = email.to_s.split("@").first.to_s
    return "User" if local_part.blank?

    local_part.tr("._-", " ").squish.titleize
  end
end
