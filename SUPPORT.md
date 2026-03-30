# Support

Use the right channel for the right kind of problem.

## Bug Reports

Open a GitHub issue if:

- the client behaved incorrectly
- a feature regressed
- the app crashed
- the UI or sync behavior is wrong after setup succeeded

Include:

- exact repro steps
- device or simulator target
- macOS or iOS version
- Xcode version
- backend version or commit if relevant
- screenshots or logs

## Setup And Build Help

Open a GitHub issue if:

- Xcode project setup failed
- signing configuration is unclear
- the app builds but cannot connect to the backend
- local configuration from `Local.xcconfig.example` is not enough to get running

Include:

- the exact step that failed
- the exact error text
- your Xcode version
- whether you are testing on macOS, simulator, or device

## Security Issues

Do not use public issues for vulnerabilities.

Use the process in [SECURITY.md](SECURITY.md).

## Scope Note

The client and backend are separate repositories.

If the issue appears to involve:

- authentication
- tasks
- memory
- documents
- server-side tools
- shared Google or Apple integration behavior

then the root cause may be in the backend repo instead of this client repo.
