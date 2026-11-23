# Aura Homebrew Tap

Homebrew tap and package source for internal Aura command-line tools.

## Installing

The tap is public, so no GitHub account is needed. You need Homebrew and an
AWS IAM user with access to the database tunnels (ask in a support ticket; an
admin grants it with `db-access`, below).

1. **Install the tools:**

   ```sh
   brew install --cask session-manager-plugin
   brew install aura-app/tap/db-tunnel
   ```

   This also installs the AWS CLI.

2. **Configure AWS** with your IAM user's access key, in the `default`
   profile (skip this if `aws sts get-caller-identity` already works):

   ```sh
   aws configure
   ```

   Use region `eu-west-1`.

3. **Check the setup:**

   ```sh
   db-tunnel doctor
   ```

   Every line should show ✔. If something fails, include this output in a
   support ticket.

Non-developers using Valentina Studio can follow the one-page
[cheat sheet](docs/cheat-sheet-valentina.md) instead. On Windows, see
[Appendix: Windows (WSL)](#appendix-windows-wsl).

**Upgrading:** `brew upgrade <package>` alone can silently skip refreshing
tap definitions if Homebrew's automatic update ran recently (it's throttled).
If a new version doesn't show up, run `brew update` explicitly first, then
retry the upgrade.

## Connecting To A Database

Every tunnel in `db-tunnels.json` goes through an IAM-auth RDS Proxy shared
by many identities, so there's no shared password — you authenticate as
your own database role via a short-lived IAM token.

Your database role is your AWS IAM user name in lowercase, worked out from
your AWS identity. Set `PGUSER` (or pass `--db-user`) only if yours is named
differently.

1. **See what's available:**

   ```sh
   db-tunnel list
   ```

2. **Open a tunnel.** This blocks (it's holding the SSM port-forward open),
   so run it in its own terminal tab/pane and leave it running:

   ```sh
   db-tunnel open dev
   ```

   It prints the connection details and a ready-to-run `psql` command:

   ```text
   Connect with your database tool (e.g. Valentina Studio) to:

     host 127.0.0.1, port 15432, database devtest, user jane, SSL required

   or from another terminal:

     PGPASSWORD="$(db-auth-token dev)" psql -h localhost -p 15432 -U jane devtest
   ```

3. **In a separate terminal**, run the `psql` command as printed. Each run
   generates a fresh, short-lived IAM token — nothing to remember or rotate.

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

Valentina Studio's bookmark pre-connect hook replaces the connection password
with a fresh IAM token immediately before connecting. Set up a bookmark once
per tunnel:

```sh
db-tunnel valentina dev
```

This prints the bookmark settings (host, port, database, your user, SSL) and
copies the pre-connect hook, already set to that tunnel, to the clipboard.
Create a **PostgreSQL** bookmark with those settings, leave Valentina's SSH
tunnel disabled, and paste the hook into **Pre Connect** with **Python**
selected.

To connect, start the same tunnel in a terminal and leave it running, then
open the bookmark:

```sh
db-tunnel open dev
```

The hook runs `db-auth-token` for the bookmark's user and sets
`params.password`. It adds the standard Homebrew paths, because GUI
applications do not necessarily inherit your shell's `PATH`. The hook source
is `packages/db-tunnel/share/valentina-pre-connect.py`.

## Managing Access

`db-access` is the admin tool for granting database access through the
tunnels. It is not packaged; run it from a checkout with AWS admin
credentials:

```sh
packages/db-access/bin/db-access list
packages/db-access/bin/db-access diagnose jane --env production
packages/db-access/bin/db-access add jane --env production --create-iam-user --new-access-key
packages/db-access/bin/db-access remove jane --env dev,staging,production
```

For each environment it manages the user's `db-tunnel-<env>` IAM policy and
their database role (a LOGIN role named after the IAM user in lowercase,
in `rds_iam` plus `cap_readonly`, `cap_readwrite` or `cap_admin`). See
`db-access --help` for the options.

## Layout

```text
Formula/
  db-tunnel.rb
docs/
  cheat-sheet-valentina.md
packages/
  db-access/
    bin/
      db-access
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
tests/
```

`Formula/` contains Homebrew formula files. `packages/` contains the source
files used to build versioned release archives for each installable package.

The `db-tunnel` package owns the shared tunnel config and auth-token helper.
Packages such as `pg-transactions` can depend on `db-tunnel` and
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

## Appendix: Windows (WSL)

`db-tunnel` is a bash script, so on Windows it runs inside WSL (Ubuntu), not
PowerShell or Git Bash. Git Bash is not supported: the Windows builds of `aws`
and `jq` print Windows line endings, which corrupt the IAM token.

1. **Install WSL with Ubuntu.** In PowerShell as Administrator:

   ```powershell
   wsl --install -d Ubuntu
   ```

   Restart when asked, then open **Ubuntu** from the Start menu and create
   a Linux user name and password. Run every remaining step in that Ubuntu
   terminal.

2. **Install git, jq and the PostgreSQL client:**

   ```sh
   sudo apt update
   sudo apt install -y git jq unzip curl postgresql-client
   ```

3. **Install the AWS CLI v2.** Ubuntu's `awscli` package is v1 and is not
   supported, so use Amazon's installer:

   ```sh
   cd /tmp
   curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o awscliv2.zip
   unzip -q awscliv2.zip
   sudo ./aws/install
   aws --version
   ```

4. **Install the Session Manager plugin:**

   ```sh
   case "$(uname -m)" in aarch64) arch=arm64 ;; *) arch=64bit ;; esac
   curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_${arch}/session-manager-plugin.deb" -o session-manager-plugin.deb
   sudo dpkg -i session-manager-plugin.deb
   session-manager-plugin --version
   ```

5. **Clone the tap and put `db-tunnel` on your `PATH`:**

   ```sh
   git clone https://github.com/Aura-app/homebrew-tap.git ~/homebrew-tap
   echo 'export PATH="$HOME/homebrew-tap/packages/db-tunnel/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   ```

   `db-tunnel` finds its tunnel list next to the script, so nothing else
   needs copying.

6. **Configure AWS and check the setup**, as for macOS:

   ```sh
   aws configure    # default profile, region eu-west-1
   db-tunnel doctor
   ```

**Updating:** `git -C ~/homebrew-tap pull`.

**Connecting:** run `db-tunnel open dev` in an Ubuntu terminal and leave it
open. `psql` in a second Ubuntu terminal works as described above. Windows
applications such as DBeaver can also connect to `localhost` on the printed
port, because WSL forwards it to Windows. For their password, run
`db-auth-token dev` in Ubuntu and paste the output; it expires after 15
minutes, but an open connection stays up. `--dbeaver` and the Valentina hook
need DBeaver or Valentina to run inside WSL, so they do not work with the
Windows apps.
