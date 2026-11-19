# frozen_string_literal: true

module RecordingStudioNotificationsEmail
  module ReplyBody
    WROTE = /^on .+ wrote:\s*$/i
    ORIGINAL = /^-{2,}\s*original message\s*-{2,}\s*$/i
    OUTLOOK = /^from:\s.+\n\s*sent:\s/i
    def self.extract(mail)
      text = plain_text(mail).to_s.gsub("\r\n", "\n")
      text = cut_signature(text)
      text = cut_pattern(text, WROTE)
      text = cut_pattern(text, ORIGINAL)
      text = cut_outlook(text)
      text.lines.reject { |line| quoted_line?(line) }.join.strip
    end

    def self.plain_text(mail)
      plain = part_text(mail.text_part)
      return plain if plain.present?

      html = part_text(mail.html_part)
      return html_to_text(html) if html.present?
      return "" if mail.multipart?

      mail.decoded.to_s
    end

    def self.part_text(part)
      part&.decoded.to_s
    end
    private_class_method :part_text

    def self.html_to_text(html)
      require "loofah"
      fragment = Loofah.fragment(html.to_s)
      fragment.css("script, style, blockquote").each(&:remove)
      fragment.css("br").each { |node| node.replace("\n") }
      fragment.css("p, div, li, tr").each { |node| node.add_child("\n") }
      fragment.text
    end
    private_class_method :html_to_text

    def self.cut_signature(text)
      lines = text.lines
      index = lines.index { |line| line.strip == "--" }
      return text unless index

      lines.take(index).join
    end
    private_class_method :cut_signature

    def self.cut_pattern(text, pattern)
      lines = text.lines
      index = lines.index { |line| line.strip.match?(pattern) }
      return text unless index

      lines.take(index).join
    end
    private_class_method :cut_pattern

    def self.cut_outlook(text)
      match = text.match(OUTLOOK)
      return text unless match

      text.byteslice(0, match.begin(0)).to_s
    end
    private_class_method :cut_outlook

    def self.quoted_line?(line)
      line.lstrip.start_with?(">")
    end
    private_class_method :quoted_line?
  end
end
