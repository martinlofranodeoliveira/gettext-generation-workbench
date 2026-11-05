require_relative "lib/gettext_generation_workbench/version"

Gem::Specification.new do |s|
  s.name = "gettext-generation-workbench"
  s.version = GettextGenerationWorkbench::VERSION
  s.summary = "An offline, generation-pinned gettext workflow"
  s.description = "Extract trusted Ruby messages, merge catalogs, compile immutable generations and exercise fixed isolated renderers."
  s.authors = ["Lofrano Tecnologia"]
  s.homepage = "https://lofranotecnologia.com.br"
  s.license = "MIT"
  s.required_ruby_version = ">= 3.4", "< 3.5"
  s.metadata = {
    "source_code_uri" => "https://github.com/martinlofranodeoliveira/gettext-generation-workbench",
    "bug_tracker_uri" => "https://github.com/martinlofranodeoliveira/gettext-generation-workbench/issues"
  }
  s.files = Dir["lib/**/*", "fixtures/**/*", "bin/*", "docs/*.md"] +
            %w[README.md README.pt-BR.md LICENSE SECURITY.md CHANGELOG.md]
  s.bindir = "bin"
  s.executables = ["catalog_workbench"]
  s.require_paths = ["lib"]
  s.add_dependency "gettext", "= 3.5.2"
end
