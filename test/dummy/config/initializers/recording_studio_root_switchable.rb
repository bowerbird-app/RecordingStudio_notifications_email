# frozen_string_literal: true

route_is_internal = lambda do |path|
  [
    Rails.application.routes,
    RecordingStudioRootSwitchable::Engine.routes
  ].any? do |route_set|
    route_set.recognize_path(path, method: :get)
    true
  rescue ActionController::RoutingError
    false
  end
end

RecordingStudioRootSwitchable.configure do |config|
  config.current_actor_resolver = lambda do |controller:|
    Current.actor || controller.current_user
  end

  # String layout name. Layout.accept rejects a method Symbol such as :application_layout.
  config.layout = "flat_pack_sidebar"

  config.after_switch_redirect = lambda do |controller:, return_to:, **|
    candidate_path = return_to.presence
    candidate_path = controller.main_app.root_path if candidate_path.blank?

    route_is_internal.call(candidate_path) ? candidate_path : controller.main_app.root_path
  end

  config.scope :all_workspaces do |scope|
    scope.label = "All workspaces"
    scope.description = "Workspaces you can open."
    scope.default_root = lambda do |roots:, **|
      roots.first
    end
  end
end
