# tpsql

Wraps `psql` to connect through a local `db-tunnel` endpoint, generating a
fresh IAM database auth token via `db-auth-token` and passing it as
`PGPASSWORD`. See `tpsql --help` for usage.
