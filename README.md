# Submodule Governance Template

Reusable template to add local git submodule governance to an existing main repository.

## Compatibility

- Verified in macOS/Linux shell environments.
- Not validated on Windows yet.

## What this template installs

- `scripts/submodule-check.sh`
- `scripts/submodule-sync.sh`
- `scripts/pre-push-hook.sh`
- `scripts/install-hooks.sh`
- `.submodule-governance.env`
- `.git/hooks/pre-push` (installed by script)

## Install into current repo

Run this command inside your target main repository:

```bash
/path/to/submodule-governance-template/bootstrap.sh .
```

## Install into another existing repo path

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/target-repo
```

## Strict mode

Install with strict mode:

```bash
/path/to/submodule-governance-template/bootstrap.sh /path/to/target-repo --strict
```

Switch strict mode after install by editing `.submodule-governance.env`:

```bash
SUBMODULE_REQUIRE_PUSHED=1
```

Use `SUBMODULE_REQUIRE_PUSHED=0` for non-strict mode.

## Daily usage in target repo

Sync submodules after branch changes:

```bash
./scripts/submodule-sync.sh
```

Run manual check:

```bash
./scripts/submodule-check.sh
```

Reinstall hook if needed:

```bash
./scripts/install-hooks.sh
```

## Key protection

When a submodule has a new commit but the main repository pointer was not updated, `git push` in main repo is blocked and will prompt:

```bash
git add <submodule_path>
git commit -m "Update submodule pointer"
```
