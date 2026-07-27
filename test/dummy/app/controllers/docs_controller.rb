# frozen_string_literal: true

require "recording_studio_notifications_email"

class DocsController < ApplicationController
  WEBHOOK_LAB_EVENTS = %w[delivered opened clicked bounced].freeze

  def install
  end

  def configuration
    render :config
  end

  def recordable_types
    RecordingStudio.validate_recordable_declarations!

    @recordable_types = RecordingStudio.recordable_declarations.values.sort_by(&:type).map do |declaration|
      normalize_recordable_declaration(declaration)
    end
  end

  def recordings_tree
    recordings = RecordingStudio::Recording.includes(:recordable).reorder(:created_at, :id).to_a
    recordings_by_parent_id = recordings.group_by(&:parent_recording_id)

    @recording_tree = recordings_by_parent_id.fetch(nil, []).map do |recording|
      build_recording_node(recording, recordings_by_parent_id)
    end
  end

  def gem_views
    prefix = "#{RecordingStudioNotificationsEmail::Engine.root}/"

    @engine_views = Dir.glob(
      RecordingStudioNotificationsEmail::Engine.root.join(
        "app/views/recording_studio_notifications_email/**/*.erb"
      ).to_s
    )
      .sort
      .map { |path| path.delete_prefix(prefix) }
  end

  def methods
  end

  def webhook_lab
    if params[:noop].present?
      session[:webhook_lab_form_defaults] = {
        "external_event_id" => params[:external_event_id].presence
      }

      redirect_to docs_webhook_lab_path
      return
    end

    load_webhook_lab_state
  end

  def create_webhook_lab_notification
    token = SecureRandom.uuid
    idempotency_key = "webhook-lab/#{current_user.id}/#{token}"

    RecordingStudioNotifications.notify(
      notification_type: :system_announcement,
      recipient: current_user,
      actor: current_user,
      title: "Webhook lab target #{token.first(8)}",
      body: "Dummy target notification for webhook callback testing.",
      channels: [:email],
      idempotency_key: idempotency_key,
      metadata: {
        source: "webhook_lab"
      }
    )

    notification = RecordingStudioNotifications::Notification.find_by(
      recipient_type: current_user.class.name,
      recipient_id: current_user.id,
      idempotency_key: idempotency_key
    )
    delivery = notification && RecordingStudioNotifications::Delivery
      .where(notification_id: notification.id, channel: :email)
      .order(created_at: :desc)
      .first

    unless notification && delivery
      redirect_to docs_webhook_lab_path,
                  alert: "Could not locate created notification or email delivery."
      return
    end

    reference = RecordingStudioNotificationsEmail::DeliveryToken.sign(
      notification: notification,
      delivery: delivery
    )

    session[:webhook_lab_target] = {
      notification_id: notification.id,
      delivery_id: delivery.id,
      created_at: Time.current.iso8601
    }

    session[:webhook_lab_last_result] = nil
    session[:webhook_lab_last_payload] = nil
    session[:webhook_lab_form_defaults] = {
      "external_event_id" => nil
    }

    redirect_to docs_webhook_lab_path,
                notice: "Created target notification #{notification.id} with delivery #{delivery.id}."
  end

  def fire_webhook_lab_event
    load_webhook_lab_classes!

    target = webhook_lab_target
    unless target
      redirect_to docs_webhook_lab_path,
                  alert: "Create a target notification first."
      return
    end

    replay = ActiveModel::Type::Boolean.new.cast(params[:repeat_last])
    payload = if replay
      webhook_lab_last_payload
    else
      build_webhook_lab_payload(target)
    end

    unless payload
      redirect_to docs_webhook_lab_path,
                  alert: "No previous webhook payload is available to replay."
      return
    end

    event_type = payload.fetch("event_type")
    unless WEBHOOK_LAB_EVENTS.include?(event_type)
      redirect_to docs_webhook_lab_path,
                  alert: "Unsupported event type '#{event_type}'."
      return
    end

    reference = signed_reference_for_target(target)
    event = RecordingStudioNotificationsEmail::WebhookEvent.new(
      **payload.merge("reference" => reference).symbolize_keys
    )

    result = ingest_webhook_lab_event!(event)

    session[:webhook_lab_last_payload] = payload
    session[:webhook_lab_form_defaults] = {
      "external_event_id" => payload["external_event_id"]
    }
    session[:webhook_lab_last_result] = {
      replayed: replay,
      event_type: result.event_type.to_s,
      payload: payload,
      idempotency_key: event.idempotency_key,
      updated_delivery_ids: result.updated_delivery_ids,
      already_applied_delivery_ids: result.already_applied_delivery_ids,
      missing_delivery_ids: result.missing_delivery_ids,
      error: nil
    }

    redirect_to docs_webhook_lab_path,
                notice: "Processed #{event_type} webhook event."
  rescue RecordingStudioNotificationsEmail::WebhookError,
         ActiveSupport::MessageVerifier::InvalidSignature,
         ArgumentError => e
    session[:webhook_lab_last_result] = {
      event_type: event_type,
      payload: payload,
      idempotency_key: nil,
      updated_delivery_ids: [],
      already_applied_delivery_ids: [],
      missing_delivery_ids: [],
      error: "#{e.class}: #{e.message}"
    }

    redirect_to docs_webhook_lab_path,
                alert: "Webhook processing failed: #{e.message}"
  end

  private

  def load_webhook_lab_state
    target = webhook_lab_target
    @webhook_lab_target = target
    @webhook_lab_last_result = session[:webhook_lab_last_result]

    @webhook_lab_notification = target && RecordingStudioNotifications::Notification.find_by(id: target["notification_id"])
    @webhook_lab_delivery = target && RecordingStudioNotifications::Delivery.find_by(id: target["delivery_id"])
    @webhook_lab_reference = @webhook_lab_notification && @webhook_lab_delivery &&
      RecordingStudioNotificationsEmail::DeliveryToken.sign(
        notification: @webhook_lab_notification,
        delivery: @webhook_lab_delivery
      )
    @webhook_lab_events = WEBHOOK_LAB_EVENTS
    @webhook_lab_last_payload = webhook_lab_last_payload

    defaults = session[:webhook_lab_form_defaults]
    defaults = defaults.stringify_keys if defaults.is_a?(Hash)
    @webhook_lab_form_defaults = {
      "external_event_id" => defaults&.fetch("external_event_id", nil)
    }
  end

  def load_webhook_lab_classes!
    require_dependency "recording_studio_notifications_email"
    require_dependency "recording_studio_notifications_email/delivery_token"
    require_dependency "recording_studio_notifications_email/delivery_callbacks"
    require_dependency "recording_studio_notifications_email/webhook_errors"
    require_dependency "recording_studio_notifications_email/webhook_event"
  end

  def ingest_webhook_lab_event!(event)
    RecordingStudioNotificationsEmail.process_webhook_event!(event: event)
  end

  def webhook_lab_target
    target = session[:webhook_lab_target]
    return unless target.is_a?(Hash)

    target.stringify_keys
  end

  def webhook_lab_last_payload
    payload = session[:webhook_lab_last_payload]
    return unless payload.is_a?(Hash)

    payload.stringify_keys
  end

  def build_webhook_lab_payload(target)
    event_type = params[:event_type].to_s
    return unless WEBHOOK_LAB_EVENTS.include?(event_type)

    {
      "provider" => "dummy",
      "event_type" => event_type,
      "occurred_at" => Time.current.iso8601(6),
      "external_event_id" => params[:external_event_id].presence,
      "metadata" => {
        "source" => "dummy_webhook_lab"
        }
    }
  end

  def signed_reference_for_target(target)
    notification = RecordingStudioNotifications::Notification.find_by(id: target.fetch("notification_id"))
    delivery = RecordingStudioNotifications::Delivery.find_by(id: target.fetch("delivery_id"))
    raise ArgumentError, "webhook lab target notification was not found" unless notification
    raise ArgumentError, "webhook lab target delivery was not found" unless delivery

    RecordingStudioNotificationsEmail::DeliveryToken.sign(
      notification: notification,
      delivery: delivery
    )
  end

  def normalize_recordable_declaration(declaration)
    {
      name: declaration.type,
      label: declaration.label,
      root: declaration.root?,
      allowed_parent_types: RecordingStudio.allowed_parent_types_for(declaration.type),
      recordings_count: RecordingStudio::Recording.where(recordable_type: declaration.type).count,
      recordables_count: count_recordables_for(declaration.type)
    }
  end

  def count_recordables_for(type_name)
    recordable_class = type_name.safe_constantize
    return 0 unless recordable_class&.<= ActiveRecord::Base
    return 0 unless recordable_class.table_exists?

    recordable_class.count
  rescue ActiveRecord::ActiveRecordError
    0
  end

  def build_recording_node(recording, recordings_by_parent_id)
    {
      label: recording_label(recording),
      children: recordings_by_parent_id.fetch(recording.id, []).map do |child_recording|
        build_recording_node(child_recording, recordings_by_parent_id)
      end
    }
  end

  def recording_label(recording)
    type_label = recording.recordable_type.to_s.demodulize.underscore.humanize
    identifier = recordable_identifier(recording.recordable)

    "#{type_label}: #{identifier}"
  end

  def recordable_identifier(recordable)
    return "Unknown recordable" if recordable.nil?

    %i[name title email label slug identifier].each do |attribute|
      next unless recordable.respond_to?(attribute)

      value = recordable.public_send(attribute)
      return value if value.present?
    end

    actor = recordable.actor if recordable.respond_to?(:actor)
    actor_email = actor.email if actor&.respond_to?(:email) && actor.email.present?

    if recordable.respond_to?(:role) && recordable.role.present? && actor_email.present?
      return "#{recordable.role.to_s.humanize} for #{actor_email}"
    end

    return recordable.role.to_s.humanize if recordable.respond_to?(:role) && recordable.role.present?

    return recordable.minimum_role.to_s.humanize if recordable.respond_to?(:minimum_role) &&
      recordable.minimum_role.present?

    "##{recordable.id}"
  end
end
