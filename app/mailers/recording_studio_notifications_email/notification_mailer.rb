# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  class NotificationMailer < ::ActionMailer::Base
    layout false

    def notification
      @event = params.fetch(:event)
      @tracked_notification_destination = params[:tracked_notification_path].presence || @event.url
      @correlation_reference = params.fetch(:correlation_reference)
      prepare_headers

      mail(message_options(subject: @event.title)) do |format|
        format.html { render template: params.fetch(:template_path) }
        format.text { render template: params.fetch(:template_path) }
      end
    end

    def rollup
      @events = params.fetch(:events)
      @cadence = params.fetch(:cadence)
      @period_starts_at = params.fetch(:period_starts_at)
      @period_ends_at = params.fetch(:period_ends_at)
      @correlation_reference = params.fetch(:correlation_reference)
      prepare_headers

      mail(message_options(subject: "#{@events.size} notifications")) do |format|
        format.html { render template: params.fetch(:template_path) }
        format.text { render template: params.fetch(:template_path) }
      end
    end

    private

    def message_options(subject:)
      {
        to: params.fetch(:to),
        from: params.fetch(:from),
        reply_to: params[:reply_to].presence,
        subject: subject
      }.compact
    end

    def prepare_headers
      headers[Correlation::HEADER] = @correlation_reference
      headers["Message-ID"] = params[:message_id] if params[:message_id]
    end

  end
end
