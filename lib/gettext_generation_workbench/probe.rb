# Fixed lifecycle probes, never selected by catalog/source content.
case ARGV.fetch(0)
when "normal"
  pid = fork { exit! 0 }
  Process.wait(pid)
  STDOUT.write("normal\n")
when "hang"
  fork { loop { sleep 60 } }
  STDOUT.sync = true
  STDOUT.write("nested-ready\n")
  loop { sleep 60 }
when "flood"
  STDOUT.sync = true
  loop { STDOUT.write("x" * 4096) }
else
  exit 2
end
