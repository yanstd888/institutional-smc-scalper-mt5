# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 4.52.x  | :white_check_mark: |
| < 4.50  | :x:                |

## Zero-Credential Invariant

YANSTD EA executes purely locally inside MetaTrader 5 client terminal environments. 
- The EA does **not** make unauthorized external web requests.
- No broker account credentials, investor passwords, API keys, or webhooks are compiled or hardcoded into the MQL5 code.
- Dynamic news filtering via `NewsFilter.mqh` utilizes standard public calendar HTTP APIs without credential storage.

## Reporting a Vulnerability

If you discover a security vulnerability or critical trade-execution flaw:
1. Please do **NOT** open a public issue.
2. Submit your findings privately via GitHub Security Advisories or contact the maintainers directly.
3. Include clear reproduction steps, EA version, symbol, and MT5 build number.
