require "net/http"

class AdcraftTaskClient
  DEFAULT_ENDPOINT = "http://adcraft-web:5001/api/generate"

  class Error < StandardError; end

  def self.enqueue_report_media!(report)
    new.enqueue_report_media!(report)
  end

  def initialize(endpoint: ENV.fetch("ADCRAFT_TASKS_ENDPOINT", DEFAULT_ENDPOINT))
    @uri = URI(endpoint)
  end

  def enqueue_report_media!(report)
    request = Net::HTTP::Post.new(@uri, "Content-Type" => "application/json")
    request.body = payload_for(report).to_json

    response = Net::HTTP.start(@uri.hostname, @uri.port, use_ssl: @uri.scheme == "https") do |http|
      http.request(request)
    end

    raise Error, response.body.presence || "AdCraft request failed" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError
    { "status" => "success" }
  rescue StandardError => e
    raise Error, e.message
  end

  private

  def payload_for(report)
    {
      script_text: report.content.to_s,
      topic: "#{report.game.display_name}: #{report.title}",
      tenant_name: "g9",
      content_types: [ "shorts" ],
      options: {
        skip_seo: false,
        skip_brand: false,
        generate_tts: false,
        generate_card_news: false
      }
    }
  end
end
