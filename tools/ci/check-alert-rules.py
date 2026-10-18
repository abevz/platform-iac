#!/usr/bin/env python3
"""Render the real alert template with fixtures and validate it with promtool."""
from pathlib import Path
import shutil
import subprocess
import tempfile

import jinja2
import yaml


def main():
    root = Path(__file__).resolve().parents[2]
    role = root / "config/roles/monitoring_stack"
    variables = yaml.safe_load((role / "defaults/main.yml").read_text())
    cluster = {"name": "dev-lab-cluster", "api_server": "192.0.2.200",
               "vault_k8s_role": "prometheus-external", "node_ips": ["192.0.2.200"]}
    variables["monitoring_proxmox_cadvisor_port_resolved"] = 8080
    template = jinja2.Environment(undefined=jinja2.StrictUndefined,
                                  trim_blocks=True).from_string(
        (role / "templates/alerts.yml.j2").read_text())
    with tempfile.TemporaryDirectory(prefix="iac-ci-alerts-") as directory:
        path = Path(directory)
        for name, clusters, enabled in [("full", [cluster], True),
                                        ("empty", [], True),
                                        ("disabled", [], False)]:
            variables.update(monitoring_k8s_clusters=clusters,
                             monitoring_k8s_security_alerts_enabled=enabled)
            rules = path / f"{name}.rules.yml"
            rules.write_text(template.render(variables))
            subprocess.run(["promtool", "check", "rules", str(rules)], check=True)
        shutil.copy(path / "full.rules.yml", path / "security-alerts.rules.yml")
        for fixture in ["security_alerts.test.yml", "proxmox_thin_pool_alerts.test.yml"]:
            shutil.copy(root / "tests" / fixture, path / fixture)
            subprocess.run(["promtool", "test", "rules", fixture], cwd=path,
                           check=True)


if __name__ == "__main__":
    main()
