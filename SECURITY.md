# Security Policy

## Supported Versions

Security fixes are applied to the current `main` branch and the latest tagged release.

Older tags may not receive backported fixes.

## Reporting A Vulnerability

Do not open a public GitHub issue for a suspected security vulnerability.

Report it privately to the maintainer with:

- a clear description of the issue
- affected version or commit
- reproduction steps if available
- impact assessment if known

If you do not already have a private reporting path, open a minimal GitHub issue requesting one without disclosing the vulnerability details publicly.

## Scope Note

This repository is the native Apple client only.

Some security-sensitive behavior depends on the separate FruitcakeAI backend, including:

- authentication
- chat transport
- server-side integrations
- task execution
- shared credential-backed services

If the issue spans both client and backend, report that explicitly.

## Disclosure Expectations

- coordinated disclosure is preferred
- please allow reasonable time for investigation and patching before public disclosure
- reports with concrete reproduction details will be triaged faster
