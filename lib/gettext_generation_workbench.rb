require_relative "gettext_generation_workbench/version"
require "json"
require "digest"
require "tmpdir"
require "fileutils"
require "thread"
require "rbconfig"
gem "gettext", "= 3.5.2"
require "gettext"
require "gettext/po"
require "gettext/po_parser"
require "gettext/mo"

module GettextGenerationWorkbench
  INPUT_LIMIT = 16 * 1024 * 1024
  OUTPUT_LIMIT = 64 * 1024
  MANIFEST_LIMIT = 256 * 1024
  ENTRY_LIMIT = 10_000
  STRING_LIMIT = 64 * 1024
  LOCALE = /\A[a-z]{2,3}(?:_[A-Z]{2})?\z/
  PACKAGE = File.expand_path("..", __dir__)

  class Error < StandardError
    attr_reader :code
    def initialize(code)
      @code = code
      super(code)
    end
  end

  def self.fail!(code)
    raise Error, code
  end

  def self.safe(code)
    yield
  rescue Error
    raise
  rescue StandardError
    fail!(code)
  end

  def self.canonical(value)
    sorted = case value
             when Hash then value.keys.sort.to_h { |k| [k, JSON.parse(canonical(value.fetch(k)))] }
             when Array then value.map { |v| JSON.parse(canonical(v)) }
             else value
             end
    JSON.generate(sorted)
  end

  def self.sha(bytes)
    Digest::SHA256.hexdigest(bytes)
  end

  def self.text(value)
    fail!("E_INPUT") unless value.is_a?(String) && value.bytesize <= INPUT_LIMIT
    value = value.dup.force_encoding(Encoding::UTF_8)
    fail!("E_ENCODING") unless value.valid_encoding? && !value.include?("\0")
    value.gsub("\r\n", "\n")
  end

  def self.inputs!(*values)
    fail!("E_INPUT_LIMIT") unless values.all? { |v| v.is_a?(String) } &&
                                  values.sum(&:bytesize) <= INPUT_LIMIT
  end

  def self.locale!(locale)
    fail!("E_LOCALE") unless locale.is_a?(String) && LOCALE.match?(locale)
    locale
  end

  def self.read(path, limit = INPUT_LIMIT)
    fail!("E_FILE") unless File.file?(path) && !File.symlink?(path)
    File.open(path, "rb") do |f|
      bytes = f.read(limit + 1)
      fail!("E_INPUT_LIMIT") if bytes.bytesize > limit
      bytes
    end
  end
end

require_relative "gettext_generation_workbench/catalog"
require_relative "gettext_generation_workbench/runner"
require_relative "gettext_generation_workbench/store"
require_relative "gettext_generation_workbench/workbench"
require_relative "gettext_generation_workbench/demo"
