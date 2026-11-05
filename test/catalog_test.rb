test "extracts contexts and plural data without executing the raising source" do
  workspace do |wb, _|
    output = wb.extract(source: fixture("source_v1.rb"))
    wb.store.job do |job|
      File.write(File.join(job, "extracted.po"), output)
      entries = W::Catalog.active(W::Catalog.parse(File.join(job, "extracted.po")))
      actual = entries.map { |e| [e.msgctxt, e.msgid, e.msgid_plural] }.sort_by(&:inspect)
      expected = [["verb", "Open", nil], ["state", "Open", nil], [nil, "%d file", "%d files"]].sort_by(&:inspect)
      equal(expected, actual)
    end
    check(output.include?("source.rb:"))
    check(!output.include?("SOURCE-MUST-NOT-EXECUTE"))
    check(!output.include?("EMAIL@ADDRESS"))
    check(output.include?("2000-01-01"))
    equal(output, wb.extract(source: fixture("source_v1.rb")))
  end
end

test "real msgmerge retains context translation and one obsolete record" do
  workspace do |wb, _|
    merged = wb.merge(catalog: fixture("pt_BR.po"), template: wb.extract(source: fixture("source_v2.rb")), locale: "pt_BR")
    equal({ "active" => 3, "fuzzy_active" => 0, "obsolete" => 1 }, merged["counts"])
    check(merged["evidence"].include?('#~ msgctxt "state"'))
    check(merged["evidence"].include?('#~ msgstr "Aberto"'))
    wb.compileGeneration(source: fixture("source_v2.rb"), catalogs: { "pt_BR" => merged["po"] })
    rendered = wb.renderFixture(locale: "pt_BR")
    equal("Abrir", rendered["verb"])
    equal("Open", rendered["state"])
    equal("Settings", rendered["settings"])
    inspected = wb.inspectGeneration(locale: "pt_BR")
    # Settings is active in the PO but still untranslated; GNU msgfmt omits
    # that entry, so runtime fallback is Settings and the MO has two messages.
    equal(2, inspected["mo_active"])
    check(!inspected["po"].include?('msgid "Settings"'))
    check(!inspected["po"].include?("Aberto"))
  end
end

test "obsolete materialization counts messages rather than the Ruby pseudoentry" do
  workspace do |wb, _|
    po = fixture("pt_BR.po") + "\n#~ msgid \"Retired A\"\n#~ msgstr \"Antigo A\"\n\n#~ msgid \"Retired B\"\n#~ msgstr \"Antigo B\"\n"
    published = wb.compileGeneration(source: fixture("source_v1.rb"), catalogs: { "pt_BR" => po })
    equal(2, published["manifest"]["catalogs"]["pt_BR"]["counts"]["obsolete"])
    equal(3, wb.inspectGeneration(locale: "pt_BR")["mo_active"])
  end
end

test "empty obsolete output is materialized and cannot reuse a previous catalog" do
  workspace do |wb, _|
    wb.qualify
    wb.store.job do |job|
      old = fixture("pt_BR.po") + "\n#~ msgid \"Retired\"\n#~ msgstr \"Antigo\"\n"
      W::Catalog.normalize(old, "pt_BR", job)
      equal(1, W::Catalog.counts(job)["obsolete"])
      W::Catalog.normalize(fixture("pt_BR.po"), "pt_BR", job)
      equal(0, W::Catalog.counts(job)["obsolete"])
      check(File.file?(File.join(job, "obsolete.po")))
    end
  end
end

test "real MO contexts, qualified plural outputs and independent msgunfmt" do
  workspace do |wb, _|
    compile_core(wb)
    pt = wb.renderFixture(locale: "pt_BR")
    equal(["0 arquivos", "1 arquivo", "2 arquivos"], pt["files"])
    equal(["Abrir", "Aberto"], [pt["verb"], pt["state"]])
    equal(["0 files", "1 file", "2 files"], wb.renderFixture(locale: "en")["files"])
    inspected = wb.inspectGeneration(locale: "pt_BR")
    equal(3, inspected["mo_active"])
    check(inspected["po"].include?('msgctxt "verb"'))
    check(inspected["po"].include?('msgctxt "state"'))
    check(inspected["po"].include?('msgstr[1] "%d arquivos"'))
    error("E_LOCALE") { wb.renderFixture(locale: "pt_PT") }
  end
end

test "fuzzy is active evidence but not runtime translation" do
  workspace do |wb, _|
    wb.compileGeneration(source: fixture("source_v1.rb"), catalogs: { "pt_BR" => fixture("fuzzy.po") })
    equal("Run", wb.renderFixture(locale: "pt_BR")["run"])
    inspected = wb.inspectGeneration(locale: "pt_BR")
    equal({ "active" => 1, "fuzzy_active" => 1, "obsolete" => 0 }, inspected["counts"])
    equal(0, inspected["mo_active"])
    check(!inspected["po"].include?("Executar"))
  end
end

test "Ação survives PO to MO to isolated Ruby renderer" do
  workspace do |wb, _|
    wb.compileGeneration(source: fixture("source_v1.rb"), catalogs: { "pt_BR" => fixture("action.po") })
    rendered = wb.renderFixture(locale: "pt_BR")
    equal("Ação", rendered["action"])
    equal(4, rendered["action_codepoints"])
    equal(6, rendered["action_bytes"])
    check(wb.inspectGeneration(locale: "pt_BR")["po"].include?("Ação"))
  end
end

