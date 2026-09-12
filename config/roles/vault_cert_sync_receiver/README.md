# Role: vault_cert_sync_receiver

Installs the receiving half of the one-way Certbot-to-Vault TLS certificate
sync. It creates a dedicated locked SSH account with a root-owned home and
authorization file. Its only allowed key action is a forced wrapper command
from the configured source address; the wrapper may invoke one fixed root
receiver command through sudo.

The receiver accepts only a bounded three-line `vault-cert-sync-v1` stream:
the protocol marker, a base64 PEM full chain, and a base64 private key. It
does not unpack archives or accept destination paths. Before changing Vault's
files it verifies the public CA chain, expected hostname, current validity,
and certificate/key match. It serializes receives, stages both files on the
Vault TLS filesystem, keeps a private backup, sends `HUP` to Vault's main PID,
then verifies the listener fingerprint and unsealed health endpoint. A failed
reload or health check restores the old pair and sends `HUP` again.

Use `config/playbooks/setup_vault_cert_sync.yml` after supplying the opt-in
variables documented in `certbot_setup/README.md`. The role is disabled by
default and never opens a firewall port.
