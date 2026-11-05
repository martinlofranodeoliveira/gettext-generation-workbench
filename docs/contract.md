# Development 0.1.0 contract

## Scope

Linux, the qualified toolchain in the READMEs, a private local store, cooperative writers, installed trusted dependencies and fixed package workers. All APIs are instance methods of `GettextGenerationWorkbench::Workbench`. Input source and PO/POT values are UTF-8 strings, not executable paths. All errors raised by public operations are `GettextGenerationWorkbench::Error` with a stable `code`; messages contain only that code. No native diagnostics are public. No arbitrary source, parser, plugin, executable or environment option is accepted.

## APIs

* `Workbench.new(root)` creates a private marked store at a new path, or opens an existing workbench store. An unmarked nonempty directory is rejected. The parent directory must already exist.
* `extract(source:) -> String`: runs only the maintained Ruby parser on a fixed owned `source.rb`. Caller code is never executed. Supported constructs are literal `gettext`, `pgettext`, `ngettext` calls demonstrated by the fixtures; dynamic arguments and other languages are outside the contract. Relative references use `source.rb`. Output metadata uses fixed dates and organization metadata.
* `merge(catalog:, template:, locale:) -> Hash`: GNU-validates inputs, runs fixed GNU msgmerge options, returns `po` (normalized PO), `evidence` (raw merged GNU output including obsolete blocks), and `counts`. Template is an `extract` result using the canonical English header. No fuzzy matching is requested. Unchanged translations retain their values; removed records remain obsolete evidence.
* `compileGeneration(source:, catalogs:) -> Hash`: catalogs is a hash of locale identifier to PO string. Successful extraction, GNU syntax/format validation, normalization, literal header admission and all MO builds precede publication. Returns external `generation` counter, content-addressed `id`, and `manifest`. This API does not imply source/catalog completeness or automatically merge a revision.
* `renderFixture(locale:) -> Hash`: starts one fixed isolated renderer pinned to the currently active generation. Returns `generation`, `manifest_sha256`, `locale`, `verb`, `state`, `files` (counts 0,1,2), `run`, `settings`, `action`, `action_codepoints`, `action_bytes`. Missing translations fall back through maintained gettext behavior. Only the selected catalog locale is accepted; the host default is not used.
* `inspectGeneration(locale:) -> Hash`: snapshots and verifies an MO, uses independent GNU msgunfmt, returns `generation`, `id`, PO `counts`, `mo_active`, and decompiled `po`. A fuzzy-only MO has zero active nonheader messages.
* `startRenderer(locale:, barrier: false) -> Ticket`: explicit asynchronous fixture API. A ticket must be finished by its owner. With a barrier, `wait_ready` confirms a fixed process has pinned and validated its private MO; `release` permits rendering. `stop` requests cleanup through the helper, not PID signaling. `finish` returns the render hash and frees its slot. Tickets are single-owner, not thread-safe. `wait_ready` has a three-second coordination timeout, within the child lifetime. `renderer_starts` provides a spawn count for the fifth-request regression oracle.

## Admission and limits

Locale identifiers match `[a-z]{2,3}(_[A-Z]{2})?`, case-sensitive, with no path components. This is an intentionally restricted identifier syntax, not general locale syntax compliance. Header `Language` must match the explicit identifier.

At most 16 catalogs and 16 MiB aggregate source/catalog bytes per operation, checked before normalization. CRLF becomes LF, UTF-8 must be valid, and NUL is rejected. Normalized compilation inputs must also fit 16 MiB. Per PO parse: 10,000 nonheader active entries; individual parsed message/context/translation strings are at most 64 KiB. Manifest maximum is 256 KiB. These post-parse limits do not promise bounded parser RSS before admission. There is no disk quota or generation retention policy.

At most four live renderer tickets per workbench instance. A fifth request is rejected before spawn. This is not machine-global: callers must share an instance to share its renderer budget. Native tool calls are sequential within each operation and writers are serialized by the store lock. A child has a five-second monotonic deadline and at most 64 KiB combined captured stdout/stderr; excess is discarded while cleanup drains the pipes. The helper report has a separate 8 KiB cap. No general descendant/session-escape sandbox or uninterruptible-I/O deadline guarantee is offered.

Every admitted raw header must have newline-terminated, unfolded `Name: value` lines; exactly one case-insensitively recognized Plural-Forms field must be the exact line:

