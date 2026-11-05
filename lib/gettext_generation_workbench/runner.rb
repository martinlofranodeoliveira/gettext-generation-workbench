module GettextGenerationWorkbench
  module Runner
    Result = Struct.new(:stdout, :stderr, :report, :overflow, keyword_init: true) do
      def success?
        !overflow && report["reason"] == "exit" && report["exit"] == 0 &&
          report["children_empty"] == true && report["events"] == %w[term kill seal reap]
      end
    end

    class Child
      def initialize(profile, job)
        GettextGenerationWorkbench.fail!("E_RUNTIME") unless RbConfig.ruby == "/usr/local/bin/ruby"
        control_read, @control = IO.pipe
        out_read, out_write = IO.pipe
        err_read, err_write = IO.pipe
        report_read, report_write = IO.pipe
        @mutex = Mutex.new
        @data = { stdout: +"".b, stderr: +"".b }
        @size = 0
        @overflow = false
        @done = false
        @stopped = false
        env = {
          "PATH" => "/usr/local/bin:/usr/bin:/bin", "LANG" => "C.UTF-8",
          "LC_ALL" => "C.UTF-8", "HOME" => job,
          "GEM_HOME" => Gem.dir, "GEM_PATH" => Gem.path.join(File::PATH_SEPARATOR)
        }
        @pid = Process.spawn(env, "/usr/bin/python3", File.join(__dir__, "helper.py"),
                             profile, job, 3 => control_read, 4 => report_write,
                             out: out_write, err: err_write, close_others: true,
                             unsetenv_others: true)
        [control_read, out_write, err_write, report_write].each(&:close)
        @readers = [capture(out_read, :stdout), capture(err_read, :stderr)]
        @report_thread = Thread.new do
          begin
            @report_bytes = report_read.read(8193)
          ensure
            report_read.close
          end
        end
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @watchdog = Thread.new do
          loop do
            break if @mutex.synchronize { @done }
            if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= 5.0
              stop
              break
            end
            sleep 0.01
          end
        end
      rescue StandardError
        [control_read, @control, out_read, out_write, err_read, err_write,
         report_read, report_write].compact.each { |io| io.close unless io.closed? }
        raise Error, "E_CHILD_START"
      end

      def capture(io, key)
        Thread.new do
          begin
            loop do
              chunk = io.readpartial(4096)
              overflow = @mutex.synchronize do
                room = [OUTPUT_LIMIT - @size, 0].max
                @data[key] << chunk.byteslice(0, room) if room.positive?
                @size += chunk.bytesize
                @overflow = true if @size > OUTPUT_LIMIT
                @overflow
              end
              stop if overflow
            end
          rescue EOFError, IOError
            nil
          ensure
            io.close unless io.closed?
          end
        end
      end

      def stop
        @mutex.synchronize do
          return if @stopped
          @stopped = true
          begin
            @control.write("STOP\n") unless @control.closed?
          rescue IOError, Errno::EPIPE
            nil
          end
        end
      end

      def close_control
        @mutex.synchronize { @control.close unless @control.closed? }
      end

      def finish
        return @result if @result
        Process.waitpid(@pid) # Only the helper, never its retained child anchor.
        @mutex.synchronize { @done = true }
        @watchdog.join
        @readers.each(&:join)
        @report_thread.join
        close_control
        GettextGenerationWorkbench.fail!("E_CHILD_REPORT") unless @report_bytes && @report_bytes.bytesize <= 8192
        report = JSON.parse(@report_bytes)
        GettextGenerationWorkbench.fail!("E_RUNTIME") unless report["python"] == "3.11.2"
        @result = Result.new(stdout: @data[:stdout], stderr: @data[:stderr], report: report,
                             overflow: @overflow)
      rescue JSON::ParserError, Errno::ECHILD
        raise Error, "E_CHILD_REPORT"
      ensure
        @mutex.synchronize { @done = true }
      end
    end

    def self.run(profile, job)
      result = Child.new(profile, job).finish
      GettextGenerationWorkbench.fail!("E_CHILD_OUTPUT") if result.overflow
      GettextGenerationWorkbench.fail!("E_CHILD_TIMEOUT") if result.report["reason"] == "deadline"
      GettextGenerationWorkbench.fail!("E_TOOL") unless result.success?
      result
    end
  end
end
