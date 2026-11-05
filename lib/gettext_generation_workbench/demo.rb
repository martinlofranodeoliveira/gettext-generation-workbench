module GettextGenerationWorkbench
  module Demo
    # Internal fixture lifetime only: never garbage-collect a caller's store.
    def self.temporary_directory
      Dir.mktmpdir("gettext-workbench-demo-") do |temporary|
        begin
          yield temporary
        ensure
          # Completed fixture generations are intentionally read-only. Restore
          # directory write permission only as this owned temporary tree ends.
          stack = [temporary]
          until stack.empty?
            directory = stack.pop
            next if File.symlink?(directory) || !File.directory?(directory)
            File.chmod(0o700, directory)
            Dir.children(directory).each { |name| stack << File.join(directory, name) }
          end
        end
      end
    end

    def self.fixture(name)
      GettextGenerationWorkbench.read(File.join(PACKAGE, "fixtures", name)).force_encoding(Encoding::UTF_8)
    end

    def self.run(assert: false, io: $stdout)
      temporary_directory do |temporary|
        wb = Workbench.new(File.join(temporary, "core"))
        source = fixture("source_v1.rb")
        en = fixture("en.po")
        pt = fixture("pt_BR.po")
        template = wb.extract(source: fixture("source_v2.rb"))
        merged = wb.merge(catalog: pt, template: template, locale: "pt_BR")
        g1 = wb.compileGeneration(source: source, catalogs: { "en" => en, "pt_BR" => pt })
        first = wb.renderFixture(locale: "pt_BR")
        english = wb.renderFixture(locale: "en")
        inspection = wb.inspectGeneration(locale: "pt_BR")
        readers = []
        begin
          4.times { readers << wb.startRenderer(locale: "pt_BR", barrier: true) }
          readers.each(&:wait_ready)
          g2 = wb.compileGeneration(source: source, catalogs: { "en" => en, "pt_BR" => pt.sub('"Abrir"', '"Abrir novamente"') })
          readers.each(&:release)
          old = readers.map(&:finish)
          fresh = wb.renderFixture(locale: "pt_BR")
        ensure
          readers.each do |reader|
            reader.stop
            begin
              reader.finish
            rescue Error
              nil
            end
          end
        end
        rejected = false
        before = wb.store.active.first
        begin
          wb.compileGeneration(source: source, catalogs: { "pt_BR" => "msgid \"unterminated\n" })
        rescue Error
          rejected = wb.store.active.first == before
        end
        repeat = wb.compileGeneration(source: source, catalogs: { "en" => en, "pt_BR" => pt.sub('"Abrir"', '"Abrir novamente"') })
        fuzzy_wb = Workbench.new(File.join(temporary, "fuzzy"))
        fuzzy_wb.compileGeneration(source: source, catalogs: { "pt_BR" => fixture("fuzzy.po") })
        fuzzy = fuzzy_wb.renderFixture(locale: "pt_BR")
        fuzzy_inspection = fuzzy_wb.inspectGeneration(locale: "pt_BR")
        action_wb = Workbench.new(File.join(temporary, "action"))
        action_wb.compileGeneration(source: source, catalogs: { "pt_BR" => fixture("action.po") })
        action = action_wb.renderFixture(locale: "pt_BR")
        deterministic = g2["id"] == repeat["id"] &&
          %w[en pt_BR].all? { |l| g2["manifest"]["catalogs"][l]["mo_sha256"] == repeat["manifest"]["catalogs"][l]["mo_sha256"] }
        result = {
          "version" => VERSION, "pt_BR" => first, "en" => english,
          "merge" => merged["counts"], "mo_active" => inspection["mo_active"],
          "fuzzy" => { "output" => fuzzy["run"], "counts" => fuzzy_inspection["counts"], "mo_active" => fuzzy_inspection["mo_active"] },
          "utf8" => { "text" => action["action"], "codepoints" => action["action_codepoints"], "bytes" => action["action_bytes"] },
          "pinned" => old.map { |r| { "generation" => r["generation"], "verb" => r["verb"] } },
          "new_verb" => fresh["verb"], "failed_compile_preserved_active" => rejected,
          "deterministic" => deterministic
        }
        if assert
          ok = first["files"] == ["0 arquivos", "1 arquivo", "2 arquivos"] &&
            [first["verb"], first["state"]] == ["Abrir", "Aberto"] &&
            english["files"] == ["0 files", "1 file", "2 files"] &&
            merged["counts"] == { "active" => 3, "fuzzy_active" => 0, "obsolete" => 1 } &&
            inspection["mo_active"] == 3 && fuzzy["run"] == "Run" &&
            fuzzy_inspection["counts"]["fuzzy_active"] == 1 && fuzzy_inspection["mo_active"] == 0 &&
            result["utf8"] == { "text" => "Ação", "codepoints" => 4, "bytes" => 6 } &&
            old.length == 4 && old.all? { |r| r["generation"] == g1["generation"] && r["verb"] == "Abrir" } &&
            fresh["verb"] == "Abrir novamente" && rejected && deterministic
          GettextGenerationWorkbench.fail!("E_DEMO") unless ok
        end
        io.puts "Gettext Generation Workbench development #{VERSION}"
        io.puts "pt_BR: #{first['files'].join(' | ')}"
        io.puts "contexts: #{first['verb']} / #{first['state']}"
        io.puts "merge: #{merged['counts']['active']} active, #{merged['counts']['obsolete']} obsolete"
        io.puts "fuzzy: #{fuzzy['run']}"
        io.puts "UTF-8: #{action['action']} (#{action['action_codepoints']} code points, #{action['action_bytes']} bytes)"
        io.puts "pinning: #{old.length} old readers; new reader: #{fresh['verb']}"
        io.puts "deterministic: #{deterministic}"
        io.puts GettextGenerationWorkbench.canonical(result)
        result
      end
    end
  end
end
