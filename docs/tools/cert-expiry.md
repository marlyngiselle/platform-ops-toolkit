# cert-expiry

Check the TLS certificate served by each endpoint and report the days left before it expires. Built to be called by cron, a CI schedule or a monitoring agent: the exit code carries the result.

## Prerequisites

- `openssl` (LibreSSL on macOS works)
- `jq` for `--json`
- `timeout` (coreutils) is used when present to bound each connection

## Permissions

Network reachability to the endpoints. No credentials.

## Usage

```text
cert-expiry [-f FILE] [-w DAYS] [-c DAYS] [-t SECONDS] [--json] HOST[:PORT]...
```

| Option | Default | Notes |
| --- | --- | --- |
| `-w`, `--warning` | 30 | Days left at or below which the status is WARNING |
| `-c`, `--critical` | 7 | Days left at or below which the status is CRITICAL |
| `-t`, `--timeout` | 10 | Seconds per endpoint |
| `-f`, `--file` | | One endpoint per line, `#` comments allowed |

SNI is always sent, so virtual hosts behind a shared IP report their own certificate.

## Examples

```console
$ cert-expiry www.example.com api.example.com legacy.example.com down.example.com
2027-01-01T08:00:00Z [WARN ] cert-expiry: down.example.com:443: could not retrieve certificate
HOST                                     PORT   DAYS_LEFT NOT_AFTER             STATUS
www.example.com                          443    364       2027-12-31T00:00:00Z  OK
api.example.com                          443    19        2027-01-20T00:00:00Z  WARNING
legacy.example.com                       443    2         2027-01-03T00:00:00Z  CRITICAL
down.example.com                         443    -         -                     UNKNOWN
$ echo $?
2
```

```console
$ cert-expiry --json www.example.com api.example.com:8443
[
  { "host": "www.example.com", "port": 443, "days_left": 364, "not_after": "2027-12-31T00:00:00Z", "status": "OK" },
  { "host": "api.example.com", "port": 8443, "days_left": 19, "not_after": "2027-01-20T00:00:00Z", "status": "WARNING" }
]
```

Endpoints file:

```text
# public endpoints
www.example.com
api.example.com:8443   # partner API
```

Daily check from cron, alerting only on a non-zero exit:

```cron
0 7 * * * cert-expiry -q -f /etc/platform-ops/endpoints.txt || notify-oncall "certificates need attention"
```

## Exit codes

`0` all OK · `1` at least one WARNING · `2` CRITICAL or EXPIRED · `3` an endpoint could not be checked (and nothing worse) · `64` usage · `69` missing dependency.