```text
Plural-Forms: nplurals=2; plural=(n != 1);
```

Exactly one Content-Type field must be `Content-Type: text/plain; charset=UTF-8`. Capitalization and whitespace in these qualified fields are exact. Duplicate fields, folded lines, other casing, missing fields, appended expressions and alternative rules are rejected. At runtime `MO.open(path, 'UTF-8')` returns the header as raw bytes. A UTF-8 view must validate without replacement/transcoding, and the parser must expose `charset == 'UTF-8'`, `nplurals == '2'` (a string in gettext 3.5.2) and `plural == '(n != 1)'` before binding. Only the maintained library may subsequently evaluate this fixed qualified expression. No application code calls eval on catalog text.

## Counts and compilation policy

`counts` has exactly `active`, `fuzzy_active`, `obsolete`. Active excludes the header and obsolete blocks, including fuzzy and untranslated active messages. Fuzzy-active is a subset of active, not a translated count. Obsolete is counted by GNU msgattrib `--only-obsolete --clear-obsolete` materialization, not Ruby POParser's aggregate `:last` pseudoentry. Neither these counts nor MO presence measure linguistic quality or completeness.

GNU msgfmt `--check --check-format` must succeed before the Ruby PO parser is used to admit PO syntax, and again after normalization. Default msgfmt behavior excludes fuzzy translations. Obsolete entries never enter the MO. Marked Ruby printf forms are checked by GNU; runtime arguments are fixed integers formatted using Ruby `%`.

## Generations, hashes and failure

`generations/<id>/` contains `source.rb`, normalized `messages.pot`, normalized `po/<locale>.po`, `locale/<locale>/LC_MESSAGES/fixture.mo`, `manifest.json` and a fixed identity marker. No filename comes from message text. The manifest is UTF-8 canonical JSON with recursively sorted object keys and no trailing newline. Its SHA-256 is the ID. It includes format/version, normalized source/POT/PO hashes, actual MO hashes, counts, policy and qualified toolchain. It excludes paths, clocks, UUIDs, PIDs and publication counters.

Hashes are of normalized inputs, not original submitted byte streams. Catalog header dates/metadata are replaced and catalog references removed through the maintained PO model; extraction references are fixed relative names. Obsolete comments are retained by the PO model; merge also returns the exact native evidence separately. Reproducibility is qualified-toolchain-specific, not a cross-version guarantee.

The writer lock covers extraction through the complete directory and active-pointer transition. All validation failures leave `active.json` unchanged and publish no generation. Identical successful content reuses its directory and still increments the external counter in `active.json`. Publication uses same-filesystem rename and fsync; an OS/storage failure can leave a complete unreferenced generation or an uncertain durability result, so this is not a transactional database or distributed crash-consensus protocol. No incomplete generation is deliberately selected.

Render startup reads the active pointer once, verifies its canonical manifest digest, copies the selected MO to a private tree and verifies the MO digest. The worker validates that same private read-only MO before binding. It never reads a mutable catalog path or rereads the active pointer. The store is not authenticated against a hostile same-UID process; private filesystem ownership is a precondition.

## Diagnostics and CLI

CLI successes use stdout; errors use stderr JSON `{"error":"CODE"}` and exit 2. Public codes include `E_ARGUMENT`, `E_INPUT`, `E_INPUT_LIMIT`, `E_ENCODING`, `E_LOCALE`, `E_HEADER`, `E_PLURAL_RULE`, `E_CATALOG_LIMIT`, `E_ENTRY_LIMIT`, `E_STRING_LIMIT`, `E_RUNTIME`, `E_STORE`, `E_FILE`, `E_NO_GENERATION`, `E_MANIFEST`, `E_INTEGRITY`, `E_TOOL`, `E_CHILD_START`, `E_CHILD_REPORT`, `E_CHILD_OUTPUT`, `E_CHILD_TIMEOUT`, `E_EXTRACTION`, `E_MERGE`, `E_COMPILE`, `E_INSPECTION`, `E_RENDER`, `E_RENDER_LIMIT`, `E_BARRIER`, `E_DEMO`, `E_OPERATION`. Generic phase codes cover unexpected library/system errors without leaking their raw messages. No claim is made that one native failure maps to a more detailed stable diagnosis.
