# frozen_string_literal: true

require "open3"
require "json"

module EarlScribe
  # Queries the ical CLI for the current meeting to embed in transcript metadata
  module Calendar
    DEPRIORITIZED_STATUSES = [3, 4].freeze # declined, tentative
    DEPRIORITIZED_AVAILABILITY = %w[free].freeze

    def self.current_meeting
      calendars = Config.calendar_names
      return unless calendars

      cmd = ["ical", "list", "-f", "30 minutes ago", "-t", "in 30 minutes", "--output", "json"]
      calendars.each { |name| cmd.push("-c", name) }
      stdout, _stderr, status = Open3.capture3(*cmd)
      return unless status.success?

      select_best_event(stdout)
    rescue Errno::ENOENT
      nil
    end

    def self.select_best_event(json_string)
      events = JSON.parse(json_string)
      events = [events] unless events.is_a?(Array)
      candidates = events.reject { |e| e["all_day"] }
      event = best_candidate(candidates)
      return unless event

      { title: event["title"]&.strip, start_date: event["start_date"],
        end_date: event["end_date"], id: event["id"] }
    end

    def self.best_candidate(candidates)
      return candidates.first if candidates.size <= 1

      candidates.min_by { |e| [event_priority(e), e["start_date"]] }
    end

    def self.event_priority(event)
      return 1 if DEPRIORITIZED_STATUSES.include?(my_status(event))
      return 1 if DEPRIORITIZED_AVAILABILITY.include?(event["availability"])

      0
    end

    def self.my_status(event)
      cal = event["calendar"]
      (event["attendees"] || []).find { |a| a["email"] == cal }&.dig("status")
    end

    private_class_method :select_best_event, :best_candidate, :event_priority, :my_status
  end
end
