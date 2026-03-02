# frozen_string_literal: true

require_relative "lib/earl_scribe/version"

Gem::Specification.new do |spec|
  spec.name = "earl-scribe"
  spec.version = EarlScribe::VERSION
  spec.authors = ["Eric Boehs"]
  spec.email = ["ericboehs@gmail.com"]

  spec.summary = "Meeting transcription CLI with Deepgram streaming and whisper.cpp"
  spec.description = "EARL Scribe captures meeting audio, streams to Deepgram for real-time " \
                     "transcription with speaker diarization, or transcribes locally via " \
                     "whisper.cpp. Includes speaker identification via voiceprint matching."
  spec.homepage = "https://github.com/ericboehs/earl-scribe"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ericboehs/earl-scribe"
  spec.metadata["changelog_uri"] = "https://github.com/ericboehs/earl-scribe/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").select { |f| File.exist?(f) }.reject do |f|
      f.start_with?("test/", "docs/", ".github/", ".") && !f.start_with?(".ruby-version")
    end
  end
  spec.bindir = "exe"
  spec.executables = ["earl-scribe"]
  spec.require_paths = ["lib"]

  spec.add_dependency "websocket-client-simple", "~> 0.9"

  spec.add_development_dependency "bundler-audit", "~> 0.9"
  spec.add_development_dependency "minitest", "~> 6.0"
  spec.add_development_dependency "minitest-mock", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "reek", "~> 6.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "rubocop-rake", "~> 0.7"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
