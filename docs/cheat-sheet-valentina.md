# Connecting to the Aura database with Valentina Studio

For anyone who uses Valentina Studio to look at our data or pull reports. It
replaces the old setup that someone from the tech team may have done for you.
Setting it up takes about 15 minutes, once. You need a Mac on which you can
install apps.

## Before you start

**Log a support ticket** at [LINK TBC] asking for *database access through
db-tunnel*. You will get back an **AWS access key**, which is two codes (an
"Access Key ID" and a "Secret Access Key"). Treat it like a password: never put
it in Slack, email or a ticket.

## One-time setup

Open **Terminal** (press Cmd-Space, type `Terminal`, press Enter). Copy each
grey box below into it and press Enter.

**1. Install Homebrew** (skip this if you already have it).

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

It asks for your Mac password. Nothing appears as you type, which is normal.
When it finishes, it shows **Next steps** with a couple of commands. Copy and
run those too, then close Terminal and open it again.

**2. Install the database tools.**

```sh
brew install --cask session-manager-plugin
brew install aura-app/tap/db-tunnel
```

**3. Sign in to AWS** with the access key from your ticket.

```sh
aws configure
```

Paste the Access Key ID and the Secret Access Key when asked, type `eu-west-1`
for the region, and press Enter for the last question.

**4. Check everything is ready.** Every line should have a ✔.

```sh
db-tunnel doctor
```

**5. Set up Valentina Studio.**

```sh
db-tunnel valentina production
```

This prints the details for a new connection in Valentina Studio and copies a
short script to your clipboard. Follow the steps it shows. If you have an old
Aura connection in Valentina Studio, keep it until the new one works, then
delete it.

## Every time you want to connect

1. In Terminal, run `db-tunnel open production`. **Leave that window open.**
2. In Valentina Studio, open your Aura connection.
3. When you have finished, go back to Terminal and press **Ctrl-C**.

## If something goes wrong

Run `db-tunnel doctor`, then log a support ticket at [LINK TBC] with its output
(a screenshot is fine) and the error message you saw. Do not include your
Secret Access Key.
