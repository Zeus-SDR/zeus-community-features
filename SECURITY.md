# Security policy

Zeus controls real transmitters. A feature vulnerability can cause data loss,
unintended RF emission, or equipment damage.

Do not open a public issue for a vulnerability. Email
`support@zeussdr.com` with a subject beginning `SECURITY:` and include the
feature ID/version, platform, reproduction, impact, and required attacker
access. Put unintended transmit, auto-keying, or PureSignal impact first.

Catalog removal prevents new installs but does not remove already-installed
code. Security response may therefore yank a version and recommend uninstall
or safe-mode startup.

Community packages execute in-process. SDK capability declarations and
collectible assembly load contexts are not a security boundary. Never put
credentials in source, manifests, packages, logs, or CI output.

