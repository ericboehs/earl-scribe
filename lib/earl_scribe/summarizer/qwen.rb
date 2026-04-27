# frozen_string_literal: true

require "open3"

module EarlScribe
  module Summarizer
    class Qwen
      DEFAULT_PROMPT = <<~PROMPT
        You are summarizing an in-progress meeting transcript. Produce a concise
        markdown brief with the following sections, in this order:

        ## Summary
        2-4 sentences describing what's happening.

        ## Decisions
        - Bulleted list of decisions made so far. If none, write "None yet."

        ## Action Items
        - Bulleted list of action items with owner if known. If none, write "None yet."

        ## Open Questions
        - Bulleted list of unresolved questions. If none, write "None yet."

        Keep it terse. Do not invent content not present in the transcript.
      PROMPT

      DEFAULT_OPTIONS = { n_predict: 512, ctx_size: 8192, temperature: 0.2 }.freeze
      STDERR_TAIL_LINES = 10

      def initialize(llama_bin: nil, model_path: nil, prompt_path: nil, **opts)
        params = DEFAULT_OPTIONS.merge(opts)
        @llama_bin = llama_bin || Config.llama_bin
        @model_path = model_path || Config.qwen_model
        @prompt_path = prompt_path || Config.summary_prompt_path
        @n_predict = params[:n_predict]
        @ctx_size = params[:ctx_size]
        @temperature = params[:temperature]
      end

      def available?
        return false unless @model_path && File.exist?(@model_path)
        return false unless @llama_bin

        return File.executable?(@llama_bin) if @llama_bin.include?("/")

        system("which", @llama_bin, out: File::NULL, err: File::NULL) || false
      end

      def unavailable_reason
        return "model path not set (set EARL_SCRIBE_QWEN_MODEL or run bin/build-qwen)" unless @model_path
        return "model file not found at #{@model_path}" unless File.exist?(@model_path)
        return "llama-cli path not set" unless @llama_bin
        return "llama-cli not found at #{@llama_bin}" if @llama_bin.include?("/") && !File.executable?(@llama_bin)

        on_path = system("which", @llama_bin, out: File::NULL, err: File::NULL)
        on_path ? nil : "llama-cli not on PATH (#{@llama_bin})"
      end

      def call(transcript)
        return "" if transcript.to_s.strip.empty?

        cmd = build_command(transcript)
        # nosemgrep: ruby.lang.security.dangerous-exec.dangerous-exec
        stdout, stderr, status = Open3.capture3(*cmd)
        raise Error, format_failure(status, stderr) unless status.success?

        extract_response(stdout)
      end

      def build_command(transcript)
        prompt = "#{system_prompt}\n\n# Transcript so far\n\n#{transcript}\n\n# Summary\n"
        [@llama_bin, "-m", @model_path,
         "-p", prompt,
         "-n", @n_predict.to_s,
         "-c", @ctx_size.to_s,
         "--temp", @temperature.to_s,
         "--no-display-prompt",
         "-no-cnv"]
      end

      def system_prompt
        return File.read(@prompt_path) if @prompt_path && File.exist?(@prompt_path)

        EarlScribe.logger.warn("summary prompt path #{@prompt_path.inspect} not found; using default") if @prompt_path
        DEFAULT_PROMPT
      end

      private

      def extract_response(stdout)
        stdout.sub(/\[end of text\].*\z/m, "").strip
      end

      def format_failure(status, stderr)
        exit_label = status.exitstatus || "signal #{status.termsig}"
        tail = stderr.lines.last(STDERR_TAIL_LINES).join.strip
        "llama-cli failed (#{exit_label}): #{tail}"
      end
    end
  end
end
