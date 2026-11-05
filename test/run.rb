require_relative "../lib/gettext_generation_workbench"
require "stringio"

W = GettextGenerationWorkbench
TESTS = []

def test(name, &block)
  TESTS << [name, block]
end

def equal(expected, actual)
  raise "expected #{expected.inspect}, got #{actual.inspect}" unless expected == actual
end

def check(value, message = "condition failed")
  raise message unless value
end

def error(code = nil)
  begin
    yield
  rescue W::Error => e
    equal(code, e.code) if code
    return e
  end
  raise "expected a public error"
end

def fixture(name)
  W::Demo.fixture(name)
end

def workspace
  W::Demo.temporary_directory do |dir|
    yield W::Workbench.new(File.join(dir, "store")), dir
  end
end

def compile_core(wb, pt = fixture("pt_BR.po"))
  wb.compileGeneration(source: fixture("source_v1.rb"), catalogs: { "en" => fixture("en.po"), "pt_BR" => pt })
end

require_relative "catalog_test"
require_relative "lifecycle_test"

failures = 0
TESTS.each do |name, body|
  begin
    body.call
    puts "PASS #{name}"
  rescue StandardError => e
    failures += 1
    STDERR.puts "FAIL #{name}: #{e.class}: #{e.message}"
    STDERR.puts e.backtrace.first(5)
  end
end
puts JSON.generate("tests" => TESTS.length, "failures" => failures)
exit(failures.zero? ? 0 : 1)
