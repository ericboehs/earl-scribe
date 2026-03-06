# frozen_string_literal: true

module EarlScribe
  module Audio
    # Plays audio segments from M4A files via ffplay, skippable with Enter
    module Player
      def self.play_segment(m4a_path, start_time, end_time)
        duration = end_time - start_time
        pid = spawn("ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet",
                    "-ss", start_time.to_s, "-t", duration.to_s, m4a_path)
        wait_for_input_or_exit(pid)
      end

      def self.wait_for_input_or_exit(pid)
        done = Queue.new
        wait_thread = spawn_wait_thread(pid, done)
        input_thread = spawn_input_thread(done)
        done.pop
        kill_process(pid)
        wait_thread.join(1)
        input_thread.kill
      end

      def self.spawn_wait_thread(pid, done)
        Thread.new do
          Process.wait2(pid)
          done.push(:process)
        rescue StandardError
          nil
        end
      end

      def self.spawn_input_thread(done)
        Thread.new do
          $stdin.gets
          done.push(:input)
        rescue StandardError
          nil
        end
      end

      def self.kill_process(pid)
        Process.kill("TERM", pid)
      rescue Errno::ESRCH
        nil
      end

      private_class_method :wait_for_input_or_exit, :spawn_wait_thread,
                           :spawn_input_thread, :kill_process
    end
  end
end
