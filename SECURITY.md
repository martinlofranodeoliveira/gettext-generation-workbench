# Security policy

Development version 0.1.0 has a narrow, version-qualified contract, not a general hostile-code sandbox. Review `docs/contract.md` before processing catalogs. Source is trusted extraction data and is never executed. Stores and dependencies must be private/trusted; hostile same-UID filesystem modification is outside the boundary.

Report vulnerabilities through GitHub private vulnerability reporting:

https://github.com/martinlofranodeoliveira/gettext-generation-workbench/security/advisories/new

Include the qualified toolchain versions, a minimal synthetic reproducer, expected/observed behavior and the affected trust boundary. Do not submit secrets, personal data, private source or client catalogs. Avoid public disclosure of exploit details while using the private reporting channel. No response-time SLA is promised.

For general contact, use the official organization homepage: https://lofranotecnologia.com.br.

Particularly relevant issues include reaching catalog eval before the literal guard, imported source execution, arbitrary executable/profile selection, mixed-generation rendering, public diagnostic leakage, and signaling after direct-child reap. Dependency updates require requalifying these boundaries rather than simply relaxing version checks.