test "unterminated quote, format mismatch and extraction failure preserve active" do
  workspace do |wb, _|
    compile_core(wb)
    before = wb.store.active.first
    directories = Dir.children(File.join(wb.store.root, "generations")).sort
    bad = "msgid \"unterminated\nSECRET-CATALOG\n"
    error { wb.compileGeneration(source: fixture("source_v1.rb"), catalogs: { "pt_BR" => bad }) }
    mismatch = fixture("pt_BR.po").sub('msgstr[0] "%d arquivo"', 'msgstr[0] "%s arquivo"')
    error { wb.compileGeneration(source: fixture("source_v1.rb"), catalogs: { "pt_BR" => mismatch }) }
    error { wb.compileGeneration(source: "def invalid(\n", catalogs: { "pt_BR" => fixture("pt_BR.po") }) }
    error { wb.merge(catalog: bad, template: wb.extract(source: fixture("source_v2.rb")), locale: "pt_BR") }
    equal(before, wb.store.active.first)
    equal(directories, Dir.children(File.join(wb.store.root, "generations")).sort)
    equal("Abrir", wb.renderFixture(locale: "pt_BR")["verb"])
  end
end

test "two compilations have two matching MO hashes and canonical manifest hashes" do
  workspace do |wb, _|
    a = compile_core(wb)
    b = compile_core(wb)
    equal(1, a["generation"])
    equal(2, b["generation"])
    equal(a["id"], b["id"])
    %w[en pt_BR].each do |locale|
      equal(a["manifest"]["catalogs"][locale]["mo_sha256"], b["manifest"]["catalogs"][locale]["mo_sha256"])
    end
    bytes = W.canonical(a["manifest"])
    equal(a["id"], W.sha(bytes))
    check(!bytes.include?(wb.store.root))
    check(!bytes.include?("generation\":"))
  end
end

test "known literal guard rejects evasive MO headers before every eval" do
  workspace do |wb, _|
    good = W::Header.build("pt_BR")
    rules = [
      good.sub(W::Header::PLURAL, ""),
      good + W::Header::PLURAL,
      good.sub("Plural-Forms:", "plural-forms:"),
      good.sub("Plural-Forms:", " Plural-Forms:"),
      good.sub("nplurals=2", "nplurals=3"),
      good.sub("plural=(n != 1);", "plural=(n != 1) + CATALOG_SENTINEL;"),
      good.sub("plural=(n != 1);", "plural=(n != 1); plural=0;"),
      good.sub("charset=UTF-8", "charset=ISO-8859-1"),
      good.sub("Plural-Forms:", "Plural-Forms :")
    ]
    eval_calls = 0
    tracer = TracePoint.new(:c_call) do |event|
      if event.method_id == :eval
        eval_calls += 1
        raise "forbidden eval reached"
      end
    end
    wb.store.job do |job|
      rules.each_with_index do |header, index|
        path = File.join(job, "guard-#{index}.mo")
        writer = GetText::MO.new("UTF-8")
        writer[""] = header
        writer["Action"] = "Ação"
        writer.save_to_file(path)
        rejected = false
        tracer.enable do
          mo = GetText::MO.open(path, "UTF-8")
          begin
            W::Header.guard_mo!(mo, "pt_BR")
          rescue W::Error
            rejected = true
          end
        end
        check(rejected, "forbidden header admitted")
      end
      writer = GetText::MO.new("UTF-8")
      writer[""] = good
      writer.save_to_file(File.join(job, "good.mo"))
      check(W::Header.guard_mo!(GetText::MO.open(File.join(job, "good.mo"), "UTF-8"), "pt_BR"))
    end
    equal(0, eval_calls)
    check(!Object.const_defined?(:CATALOG_SENTINEL))
  end
end

test "aggregate inputs, locale paths and catalog number are rejected early" do
  workspace do |wb, _|
    error("E_INPUT_LIMIT") { wb.extract(source: "x" * (W::INPUT_LIMIT + 1)) }
    catalogs = (0...17).to_h { |i| ["a#{i}", ""] }
    error("E_CATALOG_LIMIT") { wb.compileGeneration(source: "", catalogs: catalogs) }
    error("E_LOCALE") { wb.compileGeneration(source: "", catalogs: { "../pt_BR" => fixture("pt_BR.po") }) }
    error("E_ENCODING") { wb.extract(source: "\xff".b) }
    equal([], Dir.children(File.join(wb.store.root, "generations")))
  end
end


test "nonregular writer locks fail without publication or following links" do
  workspace do |wb, dir|
    path = File.join(wb.store.root, "writer.lock")
    File.mkfifo(path, 0o600)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error("E_STORE") { compile_core(wb) }
    check(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < 1.0)
    equal([], Dir.children(File.join(wb.store.root, "generations")))
    File.unlink(path)
    target = File.join(dir, "unrelated")
    File.write(target, "keep")
    File.symlink(target, path)
    error("E_STORE") { compile_core(wb) }
    equal("keep", File.read(target))
    equal([], Dir.children(File.join(wb.store.root, "generations")))
  end
end

test "render cleanup removes only its read-only snapshot and preserves sealed generations" do
  workspace do |wb, _|
    receipt = compile_core(wb)
    generation = File.join(wb.store.root, "generations", receipt["id"])
    manifest = File.join(generation, "manifest.json")
    before = File.binread(manifest)
    equal(0o500, File.stat(generation).mode & 0o777)
    equal(0o400, File.stat(manifest).mode & 0o777)
    equal("Abrir", wb.renderFixture(locale: "pt_BR")["verb"])
    equal([], Dir.children(File.join(wb.store.root, "jobs")))
    equal(0o500, File.stat(generation).mode & 0o777)
    equal(0o400, File.stat(manifest).mode & 0o777)
    equal(before, File.binread(manifest))
  end
end
