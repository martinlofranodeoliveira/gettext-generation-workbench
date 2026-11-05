# Design notes

## Maintained format engines, small orchestration layer

The project orchestrates RubyGettext 3.5.2 and GNU gettext-tools 0.21 rather than implementing PO quoting, context-key encoding, binary MO layout or plural syntax. Source extraction is always `XGetText.new`, `add_parser(GetText::RubyParser)` and fixed `run('--output=messages.pot', 'source.rb')` arguments. It never accepts `--parser`, `--require`, arbitrary tool arguments or project plugins. A raising synthetic Ruby source establishes that extraction treats source as data. Only `.rb` is represented internally, regardless of a CLI input filename.

Ruby POParser is a permissive scanner, not a syntax validator. Native msgfmt runs first, with format checks, before any PO admission based on the Ruby model. Model-based header/reference normalization avoids regex rewriting of catalog bodies. Normalization replaces extractor-generated date/author boilerplate rather than preserving wall-clock output or placeholder contact details.

## Plural trust boundary

The qualified RubyGettext `MO#load_from_stream` loads header fields without eval. `MO#plural_as_proc` later evaluates its parsed plural expression, including an initial call with 1. Consequently checking just the declared charset or trusting GNU to accept the expression is insufficient: an isolated process still must not evaluate an arbitrary Ruby expression.

The worker opens only its private copied MO with the maintained parser, checks the raw header's field uniqueness and exact qualified literal, then checks parsed plural fields and UTF-8 encoding. This precedes domain binding, locale lookup and ngettext. Afterward only the library may evaluate the known literal. The tests write adversarial MOs with the maintained writer and trace C-level eval calls across MO loading and guard rejection; invalid rules must cause zero eval calls. The sentinel expression references an undefined constant without executing side effects. This establishes a narrow version-specific boundary, not safety for future unreviewed library versions.

## Immutability and locale isolation

A content-addressed manifest is canonical independently of publication. The external pointer carries a monotonically increasing publication counter. Writers hold `flock` across the entire operation. Failed tools cannot partially replace the active selection. Files become read-only; generation directories become non-writable. No automatic generation deletion exists.

A renderer snapshots a selected MO into an owned private tree, verifies its hash and uses that same tree for validation and binding. This avoids a validation/bind reread of caller-controlled paths. `set_locale` is explicit. Global TextDomainManager state is confined to a separate fixed worker for each locale context, not shared threads. The concurrency oracle waits for acknowledgements from four real workers before publishing generation two; no delay is used as proof of pinning. After release every old process must return generation-one strings, and a newly started process must return generation-two strings.

## Lifetime and bounded captures

Ruby's Open3 detached waiter can reap a child before an ensure block signals a numeric process group. Merely setting a boolean after wait does not fix PID reuse. This project instead uses a small Linux Python stdlib helper as the sole reaper:

1. Enable `PR_SET_CHILD_SUBREAPER` and create one leader with `Popen(start_new_session=True, close_fds=True)`.
2. Observe leader exit using `waitid(P_PID, ..., WEXITED|WNOHANG|WNOWAIT)`, never `poll`, `wait` or `communicate` before sealing.
3. On observed exit, control EOF/STOP or monotonic deadline, attempt group TERM then KILL while the direct child remains unreaped.
4. Permanently seal all future signaling; only then wait/reap the direct child and adopted descendants.

Ruby owns only the helper control pipe and helper PID wait, never group signaling. It drains stdout, stderr and the bounded report concurrently; overflow requests STOP and continues discarding/draining. Report events document signal-attempt, seal, reap order and an empty child set. Fixed normal, nested-hang and flood probes exercise the actual mechanism. Native tools and fixed workers do not create escaping sessions. This is not a supervisor for hostile arbitrary executables, a container boundary or a guarantee against uninterruptible I/O.

An abandoned ticket retains its slot until finished and must be stopped/finished by its owner. Temporary directory deletion is restricted to the invocation's exact private job path plus identity marker. The application never sweeps unknown directories, deletes published generations or interprets catalog paths.

## Evidence and determinism

msgunfmt is independent evidence of the compiled binary, not a reserialization of the input PO. Expected context/plural strings are manually specified in tests. Fuzzy active entries appear in PO counts but not MO message counts. GNU msgattrib materializes obsolete entries because Ruby POParser aggregates obsolete blocks into one pseudoentry.

Fixed dates, relative extraction names, organization metadata, sorted locale iteration, canonical JSON and exact toolchain qualification remove runtime IDs and wall-clock data from canonical artifacts. The original byte stream is not claimed as the normalized hash input. Input limits and post-parse limits bound accepted work but do not establish pre-parser memory quotas or disk quotas.

## Packaging and dependencies

Gemspec explicitly includes workers, helper, probes and fixtures; resource lookup is based on installed file locations. The CLI always uses fixed package code for rendering. Docker's command runs the installed gem directly as non-root, with temporary work under `/tmp`. CI only prepares dependencies, tests and builds locally; there is no release, publish or deployment workflow. The OS base digest is pinned, while apt repository contents remain mutable. Dependency resolution and upstream licenses remain separate from original project code.

Primary references used for this design are RubyGettext 3.5.2's MO, POParser, XGetText and TextDomainManager APIs, installed GNU tool interfaces, [RubyGettext upstream](https://github.com/ruby/gettext), [GNU manual](https://www.gnu.org/software/gettext/manual/gettext.html), [Ruby Encoding](https://docs.ruby-lang.org/en/3.4/Encoding.html), [Python waitid](https://docs.python.org/3/library/os.html#os.waitid), and [PR_SET_CHILD_SUBREAPER](https://man7.org/linux/man-pages/man2/PR_SET_CHILD_SUBREAPER.2const.html). Links are references, not claims of live website validation or broad standards compliance.


## Inherited signal state

The exec boundary preserves ignored POSIX signal dispositions. Before creating a work child, the fixed Python helper explicitly restores SIGCHLD to SIG_DFL; it installs no competing reaper. This prevents inherited ignore from auto-reaping the leader before WNOWAIT observation and sealing. A fixed launcher regression sets SIGCHLD=IGNORE then execs the actual helper, with a normal Ruby parent reaping that helper. The report records the inherited state, the reset before spawn, observation without reap, signal/seal/reap order and no remaining children. This is not a forced PID-reuse experiment.


## Native empty results and temporary permissions

GNU msgattrib normally omits an output file when no messages survive filtering. Fixed filter/inspection profiles use `--force-po` so an empty result replaces the previous result rather than being missing or stale across catalog iterations. PO active-message counts include untranslated entries; GNU msgfmt omits their MO entries, so the merged Settings fixture has three active PO records but two translated MO messages and a runtime Settings fallback.

The immutable store retains completed generations at mode 0500 and files at 0400. Once a renderer is reaped, cleanup makes directories writable only in its validated marked job tree before removal. The synthetic demo/test temporary lifetime separately restores its own temporary directories for destruction; it is not a garbage collector for caller stores. Runtime render cleanup never unseals published generations.

Writer lock descriptors are opened with NONBLOCK and NOFOLLOW and must fstat as regular files before flock. This rejects preexisting FIFOs without blocking and refuses symbolic links. General hostile filesystem races remain outside the private cooperative-store contract. Ripper syntax validation precedes the maintained extractor token filter; both treat source as data.
