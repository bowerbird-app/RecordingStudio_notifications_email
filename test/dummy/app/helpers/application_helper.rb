module ApplicationHelper
	def recording_studio_notifications_menu(limit: 5)
		recording_studio_notifications_async_menu(recipient: current_user, limit: limit)
	end
end
