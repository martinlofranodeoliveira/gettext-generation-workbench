test "four acknowledged renderers remain pinned across publication; fifth never spawns" do
  workspace do |wb, _|
    first = compile_core(wb)
    tickets = []
    begin
      4.times { tickets << wb.startRenderer(locale: "pt_BR", barrier: true) }
      tickets.each(&:wait_ready)
      starts = wb.renderer_starts
      error("E_RENDER_LIMIT") { wb.startRenderer(locale: "en", barrier: true) }
      equal(starts, wb.renderer_starts)
      second = compile_core(wb, fixture("pt_BR.po").sub('"Abrir"', '"Abrir novamente"'))
      equal(2, second["generation"])
      tickets.each(&:release)
      old = tickets.map(&:finish)
      equal(["Abrir"] * 4, old.map { |r| r["verb"] })
      equal([first["id"]] * 4, old.map { |r| r["manifest_sha256"] })
      equal([1] * 4, old.map { |r| r["generation"] })
      fresh = wb.renderFixture(locale: "pt_BR")
      equal("Abrir novamente", fresh["verb"])
      equal(2, fresh["generation"])
    ensure
      tickets.each do |ticket|
        ticket.stop
        begin
          ticket.finish
        rescue W::Error
          nil
        end
      end
    end
  end
end

test "retained-anchor normal exit signals, seals, reaps and has no children" do
  workspace do |wb, _|
    wb.store.job do |job|
      result = W::Runner::Child.new("probe_normal", job).finish
      check(result.success?)
      equal("normal\n", result.stdout)
      equal(%w[term kill seal reap], result.report["events"])
      equal(true, result.report["children_empty"])
      equal(true, result.report["observed_exit"])
    end
  end
end

test "hanging nested worker is bounded and adopted descendants are reaped" do
  workspace do |wb, _|
    wb.store.job do |job|
      result = W::Runner::Child.new("probe_hang", job).finish
      check(%w[deadline stop].include?(result.report["reason"]))
      equal(%w[term kill seal reap], result.report["events"])
      equal(true, result.report["children_empty"])
      equal("nested-ready\n", result.stdout)
      check(!result.success?)
    end
  end
end

test "flood capture is bounded while cleanup continues draining" do
  workspace do |wb, _|
    wb.store.job do |job|
      result = W::Runner::Child.new("probe_flood", job).finish
      check(result.overflow)
      check(result.stdout.bytesize + result.stderr.bytesize <= 65_536)
      equal(%w[term kill seal reap], result.report["events"])
      equal(true, result.report["children_empty"])
      check(!result.success?)
    end
  end
end

test "control EOF also cleans up the owned group before reap" do
  workspace do |wb, _|
    wb.store.job do |job|
      child = W::Runner::Child.new("probe_hang", job)
      child.close_control
      result = child.finish
      equal("parent_closed", result.report["reason"])
      equal(%w[term kill seal reap], result.report["events"])
      equal(true, result.report["children_empty"])
    end
  end
end

test "package-owned resources work outside the repository working directory" do
  workspace do |wb, dir|
    source = fixture("source_v1.rb")
    pt = fixture("pt_BR.po")
    Dir.chdir(dir) do
      wb.compileGeneration(source: source, catalogs: { "pt_BR" => pt })
      equal("Abrir", wb.renderFixture(locale: "pt_BR")["verb"])
      equal("Ação", fixture("action.po").match(/msgstr "(Ação)"/)[1])
    end
  end
end


test "exec-inherited SIGCHLD ignore is reset before creating the retained anchor" do
  workspace do |wb, _|
    wb.store.job do |job|
      control_read, control_write = IO.pipe
      out_read, out_write = IO.pipe
      err_read, err_write = IO.pipe
      report_read, report_write = IO.pipe
      # The Ruby parent remains a normal reaper. Only the exec launcher sets
      # SIGCHLD=IGNORE; the real helper must observe and reset that inheritance.
      launcher = <<~PYTHON
        import os, signal, sys
        signal.signal(signal.SIGCHLD, signal.SIG_IGN)
        os.execv('/usr/bin/python3', ['/usr/bin/python3', sys.argv[1], 'probe_normal', sys.argv[2]])
      PYTHON
      env = { "PATH" => "/usr/local/bin:/usr/bin:/bin", "LANG" => "C.UTF-8",
              "LC_ALL" => "C.UTF-8", "HOME" => job,
              "GEM_HOME" => Gem.dir, "GEM_PATH" => Gem.path.join(File::PATH_SEPARATOR) }
      pid = Process.spawn(env, "/usr/bin/python3", "-c", launcher,
                          File.join(W::PACKAGE, "lib/gettext_generation_workbench/helper.py"), job,
                          3 => control_read, 4 => report_write,
                          out: out_write, err: err_write, close_others: true, unsetenv_others: true)
      [control_read, out_write, err_write, report_write].each(&:close)
      stdout = Thread.new { out_read.read(W::OUTPUT_LIMIT + 1) }
      stderr = Thread.new { err_read.read(W::OUTPUT_LIMIT + 1) }
      report = Thread.new { report_read.read(8193) }
      _, status = Process.waitpid2(pid)
      equal(0, status.exitstatus)
      equal("normal\n", stdout.value)
      equal("", stderr.value.to_s)
      bytes = report.value
      check(bytes.bytesize <= 8192)
      value = JSON.parse(bytes)
      equal(true, value["inherited_sigchld_ignored"])
      equal(true, value["sigchld_default_before_spawn"])
      equal(true, value["observed_exit"])
      equal(true, value["children_empty"])
      equal(%w[term kill seal reap], value["events"])
    ensure
      [control_read, control_write, out_read, out_write, err_read, err_write,
       report_read, report_write].compact.each { |io| io.close unless io.closed? }
    end
  end
end
