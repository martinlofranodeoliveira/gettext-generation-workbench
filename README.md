# Gettext Generation Workbench

Development version **0.1.0**, by [Lofrano Tecnologia](https://lofranotecnologia.com.br).
An original Ruby gem and CLI that exercises extraction, merging, binary compilation and actual translated rendering offline. Catalogs are synthetic. This is a narrowly qualified workflow, not a translation-quality assessment or a deployment system.

## Prepare, install, test

Qualified Linux toolchain: Ruby **3.4.12** at `/usr/local/bin/ruby`, Bundler **2.6.9**, RubyGettext **3.5.2**, GNU `msgfmt`, `msgmerge`, `msgunfmt`, `msgattrib` **0.21**, Python **3.11.2** at `/usr/bin/python3`. Version checks deliberately reject other versions. Install native tools before use; no packages are installed at application runtime.

On the qualified Debian-based Ruby environment:

```sh
apt-get update
apt-get install -y --no-install-recommends gettext python3
gem install bundler --version 2.6.9 --no-document
BUNDLE_FROZEN=true bundle install
bundle exec ruby test/run.rb
bundle exec ruby bin/catalog_workbench demo --assert
```

The preparation commands require the appropriate package-install permissions. Tests and demo need no network after dependencies are available. The committed `Gemfile.lock` was resolved with Bundler and includes upstream gem checksums. Frozen installation keeps that qualified dependency set. The exact RubyGems gettext 3.5.2 archive has SHA-256 `ada02c59aa7e9f56bd2522faedaed16421dd2f3ddb5fe28628c0be5abcbf3c74`.

Build/install the gem, including its owned Python helper, Ruby workers and fixtures:

```sh
gem build gettext-generation-workbench.gemspec --output /tmp/workbench.gem
gem install --local /tmp/workbench.gem --ignore-dependencies --no-document
catalog_workbench demo --assert
```

`--ignore-dependencies` assumes the earlier dependency preparation. Package resources resolve from `__dir__`, not the current directory.

## Offline demonstration

The human-readable prefix is:

```text
Gettext Generation Workbench development 0.1.0
pt_BR: 0 arquivos | 1 arquivo | 2 arquivos
contexts: Abrir / Aberto
merge: 3 active, 1 obsolete
fuzzy: Run
UTF-8: Ação (4 code points, 6 bytes)
pinning: 4 old readers; new reader: Abrir novamente
deterministic: true
```

The final line is canonical JSON containing actual generation digests, renderer results, independent MO message counts, merge counts, pinning results and failure-preservation evidence. No clock, PID or random workspace name appears in it. `--assert` exits unsuccessfully if the fixed expected results disagree. The assertion checks those fixed outcomes against actual GNU tools and the qualified RubyGettext runtime.

The core catalog has exactly three active messages: context-qualified `verb/Open`, `state/Open` and the file plural. The revision removes `state/Open` and adds `Settings`. Fuzzy `Run` and Unicode `Action` are separate catalogs so they cannot inflate the three-message oracle.

## CLI examples

```sh
bundle exec ruby bin/catalog_workbench extract fixtures/source_v1.rb
bundle exec ruby bin/catalog_workbench compile /tmp/my-catalog-store fixtures/source_v1.rb en=fixtures/en.po pt_BR=fixtures/pt_BR.po
bundle exec ruby bin/catalog_workbench render /tmp/my-catalog-store pt_BR
bundle exec ruby bin/catalog_workbench inspect /tmp/my-catalog-store pt_BR
```

Use a new store path or an existing workbench-marked private store. `extract` prints normalized POT text; `merge LOCALE CATALOG.po TEMPLATE.pot` prints JSON with normalized PO, raw GNU merge evidence and counts. Compile, render and inspect print JSON. Error output is a code-only JSON object on stderr, with exit status 2; native diagnostic text is never returned publicly.

Ruby usage:

```ruby
require "gettext_generation_workbench"
wb = GettextGenerationWorkbench::Workbench.new("/tmp/ruby-catalog-store")
pot = wb.extract(source: File.read("fixtures/source_v2.rb", encoding: "UTF-8"))
merged = wb.merge(catalog: File.read("fixtures/pt_BR.po", encoding: "UTF-8"),
                  template: pot, locale: "pt_BR")
wb.compileGeneration(source: File.read("fixtures/source_v2.rb", encoding: "UTF-8"),
                     catalogs: { "pt_BR" => merged.fetch("po") })
puts wb.renderFixture(locale: "pt_BR").fetch("verb") # Abrir
```

Only the RubyGettext Ruby parser is admitted. Source is trusted extraction data, never imported or executed. The renderer is fixed checked-in code, not the supplied source.

## Why generations and processes?

One cooperative writer lock covers complete compilation and the atomic active-pointer transition. Generations are content-addressed, read-only directories. A renderer snapshots the active pointer once, copies and hash-checks its MO into a private immutable locale tree and never follows the pointer again. Each locale context uses its own process: RubyGettext's global locale state is not treated as thread-local.

The fixed worker checks the raw MO header with RubyGettext's maintained MO parser **before binding or plural lookup**. Only the exact literal `nplurals=2; plural=(n != 1);` is admitted. RubyGettext 3.5.2 subsequently evaluates that fixed expression internally; the application never evaluates a catalog expression. This is not support for arbitrary GNU plural expressions. The Portuguese example follows its supplied rule, including plural at zero, not a claim about every Portuguese locale.

## Limits and caveats

Per API operation: at most 16 catalogs and 16 MiB aggregate source/catalog input. A workbench instance admits four simultaneous fixed renderers, rejecting a fifth before spawn. Each supervised child has a five-second monotonic deadline and a combined 64 KiB stdout/stderr capture cap. There are additional finite entry, string and manifest bounds. These are not a machine-global process limit, pre-parser memory quota or filesystem quota.

GNU tools validate syntax and marked printf formats. Fuzzy entries compile as untranslated; obsolete messages remain in PO evidence but never count as active or render. No translation-completeness guarantee is made. Unmarked format strings are not a general formatting proof. No arbitrary plugins, source execution, remote services, telemetry or model/API runtime are used.

Linux child supervision explicitly restores inherited SIGCHLD to its default before spawning, uses an unreaped direct-child anchor, TERM/KILL, then a permanent signal seal, then reaping. Trusted fixed children do not escape their session. This is not a general sandbox or a hard deadline guarantee for uninterruptible kernel I/O. Stores assume a private local filesystem and cooperative writers; permissions and hashes are not authentication against a hostile process with the same user identity. Generations accumulate; there is deliberately no automatic deletion or rollback/retention service.

## Container

```sh
docker build -t gettext-workbench:dev .
docker run --rm --network=none --read-only --cap-drop=ALL --tmpfs /tmp:rw,nosuid,nodev,size=128m gettext-workbench:dev
```

The pinned Ruby base is recorded in `Dockerfile`; apt repositories and resolved transitive gems remain build inputs, so a bit-identical OS image is not promised. The image's runtime command directly runs the installed gem as non-root; it does not compile/install software at startup.

## Further reading and licensing

See [contract](docs/contract.md), [design](docs/design.md), [contributing](CONTRIBUTING.md) and [security reporting](SECURITY.md). Project code is MIT, copyright 2026 Lofrano Tecnologia. RubyGettext's upstream Ruby/LGPL licensing and GNU gettext tools' GPL licensing remain separate; they are not relicensed MIT by this project. Upstream sources: [RubyGettext](https://github.com/ruby/gettext), [GNU gettext](https://www.gnu.org/software/gettext/manual/gettext.html), [Ruby encoding](https://docs.ruby-lang.org/en/3.4/Encoding.html).
