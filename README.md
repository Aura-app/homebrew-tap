# Aura Homebrew Tap

Homebrew tap and package source for internal Aura command-line tools.

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
