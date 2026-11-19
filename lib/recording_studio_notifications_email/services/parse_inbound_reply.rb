# frozen_string_literal: true

require "mail"
require "recording_studio/services/base_service"

module RecordingStudioNotificationsEmail
  module Services
    class ParseInboundReply < RecordingStudio::Services::BaseService
      CHANNEL = :email
      AUTO_PRECEDENCE = %w[bulk auto_reply list].freeze
      DMARC_PASS = /(?:\A|[;\s])dmarc\s*=\s*pass\b/i
      Disposition = Data.define(:status, :reason) do
        def processed?
          status == :processed
        end

        def rejected?
          status == :rejected
        end
      end

      def initialize(mail:, configuration: RecordingStudioNotificationsEmail.configuration)
        @mail = mail
        @configuration = configuration
      end

      private

      def perform
        disposition = build_disposition
        log_disposition(disposition)
        success(disposition)
      end

      def service_args
        { channel: CHANNEL }
      end

      def build_disposition
        reason = refusal_reason
        return rejected(reason) if reason

        submit_reply
      end

      def refusal_reason
        return :auto_reply if auto_reply?
        return :bounce if bounce?
        return :invalid_token unless token_accepted?
        return :unknown_delivery unless target
        return :from_mismatch unless from_matches?
        return :authentication_failed unless authenticated?
        return :empty_body if reply_text.blank?
        return :body_too_large if reply_text.bytesize > @configuration.reply_max_body_bytes

        attachment_problem || missing_message_id
      end

      def submit_reply
        uploaded = upload_attachments
        return rejected(uploaded) if uploaded.is_a?(Symbol)

        map_result(invoke_handler(uploaded))
      end

      def token_accepted?
        delivery_id.present? && reply_domain_matches?
      end

      def delivery_id
        return @delivery_id if defined?(@delivery_id)

        @delivery_id = reply_code ? ReplyAddress.verify(reply_code, configuration: @configuration) : nil
      end

      def reply_domain_matches?
        domain = ReplyAddress.normalized_domain(@configuration.reply_domain)
        domain.present? && reply_recipient&.fetch(:domain) == domain
      rescue ConfigurationError
        false
      end

      def target
        return @target if defined?(@target)

        @target = RecordingStudioNotifications.reply_target(delivery_id: delivery_id, channel: CHANNEL)
      end

      def from_matches?
        sender = mailbox(from_address)
        sender.present? && recipient_mailboxes.include?(sender)
      end

      def authenticated?
        return true unless @configuration.require_inbound_authentication

        authentication_results.any? { |value| trusted_dmarc_pass?(value) }
      end

      def authentication_results
        header = @mail.header if @mail.respond_to?(:header)
        return [] unless header.respond_to?(:fields)

        header.fields.filter_map do |field|
          next unless field.name.to_s.casecmp("Authentication-Results").zero?

          field.value.to_s
        end
      end

      def trusted_dmarc_pass?(value)
        id = authserv_id(value)
        id.present? && trusted_authserv_ids.include?(id) && value.match?(DMARC_PASS)
      end

      def trusted_authserv_ids
        Array(@configuration.inbound_authserv_ids).filter_map { |id| normalize_authserv_id(id) }
      end

      def authserv_id(value)
        head = value.to_s.strip.split(";", 2).first.to_s
        head = head.gsub(/\([^)]*\)/, " ")
        normalize_authserv_id(head.strip.split(/\s+/).first)
      end

      def normalize_authserv_id(value)
        value.to_s.strip.downcase.presence
      end

      def auto_reply?
        submitted = header_value("Auto-Submitted").downcase
        return true if submitted.present? && submitted != "no"
        return true if AUTO_PRECEDENCE.include?(header_value("Precedence").downcase)

        @mail.header["X-Autoreply"].present?
      end

      def bounce?
        return true if content_type_value.include?("multipart/report")
        return true if content_type_value.include?("delivery-status")
        return true if delivery_status_part?

        bounce_return_path?
      end

      def attachment_problem
        return :attachment_unreadable if attachment_read_failed?
        return :too_many_attachments if prepared_attachments.size > @configuration.reply_max_attachments
        return :attachment_too_large if attachment_too_large?
        return :active_storage_unavailable if attachments_need_storage?

        nil
      end

      def attachment_too_large?
        prepared_attachments.any? { |_part, bytes| bytes.bytesize > max_attachment_bytes }
      end

      def attachments_need_storage?
        prepared_attachments.any? && !defined?(ActiveStorage::Blob)
      end

      def missing_message_id
        :missing_message_id if idempotency_key.blank?
      end

      def upload_attachments
        prepared_attachments.map { |part, bytes| upload_blob(part, bytes) }
      rescue StandardError => e
        log_exception(:attachment_store_failed, e)
        :attachment_store_failed
      end

      def upload_blob(part, bytes)
        ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(bytes),
          filename: filename_for(part),
          content_type: content_type_for(part)
        )
      end

      def invoke_handler(blobs)
        RecordingStudioNotifications.handle_reply(
          notification: target.notification,
          recipient: target.recipient,
          body: reply_text,
          attachments: blobs,
          channel: CHANNEL,
          idempotency_key: idempotency_key
        )
      end

      def map_result(result)
        case result.respond_to?(:outcome) ? result.outcome : nil
        when :ok
          processed(nil)
        when :duplicate
          processed(:duplicate)
        when :rejected, :failed
          rejected(symbol_reason(result.reason))
        else
          rejected(:invalid_result)
        end
      end

      def reply_text
        @reply_text ||= ReplyBody.extract(@mail)
      end

      def idempotency_key
        @mail.message_id.to_s.strip.presence
      end

      def prepared_attachments
        return @prepared_attachments if defined?(@prepared_attachments)

        @attachment_read_failed = false
        @prepared_attachments = Array(@mail.attachments).map { |part| [part, part.body.decoded.to_s] }
      rescue StandardError => e
        log_exception(:attachment_unreadable, e)
        @attachment_read_failed = true
        @prepared_attachments = []
      end

      def attachment_read_failed?
        prepared_attachments
        @attachment_read_failed
      end

      def reply_recipient
        return @reply_recipient if defined?(@reply_recipient)

        @reply_recipient = candidate_addresses.filter_map { |address| reply_parts(address) }.first
      end

      def reply_code
        reply_recipient&.fetch(:code)
      end

      def candidate_addresses
        values = Array(@mail.to) + Array(@mail.cc)
        values += Array(@mail.bcc) if @mail.respond_to?(:bcc)
        values += Array(@mail.recipients) if @mail.respond_to?(:recipients)
        values.compact
      end

      def reply_parts(address)
        parsed = Mail::Address.new(address.to_s)
        local = parsed.local.to_s
        return unless local.downcase.start_with?("reply+")

        { domain: parsed.domain.to_s.downcase, code: local.split("+", 2).last.to_s }
      rescue Mail::Field::ParseError
        nil
      end

      def from_address
        Array(@mail.from).first
      end

      def recipient_mailboxes
        Array(@configuration.recipients.resolve(target.recipient)).filter_map { |address| mailbox(address) }
      rescue ArgumentError
        []
      end

      def mailbox(value)
        Mail::Address.new(value.to_s).address.to_s.downcase.presence
      rescue Mail::Field::ParseError
        nil
      end

      def header_value(name)
        @mail[name]&.value.to_s.strip
      end

      def content_type_value
        @mail.content_type.to_s.downcase
      end

      def delivery_status_part?
        return false unless @mail.respond_to?(:parts)

        Array(@mail.parts).any? { |part| part.content_type.to_s.downcase.include?("delivery-status") }
      end

      def bounce_return_path?
        field = @mail.header["Return-Path"]
        return false unless field

        raw = field.value.to_s.strip.downcase
        raw.empty? || raw == "<>" || raw.include?("mailer-daemon")
      end

      def filename_for(part)
        name = File.basename(part.filename.to_s).gsub(/[^\w.-]+/, "_")
        name = "attachment" if name.empty? || name == "." || name == ".."
        name
      end

      def content_type_for(part)
        type = part.content_type.to_s.split(";").first.to_s.strip
        type.empty? ? "application/octet-stream" : type
      end

      def max_attachment_bytes
        @configuration.reply_max_attachment_bytes
      end

      def symbol_reason(reason)
        reason.is_a?(Symbol) ? reason : :invalid_reason
      end

      def processed(reason)
        Disposition.new(status: :processed, reason: reason)
      end

      def rejected(reason)
        Disposition.new(status: :rejected, reason: symbol_reason(reason))
      end

      def log_disposition(disposition)
        logger = rails_logger
        return unless logger.respond_to?(:info)

        logger.info("recording_studio_notifications_email reply #{disposition.status} #{disposition.reason}".strip)
      end

      def log_exception(reason, error)
        logger = rails_logger
        return unless logger.respond_to?(:error)

        logger.error("recording_studio_notifications_email reply #{reason} #{error.class.name}")
      end

      def rails_logger
        return unless defined?(Rails) && Rails.respond_to?(:logger)

        Rails.logger
      end
    end
  end
end
