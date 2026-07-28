# frozen_string_literal: true

# Keep the notifications index scope aligned with the top-nav bell menu.
# The menu endpoint always uses "all", while upstream index defaults to
# current-root. This patch makes the page default to "all" in the dummy app.
Rails.application.config.to_prepare do
  next unless defined?(RecordingStudioNotifications::NotificationsController)

  RecordingStudioNotifications::NotificationsController.class_eval do
    private

    def notifications_inbox_scope
      requested_scope = params[:inbox_scope].to_s
      return requested_scope if %w[all current_root].include?(requested_scope)

      "all"
    end
  end
end
