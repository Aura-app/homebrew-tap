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
   brew install tpsql
   ```

   The trust step is needed because `Formula/db-tunnel.rb` defines a custom
   download strategy (it shells out to `gh release download` to fetch
   private release assets) — Homebrew gates formulas with custom code like
   this behind an explicit trust step before it'll run them.

**Upgrading:** `brew upgrade <package>` alone can silently skip refreshing
tap definitions if Homebrew's automatic update ran recently (it's throttled).
If a new version doesn't show up, run `brew update` explicitly first, then
retry the upgrade.

## Connecting To A Database

Every tunnel in `db-tunnels.json` goes through an IAM-auth RDS Proxy shared
by many identities, so there's no shared password — you authenticate as
your own database role via a short-lived IAM token.

1. **Set `PGUSER` once**, e.g. in `~/.bashrc`/`~/.zshrc`, to your own
   database role:

   ```sh
   export PGUSER=<your-database-role>
   ```

   `psql` reads this natively, and so does `db-auth-token` — one setting
   covers both.

2. **See what's available:**

   ```sh
   db-tunnel list
   ```

3. **Open a tunnel.** This blocks (it's holding the SSM port-forward open),
   so run it in its own terminal tab/pane and leave it running:

   ```sh
   db-tunnel open dev
   ```

   It prints a ready-to-run connect command using the `PGUSER` you set in
   step 1:

   ```text
   Connect with:

     PGPASSWORD="$(db-auth-token dev)" psql -h localhost -p 15432 devtest
   ```

4. **In a separate terminal**, run the command exactly as printed:

   ```sh
   PGPASSWORD="$(db-auth-token dev)" psql -h localhost -p 15432 devtest
   ```

   Each run generates a fresh, short-lived IAM token — nothing to remember
   or rotate. `tpsql` does this same connect step in one command if you'd
   rather not copy-paste it (it still needs the tunnel from step 3 open in
   another terminal):

   ```sh
   tpsql dev
   ```

### Opening DBeaver

If DBeaver is installed, `db-tunnel` can start the tunnel, generate the IAM
token, and open a connected temporary datasource in one step:

```sh
db-tunnel open staging --dbeaver
```

The connection is named after the tunnel, such as `Aura staging`, and is not
saved to the DBeaver workspace. To use a different database role for one
launch, pass it explicitly:

```sh
db-tunnel open production --dbeaver --db-user shauns
```

On macOS, the launcher detects the Community, Lite, Enterprise, and Ultimate
app bundles. On Linux, it checks the usual executable names on `PATH`. For an
installation in another location, provide the executable directly:

```sh
DB_TUNNEL_DBEAVER_EXECUTABLE=/path/to/dbeaver \
  db-tunnel open staging --dbeaver
```

The IAM token is passed through a private temporary variables file rather than
on DBeaver's command line, and the file is removed when the tunnel closes. If
DBeaver needs to reconnect after the short-lived token expires, close the old
tunnel and rerun the command to create a fresh temporary connection.

Press Ctrl-C in the `db-tunnel open` terminal to close the tunnel when
you're done with it. DBeaver remains open, with its temporary connection
disconnected.

### Connecting With Valentina Studio

Valentina Studio's bookmark pre-connect hook can replace the connection
password immediately before connecting, which avoids copying a new IAM token
into the bookmark each time. The hook is installed with `db-tunnel`; it
generates the token but does not start the tunnel.

1. Locate the hook installed by Homebrew:

   ```sh
   VALENTINA_HOOK="$(brew --prefix db-tunnel)/share/db-tunnel/valentina-pre-connect.py"
   less "$VALENTINA_HOOK"
   ```

   On macOS, copy the complete hook directly to the clipboard with:

   ```sh
   pbcopy < "$VALENTINA_HOOK"
   ```

2. Create or edit a **PostgreSQL** bookmark in Valentina Studio. Configure it
   with the local endpoint from `db-tunnel list`, your own database role, and
   SSL mode `require`. Do not enable Valentina's SSH tunnel: `db-tunnel` owns
   that part of the connection. For example, the read-only `dev` bookmark is:

   ```text
   Name:      Aura dev
   Host:      127.0.0.1
   Port:      15432
   Database:  devtest
   User:      <your database role>
   Password:  <blank or any placeholder>
   SSL mode:  require
   SSH:       disabled
   ```

3. In that bookmark's editor, open **Pre Connect**, select **Python**, and
   paste the complete contents of `valentina-pre-connect.py`. Do not put it in
   **Post Connect** or a shell-script field.
4. Change `TUNNEL_NAME` near the top of the pasted hook to exactly the tunnel
   name used by the bookmark, such as `dev`, `staging`, or `production`.
5. Save the bookmark, start the same tunnel in a terminal, and leave it
   running while Valentina is connected:

   ```sh
   db-tunnel open dev
   ```

6. Open the bookmark in Valentina. The hook generates a fresh IAM token and
   places it in the runtime connection parameters before PostgreSQL connects.

The script receives Valentina's mutable `params` connection object, runs
`db-auth-token` without a shell, trims its stdout, and assigns the result to
`params.password`. It passes the bookmark's `params.user` explicitly, so the
generated token always matches the role Valentina will use. The script also
adds the standard Homebrew paths on Intel and Apple Silicon Macs because GUI
applications do not necessarily inherit your interactive shell's `PATH`.

## Layout

```text
Formula/
  db-tunnel.rb
  tpsql.rb
  lib/
    github_cli_download_strategy.rb
packages/
  db-tunnel/
    bin/
      db-tunnel
      db-auth-token
    share/
      db-tunnels.json
      valentina-pre-connect.py
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
