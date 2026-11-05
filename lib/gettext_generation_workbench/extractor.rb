gem "gettext", "= 3.5.2"
require "gettext/tools/xgettext"

begin
  # RubyGettext's token filter can return an empty POT for malformed Ruby.
  # Ripper validates syntax as data; it does not execute the supplied source.
  raise SyntaxError unless Ripper.sexp(File.read("source.rb", encoding: "UTF-8"))
  extractor = GetText::Tools::XGetText.new
  extractor.add_parser(GetText::RubyParser)
  # No imported source, parser name, plugin, require option or executable is run.
  extractor.run("--output=messages.pot", "source.rb")
rescue StandardError, SyntaxError
  STDERR.write("E_EXTRACTION\n")
  exit 2
end
