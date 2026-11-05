require_relative "../gettext_generation_workbench"

module GettextGenerationWorkbench
  class FixedRenderer
    include GetText

    def initialize(locale)
      bindtextdomain("fixture", path: File.expand_path("locale"), output_charset: "UTF-8")
      set_locale(locale)
    end

    def render(config)
      action = gettext("Action")
      {
        "generation" => config.fetch("generation"), "manifest_sha256" => config.fetch("id"),
        "locale" => config.fetch("locale"), "verb" => pgettext("verb", "Open"),
        "state" => pgettext("state", "Open"),
        "files" => [0, 1, 2].map { |n| ngettext("%d file", "%d files", n) % n },
        "run" => gettext("Run"), "settings" => gettext("Settings"), "action" => action,
        "action_codepoints" => action.length, "action_bytes" => action.bytesize
      }
    end
  end
end

begin
  include GettextGenerationWorkbench
  config = JSON.parse(GettextGenerationWorkbench.read("render.json", 4096))
  locale = GettextGenerationWorkbench.locale!(config.fetch("locale"))
  path = File.join("locale", locale, "LC_MESSAGES", "fixture.mo")
  bytes = GettextGenerationWorkbench.read(path)
  GettextGenerationWorkbench.fail!("E_INTEGRITY") unless GettextGenerationWorkbench.sha(bytes) == config.fetch("mo_sha256")
  mo = GetText::MO.open(path, "UTF-8")
  # This MUST precede bindtextdomain, locale lookup and every plural_as_proc call.
  Header.guard_mo!(mo, locale)
  renderer = FixedRenderer.new(locale)
  if config.fetch("barrier")
    ack = { "generation" => config.fetch("generation"), "id" => config.fetch("id") }
    File.write("ready.next", GettextGenerationWorkbench.canonical(ack))
    File.rename("ready.next", "ready")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5.0
    until File.file?("release")
      GettextGenerationWorkbench.fail!("E_BARRIER") if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      sleep 0.005
    end
  end
  STDOUT.write(JSON.generate(renderer.render(config)) + "\n")
rescue GettextGenerationWorkbench::Error => e
  STDERR.write(e.code + "\n")
  exit 2
rescue StandardError
  STDERR.write("E_RENDER\n")
  exit 2
end
