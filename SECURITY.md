# Security Policy

This repository ships executable hook scripts, shell utilities, and harness
adapter modules that execute locally under the user's permissions.

## Supported Versions

Security fixes are shipped as urgent hotfixes against the latest tagged release
on `main`.

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for suspected security
vulnerabilities (such as command injection in a hook or validator, hook bypass
via untrusted repository input, path traversal, or credential leakage).

Report privately using **GitHub Private Vulnerability Reporting** on this
repository's Security tab, or email the maintainer directly at
`pnjoyim@gmail.com`.

Include:

- The affected script, hook, workflow, or adapter path and commit/version.
- A minimal reproduction (with any real secrets redacted).
- Expected vs observed impact.

You can expect an acknowledgment within 72 hours and coordinated disclosure
once a fix is verified and tagged.
