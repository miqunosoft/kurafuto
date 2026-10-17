# .github/

GitHub Actions workflows, issue and pull request templates, and code owners. (Named `AGENTS.md` because GitHub would render a `.github/README.md` as the repository front page.)

## Workflows

- `workflows/ci.yml` – required check `build-and-test`: generates the project with XcodeGen, builds without code signing, runs `KurafutoTests` on an iOS simulator and checks the String Catalog (`scripts/check-localizations.sh`). Runs on pull requests, pushes to `main` and manual dispatch.
- `workflows/dco.yml` – required check `DCO`, implemented in `scripts/check-dco.sh`.
- `workflows/pages.yml` – deploys `site/` to GitHub Pages on pushes to `main` that touch `site/`. The only job with more than `contents: read` (`pages: write`, `id-token: write`, required by `actions/deploy-pages`). Not a required check.

## Workflow rules

- Top-level `permissions: {}`; each job requests only `contents: read`. A job that needs more states why in a comment.
- Actions are pinned to full commit SHAs with the version in a comment. Update them deliberately, like any dependency.
- `actions/checkout` always uses `persist-credentials: false`.
- Never use `pull_request_target` or `workflow_run` with untrusted code, and never interpolate `${{ github.event.* }}` text into `run:` scripts – pass it through `env:`.
- No signing certificates, provisioning profiles or App Store Connect keys in CI until a release workflow is designed in an ADR.
- No Dependabot, Renovate or other automated update bots.

## Repository settings (to apply on GitHub)

These are not in code; keep this list in sync with the live settings.

- Ruleset `main` (ID `25093336`): no deletion, no force-push, no bypass actors; pull requests required, conversation resolution required, squash merge only; required status checks `build-and-test` and `DCO` (GitHub Actions app).
- Squash merge as the only merge method; delete branches after merge; auto-merge allowed (merges only once the required checks pass).
- Secret scanning and push protection enabled; private vulnerability reporting enabled; Dependabot **alerts** enabled, automatic pull requests disabled.
- Actions: default `GITHUB_TOKEN` read-only; workflows may not create or approve pull requests.
- Pages: source "GitHub Actions", custom domain `getkurafuto.app`, "Enforce HTTPS" on. DNS at the registrar: `A`/`AAAA` records for the apex pointing to GitHub Pages, and verify the domain under the `miquno` account's Pages settings (TXT record `_github-pages-challenge-miquno`). The domain is verified for the account (protects it from takeover; a domain verified for an organization only works for that organization's repositories); the certificate covers `getkurafuto.app` and `www.getkurafuto.app`, but only the apex has DNS records.
- Code-owner review not required while there is a single maintainer.

## Gotchas

- Required check names are the job names. Renaming a job means updating the ruleset in the same change.
- A skipped job counts as passing. Never add path filters or `if:` conditions that can skip a required job.
