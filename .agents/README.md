# .agents/

Task-oriented playbooks for coding agents working on LOGIT.

Each file describes **one concrete job** an agent might be asked to do. When a
user gives an instruction that matches, read the matching playbook before
acting — these files encode the project-specific quirks (leading-dot bundle
IDs, widget/app version lockstep, App Store Connect validation limits, etc.)
that are easy to get wrong the first time.

## Index

### Release & App Store

Everything App Store Connect, TestFlight, or screenshot related. Start with
[`release/README.md`](release/README.md) for the decision tree.

| If the user says... | Read |
| --- | --- |
| "Ship 4.3 / cut a release / new App Store version" | [`release/ship-release.md`](release/ship-release.md) |
| "Push a TestFlight build / new beta" | [`release/ship-testflight.md`](release/ship-testflight.md) |
| "Update the description / keywords / what's new" | [`release/update-metadata.md`](release/update-metadata.md) |
| "Regenerate / refresh / restyle the screenshots" | [`release/refresh-screenshots.md`](release/refresh-screenshots.md) |
| "Bump the version to X.Y" | [`release/bump-version.md`](release/bump-version.md) |
| "Something broke in the release pipeline" | [`release/troubleshooting.md`](release/troubleshooting.md) |
| "Set up fastlane on a fresh machine" (humans only) | [`release/one-time-setup.md`](release/one-time-setup.md) |

## Conventions

- Every playbook assumes it is being run from the repo root.
- Commands are `zsh`/macOS. Every fastlane invocation goes through
  `bundle exec` because the toolchain is pinned in `Gemfile.lock`.
- Secrets live in `fastlane/.env.secret` (gitignored). Never read, print, or
  commit their contents.
- The playbooks are allowed to reference each other — prefer linking over
  duplicating instructions.
