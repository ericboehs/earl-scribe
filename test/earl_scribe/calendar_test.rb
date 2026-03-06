# frozen_string_literal: true

require "test_helper"

module EarlScribe
  class CalendarTest < Minitest::Test
    test "current_meeting returns meeting hash on success" do
      json = '[{"title":"EERT Standup","start_date":"2026-03-03T13:00:00",' \
             '"end_date":"2026-03-03T13:30:00","id":"abc-123"}]'
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, [json, "", status]) do
        result = Calendar.current_meeting
        assert_equal "EERT Standup", result[:title]
        assert_equal "abc-123", result[:id]
      end
      status.verify
    end

    test "current_meeting returns nil when ical not installed" do
      Open3.stub(:capture3, ->(*_args) { raise Errno::ENOENT }) do
        assert_nil Calendar.current_meeting
      end
    end

    test "current_meeting returns nil when no events" do
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, ["[]", "", status]) do
        assert_nil Calendar.current_meeting
      end
      status.verify
    end

    test "current_meeting handles single event object instead of array" do
      json = '{"title":"Solo Event","start_date":"2026-03-03T14:00:00","end_date":"2026-03-03T14:30:00","id":"solo-1"}'
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, [json, "", status]) do
        result = Calendar.current_meeting
        assert_equal "Solo Event", result[:title]
      end
      status.verify
    end

    test "current_meeting returns nil on command failure" do
      status = Minitest::Mock.new
      status.expect(:success?, false)

      Open3.stub(:capture3, ["", "error", status]) do
        assert_nil Calendar.current_meeting
      end
      status.verify
    end

    test "current_meeting skips all-day events" do
      json = [{ "title" => "All Day", "all_day" => true, "start_date" => "2026-03-03",
                "end_date" => "2026-03-04", "id" => "ad-1" },
              { "title" => "Real Meeting", "all_day" => false, "start_date" => "2026-03-03T13:00:00",
                "end_date" => "2026-03-03T13:30:00", "id" => "rm-1" }].to_json
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, [json, "", status]) do
        result = Calendar.current_meeting
        assert_equal "Real Meeting", result[:title]
      end
      status.verify
    end

    test "current_meeting favors accepted over tentative" do
      json = [
        { "title" => "Tentative Meeting", "all_day" => false, "calendar" => "me@work.com",
          "start_date" => "2026-03-03T13:00:00", "end_date" => "2026-03-03T13:30:00", "id" => "t-1",
          "attendees" => [{ "email" => "me@work.com", "status" => 4 }] },
        { "title" => "Accepted Meeting", "all_day" => false, "calendar" => "me@work.com",
          "start_date" => "2026-03-03T13:30:00", "end_date" => "2026-03-03T14:00:00", "id" => "a-1",
          "attendees" => [{ "email" => "me@work.com", "status" => 2 }] }
      ].to_json
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, [json, "", status]) do
        result = Calendar.current_meeting
        assert_equal "Accepted Meeting", result[:title]
      end
      status.verify
    end

    test "current_meeting favors pending over tentative" do
      json = [
        { "title" => "Tentative", "all_day" => false, "calendar" => "me@work.com",
          "start_date" => "2026-03-03T13:00:00", "end_date" => "2026-03-03T13:30:00", "id" => "t-1",
          "attendees" => [{ "email" => "me@work.com", "status" => 4 }] },
        { "title" => "Pending", "all_day" => false, "calendar" => "me@work.com",
          "start_date" => "2026-03-03T13:30:00", "end_date" => "2026-03-03T14:00:00", "id" => "p-1",
          "attendees" => [{ "email" => "me@work.com", "status" => 1 }] }
      ].to_json
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, [json, "", status]) do
        result = Calendar.current_meeting
        assert_equal "Pending", result[:title]
      end
      status.verify
    end

    test "current_meeting strips whitespace from title" do
      json = '[{"title":"  Standup  ","start_date":"2026-03-03T13:00:00","end_date":"2026-03-03T13:30:00","id":"s-1"}]'
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, [json, "", status]) do
        result = Calendar.current_meeting
        assert_equal "Standup", result[:title]
      end
      status.verify
    end

    test "current_meeting handles nil title" do
      json = '[{"start_date":"2026-03-03T13:00:00","end_date":"2026-03-03T13:30:00","id":"n-1"}]'
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, [json, "", status]) do
        result = Calendar.current_meeting
        assert_nil result[:title]
      end
      status.verify
    end

    test "current_meeting handles event with no matching attendee" do
      json = [{ "title" => "Team Sync", "all_day" => false, "calendar" => "me@work.com",
                "start_date" => "2026-03-03T13:00:00", "end_date" => "2026-03-03T13:30:00", "id" => "ts-1",
                "attendees" => [{ "email" => "other@work.com", "status" => 2 }] },
              { "title" => "Accepted", "all_day" => false, "calendar" => "me@work.com",
                "start_date" => "2026-03-03T13:30:00", "end_date" => "2026-03-03T14:00:00", "id" => "a-1",
                "attendees" => [{ "email" => "me@work.com", "status" => 2 }] }].to_json
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, [json, "", status]) do
        result = Calendar.current_meeting
        assert_equal "Team Sync", result[:title]
      end
      status.verify
    end

    test "current_meeting returns nil when only all-day events" do
      json = '[{"title":"Holiday","all_day":true,"start_date":"2026-03-03","end_date":"2026-03-04","id":"h-1"}]'
      status = Minitest::Mock.new
      status.expect(:success?, true)

      Open3.stub(:capture3, [json, "", status]) do
        assert_nil Calendar.current_meeting
      end
      status.verify
    end
  end
end
