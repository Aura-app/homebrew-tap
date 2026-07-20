# Aura Homebrew Tap

Homebrew tap and package source for internal Aura command-line tools.

## Installing

This tap and its release assets are private, so installing needs GitHub
access to this repo plus the GitHub CLI — Homebrew can't download a private
release with its normal downloader alone.

1. **Get GitHub access.** You need read access to `aura-app/homebrew-tap`
   (org membership or a direct collaborator invite) — ask in
   `#tech-support` if you don't have it yet.
2. **Install and authenticate the GitHub CLI**, if you haven't already:

   ```sh
   brew install gh
   gh auth login
   ```

   When prompted, let it authenticate Git operations with your GitHub
   credentials too (or run `gh auth setup-git` afterwards) — this is what
   lets `brew tap` clone the private repo, separately from `gh` itself being
   used to fetch private release assets.

3. **Tap, trust, and install:**

   ```sh
   brew tap aura-app/tap
   brew trust aura-app/tap
   brew install db-tunnel
   ```

   The trust step is needed because `Formula/db-tunnel.rb` defines a custom
   download strategy (it shells out to `gh release download` to fetch
   private release assets) — Homebrew gates formulas with custom code like
   this behind an explicit trust step before it'll run them.

**Upgrading:** `brew upgrade <package>` alone can silently skip refreshing
tap definitions if Homebrew's automatic update ran recently (it's throttled).
If a new version doesn't show up, run `brew update` explicitly first, then
retry the upgrade.

## Layout

```text
Formula/
  db-tunnel.rb
packages/
  db-tunnel/
    bin/
      db-tunnel
      db-auth-token
    share/
      db-tunnels.json
  pg-transactions/
    bin/
      pg-transactions
  tpsql/
    bin/
      tpsql
```

`Formula/` contains Homebrew formula files. `packages/` contains the source
files used to build versioned release archives for each installable package.

The `db-tunnel` package owns the shared tunnel config and auth-token helper.
Packages such as `tpsql` and `pg-transactions` can depend on `db-tunnel` and
reuse `db-auth-token` plus `db-tunnels.json`.

## Releasing A Package

Each package is released independently using tags of the form
`<package>-v<version>`.

For example:

```sh
git tag db-tunnel-v0.1.0
git push origin db-tunnel-v0.1.0
```

The release workflow builds `packages/db-tunnel` into
`db-tunnel-v0.1.0.tar.gz`, publishes it as a GitHub Release asset, calculates
the SHA-256 checksum, and updates `Formula/db-tunnel.rb` on the default branch.

To build the same archive locally:

```sh
scripts/package-homebrew-package db-tunnel 0.1.0
```

## Private Repository Access

The initial formula uses a normal GitHub Release asset URL. If this repository
or its release assets are private, users may need an authenticated download
strategy instead of Homebrew's default downloader. In that setup, keep the same
package archive and release workflow, but make the formula download via the
GitHub CLI after the user has run `gh auth login`.
