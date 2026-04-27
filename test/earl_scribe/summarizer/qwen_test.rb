# frozen_string_literal: true

require "test_helper"
require "tempfile"

module EarlScribe
  module Summarizer
    class QwenTest < Minitest::Test
      test "empty transcript returns empty string without invoking llama" do
        called = false
        Open3.stub(:capture3, lambda { |*_args|
          called = true
          ["", "", nil]
        }) do
          summary = Qwen.new(llama_bin: "/tmp/llama", model_path: "/tmp/m").call("   ")
          assert_equal "", summary
        end
        assert_not called
      end

      test "successful run returns trimmed stdout" do
        status = Object.new
        status.define_singleton_method(:success?) { true }
        Open3.stub(:capture3, ->(*_args) { ["## Summary\nAll good.\n[end of text]\n", "", status] }) do
          out = Qwen.new(llama_bin: "/tmp/llama", model_path: "/tmp/m").call("hi")
          assert_equal "## Summary\nAll good.", out
        end
      end

      test "non-zero exit raises EarlScribe::Error" do
        status = Object.new
        status.define_singleton_method(:success?) { false }
        status.define_singleton_method(:exitstatus) { 7 }
        Open3.stub(:capture3, ->(*_args) { ["", "model not found\n", status] }) do
          error = assert_raises(EarlScribe::Error) do
            Qwen.new(llama_bin: "/tmp/llama", model_path: "/tmp/m").call("transcript")
          end
          assert_includes error.message, "model not found"
          assert_includes error.message, "7"
        end
      end

      test "available? false when model path is unset" do
        EarlScribe::Config.stub(:qwen_model, nil) do
          assert_not Qwen.new.available?
        end
      end

      test "available? false when model file is missing" do
        assert_not Qwen.new(llama_bin: "/bin/sh", model_path: "/tmp/does-not-exist.gguf").available?
      end

      test "available? requires llama-cli on PATH" do
        Tempfile.create("model.gguf") do |f|
          q = Qwen.new(llama_bin: "/this/does/not/exist", model_path: f.path)
          assert_not q.available?
        end
      end

      test "build_command embeds transcript and uses configured params" do
        cmd = Qwen.new(llama_bin: "/tmp/llama", model_path: "/tmp/m",
                       n_predict: 99, ctx_size: 4096, temperature: 0.5)
                  .build_command("hello world")
        assert_equal "/tmp/llama", cmd.first
        assert_includes cmd, "/tmp/m"
        assert_includes cmd, "99"
        assert_includes cmd, "4096"
        assert_includes cmd, "0.5"
        prompt = cmd[cmd.index("-p") + 1]
        assert_includes prompt, "hello world"
        assert_includes prompt, "## Summary"
      end

      test "system_prompt reads from prompt_path when present" do
        Tempfile.create("p") do |f|
          f.write("custom prompt")
          f.flush
          q = Qwen.new(llama_bin: "x", model_path: "y", prompt_path: f.path)
          assert_equal "custom prompt", q.system_prompt
        end
      end

      test "system_prompt falls back to default when path missing" do
        q = Qwen.new(llama_bin: "x", model_path: "y", prompt_path: "/no/such/file")
        assert_includes q.system_prompt, "## Summary"
      end

      test "available? false when llama_bin is nil" do
        Tempfile.create("model.gguf") do |f|
          EarlScribe::Config.stub(:llama_bin, nil) do
            assert_not Qwen.new(model_path: f.path).available?
          end
        end
      end

      test "available? checks executable when llama_bin is an absolute path" do
        Tempfile.create("model.gguf") do |f|
          q = Qwen.new(llama_bin: "/bin/sh", model_path: f.path)
          assert q.available?
        end
      end

      test "available? returns false for absolute non-executable path" do
        Tempfile.create("model.gguf") do |f|
          Tempfile.create("not-exec") do |bin|
            File.chmod(0o644, bin.path)
            q = Qwen.new(llama_bin: bin.path, model_path: f.path)
            assert_not q.available?
          end
        end
      end

      test "unavailable_reason names the missing piece" do
        EarlScribe::Config.stub(:qwen_model, nil) do
          assert_match(/model path not set/, Qwen.new.unavailable_reason)
        end
        assert_match(/model file not found/,
                     Qwen.new(llama_bin: "/bin/sh", model_path: "/no/such/m").unavailable_reason)
        Tempfile.create("model.gguf") do |f|
          assert_nil Qwen.new(llama_bin: "/bin/sh", model_path: f.path).unavailable_reason
          assert_match(/llama-cli not found/,
                       Qwen.new(llama_bin: "/no/such/llama", model_path: f.path).unavailable_reason)
          assert_match(/llama-cli not on PATH/,
                       Qwen.new(llama_bin: "definitely-not-a-real-binary-xyz",
                                model_path: f.path).unavailable_reason)
          EarlScribe::Config.stub(:llama_bin, nil) do
            assert_match(/llama-cli path not set/,
                         Qwen.new(model_path: f.path).unavailable_reason)
          end
        end
      end

      test "error message includes signal label when process killed by signal" do
        status = Object.new
        status.define_singleton_method(:success?) { false }
        status.define_singleton_method(:exitstatus) { nil }
        status.define_singleton_method(:termsig) { 9 }
        Open3.stub(:capture3, ->(*_args) { ["", "boom\n", status] }) do
          error = assert_raises(EarlScribe::Error) do
            Qwen.new(llama_bin: "/tmp/llama", model_path: "/tmp/m").call("x")
          end
          assert_includes error.message, "signal 9"
        end
      end
    end
  end
end
