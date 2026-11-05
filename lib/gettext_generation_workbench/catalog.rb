module GettextGenerationWorkbench
  module Header
    PLURAL = "Plural-Forms: nplurals=2; plural=(n != 1);\n"
    CONTENT = "Content-Type: text/plain; charset=UTF-8\n"

    def self.build(locale)
      "Project-Id-Version: Gettext Generation Workbench 0.1.0\n" \
        "POT-Creation-Date: 2000-01-01 00:00+0000\n" \
        "PO-Revision-Date: 2000-01-01 00:00+0000\n" \
        "Last-Translator: Lofrano Tecnologia\n" \
        "Language-Team: Lofrano Tecnologia\n" \
        "Language: #{locale}\n" \
        "MIME-Version: 1.0\n" + CONTENT +
        "Content-Transfer-Encoding: 8bit\n" + PLURAL
    end

    def self.check!(header, locale = nil)
      GettextGenerationWorkbench.fail!("E_HEADER") unless header.is_a?(String) &&
        header.encoding == Encoding::UTF_8 && header.valid_encoding?
      lines = header.lines
      GettextGenerationWorkbench.fail!("E_HEADER") unless !lines.empty? &&
        lines.all? { |l| /\A[A-Za-z][A-Za-z-]*: [^\r\n]*\n\z/.match?(l) }
      plurals = lines.select { |l| /\Aplural-forms:/i.match?(l) }
      contents = lines.select { |l| /\Acontent-type:/i.match?(l) }
      GettextGenerationWorkbench.fail!("E_PLURAL_RULE") unless plurals == [PLURAL]
      GettextGenerationWorkbench.fail!("E_ENCODING") unless contents == [CONTENT]
      if locale
        languages = lines.select { |l| /\Alanguage:/i.match?(l) }
        GettextGenerationWorkbench.fail!("E_LOCALE") unless languages == ["Language: #{locale}\n"]
      end
      true
    end

    # MO.open is the maintained parser, not a handwritten binary parser. In
    # gettext 3.5.2 it loads the header without calling plural_as_proc/eval.
    def self.guard_mo!(mo, locale)
      # MO.open keeps the header's raw bytes as ASCII-8BIT in gettext3.5.2.
      # Validate a UTF-8 view without transcoding/replacing invalid bytes.
      raw = mo[""]
      GettextGenerationWorkbench.fail!("E_HEADER") unless raw.is_a?(String)
      check!(raw.dup.force_encoding(Encoding::UTF_8), locale)
      GettextGenerationWorkbench.fail!("E_PLURAL_RULE") unless
        mo.charset == "UTF-8" && mo.nplurals == "2" && mo.plural == "(n != 1)"
      true
    end
  end

  module Catalog
    def self.parse(path)
      po = GetText::PO.new
      parser = GetText::POParser.new
      parser.ignore_fuzzy = false
      parser.report_warning = false
      parser.parse_file(path, po)
      entries = active(po)
      GettextGenerationWorkbench.fail!("E_ENTRY_LIMIT") if entries.length > ENTRY_LIMIT
      entries.each do |e|
        [e.msgid, e.msgctxt, e.msgid_plural, e.msgstr].flatten.compact.each do |s|
          GettextGenerationWorkbench.fail!("E_STRING_LIMIT") if s.to_s.bytesize > STRING_LIMIT
        end
      end
      po
    end

    def self.active(po)
      po.select { |e| e.msgid.is_a?(String) && !e.msgid.empty? }
    end

    def self.normalize(bytes, locale, job, template: false)
      bytes = GettextGenerationWorkbench.text(bytes)
      File.write(File.join(job, "catalog.po"), bytes)
      # GNU syntax validation MUST precede the permissive Ruby PO scanner.
      Runner.run("compile", job)
      po = parse(File.join(job, "catalog.po"))
      header = po.find { |e| e.msgid == "" }
      GettextGenerationWorkbench.fail!("E_HEADER") unless header
      Header.check!(header.msgstr, locale) unless template
      header.msgstr = Header.build(locale)
      header.translator_comment = "Gettext Generation Workbench development 0.1.0"
      header.flags = []
      po.each do |entry|
        entry.references = [] unless template
      end
      normalized = po.to_s
      GettextGenerationWorkbench.inputs!(normalized)
      File.write(File.join(job, "catalog.po"), normalized)
      Runner.run("compile", job)
      normalized
    end

    def self.normalize_extraction(path)
      po = parse(path)
      header = po.find { |e| e.msgid == "" }
      GettextGenerationWorkbench.fail!("E_EXTRACTION") unless header
      header.msgstr = Header.build("en")
      header.translator_comment = "Gettext Generation Workbench development 0.1.0"
      header.flags = []
      # The extractor only ever sees the fixed relative name source.rb.
      po.each do |entry|
        entry.references = entry.references.sort
      end
      po.to_s
    end

    def self.counts(job)
      po = parse(File.join(job, "catalog.po"))
      entries = active(po)
      Runner.run("obsolete", job)
      obsolete = active(parse(File.join(job, "obsolete.po"))).length
      {
        "active" => entries.length,
        "fuzzy_active" => entries.count(&:fuzzy?),
        "obsolete" => obsolete
      }
    end
  end
end
