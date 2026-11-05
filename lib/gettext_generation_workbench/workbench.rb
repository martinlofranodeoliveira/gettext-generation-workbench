module GettextGenerationWorkbench
  class Workbench
    attr_reader :store

    def initialize(root)
      @store = Store.new(root)
      @slots = Mutex.new
      @renderers = 0
      @renderer_starts = 0
      @qualification_lock = Mutex.new
    end

    def renderer_starts
      @slots.synchronize { @renderer_starts }
    end

    def qualify
      @qualification_lock.synchronize do
        return @toolchain if @toolchain
        GettextGenerationWorkbench.fail!("E_RUNTIME") unless RUBY_VERSION == "3.4.12" &&
          Gem.loaded_specs.fetch("gettext").version.to_s == "3.5.2"
        versions = {}
        store.job do |job|
          %w[msgfmt msgmerge msgunfmt msgattrib].each do |tool|
            line = Runner.run("version_#{tool}", job).stdout.lines.first.to_s.strip
            GettextGenerationWorkbench.fail!("E_RUNTIME") unless line == "#{tool} (GNU gettext-tools) 0.21"
            versions[tool] = "0.21"
          end
        end
        @toolchain = { "ruby" => RUBY_VERSION, "gettext_gem" => "3.5.2",
                       "python" => "3.11.2", "gnu" => versions }
      end
    end

    def extract(source:)
      GettextGenerationWorkbench.safe("E_EXTRACTION") do
        GettextGenerationWorkbench.inputs!(source)
        source = GettextGenerationWorkbench.text(source)
        qualify
        store.job do |job|
          File.write(File.join(job, "source.rb"), source)
          Runner.run("extract", job)
          result = Catalog.normalize_extraction(File.join(job, "messages.pot"))
          GettextGenerationWorkbench.inputs!(result)
          result
        end
      end
    end

    def merge(catalog:, template:, locale:)
      GettextGenerationWorkbench.safe("E_MERGE") do
        GettextGenerationWorkbench.locale!(locale)
        GettextGenerationWorkbench.inputs!(catalog, template)
        qualify
        store.job do |job|
          old = Catalog.normalize(catalog, locale, job)
          File.write(File.join(job, "old.po"), old)
          pot = Catalog.normalize(template, "en", job)
          File.write(File.join(job, "messages.pot"), pot)
          Runner.run("merge", job)
          evidence = GettextGenerationWorkbench.text(GettextGenerationWorkbench.read(File.join(job, "merged.po")))
          normalized = Catalog.normalize(evidence, locale, job)
          { "po" => normalized, "evidence" => evidence, "counts" => Catalog.counts(job) }
        end
      end
    end

    def compileGeneration(source:, catalogs:)
      GettextGenerationWorkbench.safe("E_COMPILE") do
        GettextGenerationWorkbench.fail!("E_CATALOG_LIMIT") unless catalogs.is_a?(Hash) && catalogs.size.between?(1, 16)
        catalogs.keys.each { |locale| GettextGenerationWorkbench.locale!(locale) }
        GettextGenerationWorkbench.inputs!(source, *catalogs.values)
        source = GettextGenerationWorkbench.text(source)
        store.writer do
          toolchain = qualify
          # Extraction is also a required successful phase of compilation.
          pot = extract(source: source)
          store.job do |job|
            payload = File.join(job, "payload")
            Dir.mkdir(payload, 0o700)
            File.write(File.join(payload, "source.rb"), source)
            File.write(File.join(payload, "messages.pot"), pot)
            reports = {}
            total_normalized = source.bytesize
            catalogs.keys.sort.each do |locale|
              normalized = Catalog.normalize(catalogs.fetch(locale), locale, job)
              total_normalized += normalized.bytesize
              GettextGenerationWorkbench.fail!("E_INPUT_LIMIT") if total_normalized > INPUT_LIMIT
              counts = Catalog.counts(job)
              mo = GettextGenerationWorkbench.read(File.join(job, "catalog.mo"))
              # The same literal guard used by the worker also checks compiled output.
              Header.guard_mo!(GetText::MO.open(File.join(job, "catalog.mo"), "UTF-8"), locale)
              locale_dir = File.join(payload, "locale", locale, "LC_MESSAGES")
              FileUtils.mkdir_p(locale_dir, mode: 0o700)
              File.write(File.join(locale_dir, "fixture.mo"), mo, mode: "wb")
              po_dir = File.join(payload, "po")
              Dir.mkdir(po_dir, 0o700) unless File.directory?(po_dir)
              File.write(File.join(po_dir, "#{locale}.po"), normalized)
              reports[locale] = { "po_sha256" => GettextGenerationWorkbench.sha(normalized),
                                  "mo_sha256" => GettextGenerationWorkbench.sha(mo), "counts" => counts }
            end
            manifest = {
              "format" => 1, "version" => VERSION, "toolchain" => toolchain,
              "source_sha256" => GettextGenerationWorkbench.sha(source),
              "pot_sha256" => GettextGenerationWorkbench.sha(pot), "catalogs" => reports,
              "policy" => { "fuzzy" => "untranslated", "charset" => "UTF-8",
                            "plural" => "nplurals=2; plural=(n != 1);" }
            }
            store.publish(payload, manifest, job)
          end
        end
      end
    end

    def snapshot_mo(job, locale)
      GettextGenerationWorkbench.locale!(locale)
      pointer, manifest, directory = store.active
      record = manifest.fetch("catalogs")[locale]
      GettextGenerationWorkbench.fail!("E_LOCALE") unless record
      bytes = GettextGenerationWorkbench.read(File.join(directory, "locale", locale, "LC_MESSAGES", "fixture.mo"))
      GettextGenerationWorkbench.fail!("E_INTEGRITY") unless GettextGenerationWorkbench.sha(bytes) == record["mo_sha256"]
      [pointer, manifest, bytes]
    end

    def inspectGeneration(locale:)
      GettextGenerationWorkbench.safe("E_INSPECTION") do
        qualify
        store.job do |job|
          pointer, manifest, bytes = snapshot_mo(job, locale)
          File.binwrite(File.join(job, "catalog.mo"), bytes)
          Runner.run("inspect", job)
          inspected = GettextGenerationWorkbench.text(GettextGenerationWorkbench.read(File.join(job, "inspected.po")))
          { "generation" => pointer["generation"], "id" => pointer["id"],
            "counts" => manifest.fetch("catalogs").fetch(locale).fetch("counts"),
            "mo_active" => Catalog.active(Catalog.parse(File.join(job, "inspected.po"))).length,
            "po" => inspected }
        end
      end
    end

    def startRenderer(locale:, barrier: false)
      GettextGenerationWorkbench.safe("E_RENDER") do
        @slots.synchronize do
          GettextGenerationWorkbench.fail!("E_RENDER_LIMIT") if @renderers >= 4
          @renderers += 1
        end
        reserved = true
        qualify
        job = store.new_job
        pointer, _manifest, bytes = snapshot_mo(job, locale)
        directory = File.join(job, "locale", locale, "LC_MESSAGES")
        FileUtils.mkdir_p(directory, mode: 0o700)
        mo = File.join(directory, "fixture.mo")
        File.binwrite(mo, bytes)
        File.chmod(0o400, mo)
        [directory, File.dirname(directory), File.join(job, "locale")].each { |d| File.chmod(0o500, d) }
        config = pointer.merge("locale" => locale, "barrier" => !!barrier,
                               "mo_sha256" => GettextGenerationWorkbench.sha(bytes))
        File.write(File.join(job, "render.json"), GettextGenerationWorkbench.canonical(config))
        child = Runner::Child.new("render", job)
        @slots.synchronize { @renderer_starts += 1 }
        ticket = Ticket.new(self, job, child, pointer)
        reserved = false
        ticket
      ensure
        if reserved
          store.cleanup(job) if job
          @slots.synchronize { @renderers -= 1 }
        end
      end
    end

    def renderFixture(locale:)
      startRenderer(locale: locale).finish
    end

    def renderer_finished(job)
      store.cleanup(job)
    ensure
      @slots.synchronize { @renderers -= 1 }
    end
  end

  class Ticket
    def initialize(workbench, job, child, pointer)
      @workbench, @job, @child, @pointer = workbench, job, child, pointer
      @finished = false
    end

    def wait_ready
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3.0
      until File.file?(File.join(@job, "ready"))
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
          @child.stop
          raise Error, "E_BARRIER"
        end
        sleep 0.005
      end
      ack = JSON.parse(GettextGenerationWorkbench.read(File.join(@job, "ready"), 4096))
      GettextGenerationWorkbench.fail!("E_BARRIER") unless ack == @pointer
      self
    end

    def release
      File.write(File.join(@job, "release"), "go\n")
      self
    end

    def stop
      @child.stop unless @finished
    end

    def finish
      GettextGenerationWorkbench.fail!("E_RENDER") if @finished
      result = @child.finish
      GettextGenerationWorkbench.fail!("E_CHILD_OUTPUT") if result.overflow
      GettextGenerationWorkbench.fail!("E_RENDER") unless result.success?
      value = JSON.parse(result.stdout)
      GettextGenerationWorkbench.fail!("E_INTEGRITY") unless value["generation"] == @pointer["generation"] &&
        value["manifest_sha256"] == @pointer["id"]
      value
    rescue JSON::ParserError
      raise Error, "E_RENDER"
    ensure
      unless @finished
        @finished = true
        @workbench.renderer_finished(@job)
      end
    end
  end
end
