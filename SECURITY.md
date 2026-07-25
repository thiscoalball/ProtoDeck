# Security policy

## Supported versions

Security fixes are applied to the latest development branch and the latest tagged release. Older
build artifacts may not receive backports while the project is in active development.

## Reporting a vulnerability

Do not open a public issue containing an exploit, credential, private host, packet capture or other
sensitive material.

Use GitHub's **Report a vulnerability** / private security advisory feature for this repository. In
the report, include:

- affected version, commit and platform;
- required permissions and preconditions;
- minimal reproduction steps;
- expected impact;
- logs or captures with credentials, tokens, public IPs and device identifiers removed.

Maintainers will acknowledge a complete report when it is reviewed, coordinate a fix and disclosure
window where practical, and credit the reporter if requested. Please do not test against networks,
devices or accounts you are not authorized to use.

## Security-sensitive areas

Changes involving SSH host-key verification, credential storage, TLS validation, local listeners,
file transfer paths, packet parsing, Android permissions or native code require focused regression
tests and explicit review.
