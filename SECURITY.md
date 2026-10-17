# Security Policy

Kurafuto holds credentials for servers that people run at home. Thank you for helping keep them safe.

## Supported versions

Only the latest App Store / TestFlight build and the `main` branch receive security fixes.

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues, discussions or pull requests.**

Report them privately through GitHub's private vulnerability reporting:

1. Open the [Security Advisories page](https://github.com/miquno/kurafuto/security/advisories/new).
2. Click **Report a vulnerability** and fill in the details.

Please include as much of the following as you can:

- A description of the vulnerability and its impact
- Steps to reproduce, or a proof of concept
- The affected version or commit, iOS version and device
- Any suggested fix or mitigation

Do not include real panel addresses, tokens or passwords in your report.

### What to expect

- We acknowledge reports within **7 days**.
- We keep you informed while we investigate and fix the issue.
- Once a fix ships, we credit you in the advisory unless you prefer to remain anonymous.

Please give us reasonable time to fix the issue before public disclosure.

## Scope

In scope:

- The Kurafuto iOS app and its handling of tokens, certificates and panel data
- The source code, CI workflows and scripts in this repository

Out of scope:

- Vulnerabilities in Crafty Controller itself – report those to the Crafty project (https://gitlab.com/crafty-controller/crafty-4)
- Attacks that require a jailbroken device or physical access to an unlocked device
- Findings from automated scanners without a demonstrated impact

## Security model

- [docs/security/threat-model.md](docs/security/threat-model.md) – assets, trust boundaries, threats and mitigations
- [PRIVACY.md](PRIVACY.md) – what is stored where
