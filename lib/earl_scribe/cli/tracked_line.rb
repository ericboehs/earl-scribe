# frozen_string_literal: true

module EarlScribe
  module Cli
    # A previously displayed transcript line with its associated speaker cache keys.
    TrackedLine = Struct.new(:text, :cache_keys, keyword_init: true) do
      def matches?(cache_key, name)
        cache_keys.include?(cache_key) && text.include?(name)
      end
    end
  end
end
