"""Valentina Studio bookmark pre-connect script for Aura database tunnels.

Paste this script into a PostgreSQL bookmark's Pre Connect editor and change
TUNNEL_NAME to the db-tunnel entry used by that bookmark. Configure the
bookmark with its normal local tunnel endpoint and database role; this script
replaces only the password with a fresh RDS IAM token before every connection.
"""

import os
import shutil
import subprocess


TUNNEL_NAME = "dev-writer"


# GUI applications on macOS commonly do not inherit the shell's Homebrew PATH.
# Include the standard Homebrew and Nix locations while retaining any PATH that
# Valentina Studio did inherit. DB_AUTH_TOKEN_COMMAND remains available for an
# installation in a non-standard location.
environment = os.environ.copy()
command_paths = [
    os.path.expanduser("~/.nix-profile/bin"),
    "/run/current-system/sw/bin",
    "/opt/homebrew/bin",
    "/usr/local/bin",
    "/home/linuxbrew/.linuxbrew/bin",
]
if environment.get("PATH"):
    command_paths.append(environment["PATH"])
environment["PATH"] = os.pathsep.join(command_paths)

command = environment.get("DB_AUTH_TOKEN_COMMAND")
if not command:
    command = shutil.which("db-auth-token", path=environment["PATH"])
if not command:
    raise RuntimeError(
        "db-auth-token was not found; install db-tunnel or set "
        "DB_AUTH_TOKEN_COMMAND to its absolute path"
    )

arguments = [command, environment.get("DB_TUNNEL_NAME", TUNNEL_NAME)]
if params.user:
    arguments.extend(["--db-user", params.user])

token = subprocess.check_output(
    arguments,
    env=environment,
    text=True,
).strip()
if not token:
    raise RuntimeError("db-auth-token returned an empty token")

params.password = token
