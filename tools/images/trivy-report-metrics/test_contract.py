#!/usr/bin/env python3
"""Check a local KSM binary against synthetic list/watch data and the role probes."""

import argparse
import datetime
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

import jinja2
import yaml


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    role = root / "config/roles/trivy_operator_deploy"
    values = yaml.safe_load((role / "defaults/main.yml").read_text())
    env = jinja2.Environment(undefined=jinja2.StrictUndefined)
    env.filters["to_json"] = json.dumps
    env.filters["hash"] = lambda text, algorithm: hashlib.new(algorithm, text.encode()).hexdigest()
    values.update(role_path=str(role), lookup=lambda name, path: Path(path).read_text())
    rendered = env.from_string((role / "templates/report-metrics.yml.j2").read_text()).render(**values)
    documents = list(yaml.safe_load_all(rendered))
    config = next(d["data"]["config.yml"] for d in documents if d["kind"] == "ConfigMap")
    container = next(d["spec"]["template"]["spec"]["containers"][0] for d in documents if d["kind"] == "Deployment")
    assert container["readinessProbe"]["httpGet"] == {"path": "/readyz", "port": "telemetry"}
    assert container["livenessProbe"]["httpGet"] == {"path": "/livez", "port": "metrics"}
    assert {p["name"]: p["containerPort"] for p in container["ports"]} == {"metrics": 8080, "telemetry": 8081}
    metrics_port, telemetry_port = free_port(), free_port()
    requests = []
    stop = threading.Event()
    report = {
        "apiVersion": "aquasecurity.github.io/v1alpha1",
        "kind": "VulnerabilityReport",
        "metadata": {"name": "fixture", "namespace": "fixture", "resourceVersion": "10", "creationTimestamp": "2026-10-14T12:00:00Z"},
        "report": {"updateTimestamp": "2026-10-15T12:00:00Z", "artifact": {"digest": "sha256:" + "a" * 64}},
    }
    crd = {
        "apiVersion": "apiextensions.k8s.io/v1", "kind": "CustomResourceDefinition",
        "metadata": {"name": "vulnerabilityreports.aquasecurity.github.io", "resourceVersion": "10"},
        "spec": {"group": "aquasecurity.github.io", "names": {"kind": "VulnerabilityReport", "listKind": "VulnerabilityReportList", "plural": "vulnerabilityreports", "singular": "vulnerabilityreport"}, "scope": "Namespaced", "versions": [{"name": "v1alpha1", "served": True, "storage": True}]},
        "status": {"acceptedNames": {"kind": "VulnerabilityReport", "plural": "vulnerabilityreports"}, "storedVersions": ["v1alpha1"]},
    }

    class API(BaseHTTPRequestHandler):
        def log_message(self, *unused):
            pass

        def do_GET(self):
            parsed = urllib.parse.urlparse(self.path)
            query = urllib.parse.parse_qs(parsed.query)
            requests.append({"path": parsed.path, "query": query})
            resource = None
            if parsed.path.endswith("/customresourcedefinitions"):
                resource = crd
            elif parsed.path.endswith("/vulnerabilityreports"):
                resource = report
            if resource:
                if query.get("watch") == ["true"]:
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    try:
                        self.wfile.write((json.dumps({"type": "ADDED", "object": resource}) + "\n").encode())
                        self.wfile.flush()
                        stop.wait(30)
                    except (BrokenPipeError, ConnectionResetError):
                        pass
                    return
                body = {"apiVersion": resource["apiVersion"], "kind": resource["kind"] + "List", "metadata": {"resourceVersion": "10"}, "items": [resource]}
            elif parsed.path == "/version":
                body = {"major": "1", "minor": "33", "gitVersion": "v1.33.0", "gitTreeState": "clean", "platform": "linux/amd64"}
            elif parsed.path == "/livez":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok")
                return
            elif parsed.path in {"/apis/aquasecurity.github.io/v1alpha1", "/apis/apiextensions.k8s.io/v1"}:
                obj = report if "aquasecurity" in parsed.path else crd
                body = {"apiVersion": "v1", "kind": "APIResourceList", "groupVersion": obj["apiVersion"], "resources": [{"name": "vulnerabilityreports" if obj is report else "customresourcedefinitions", "singularName": "", "namespaced": obj is report, "kind": obj["kind"], "verbs": ["list", "watch"]}]}
            else:
                self.send_error(404)
                return
            payload = json.dumps(body).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

    server = ThreadingHTTPServer(("127.0.0.1", 0), API)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    args.output.mkdir(parents=True, exist_ok=True)
    result = {"fixture": "synthetic Kubernetes 1.33 list/watch API", "passed": False}
    try:
        with tempfile.TemporaryDirectory(prefix="ksm-contract-") as directory:
            directory = Path(directory)
            (directory / "config.yml").write_text(config)
            (directory / "kubeconfig").write_text(yaml.safe_dump({"apiVersion": "v1", "kind": "Config", "clusters": [{"name": "fixture", "cluster": {"server": f"http://127.0.0.1:{server.server_port}"}}], "contexts": [{"name": "fixture", "context": {"cluster": "fixture", "user": "fixture"}}], "current-context": "fixture", "users": [{"name": "fixture", "user": {}}]}))
            command = [str(args.binary.resolve()), "--custom-resource-state-only=true", f"--custom-resource-state-config-file={directory / 'config.yml'}", f"--kubeconfig={directory / 'kubeconfig'}", "--host=127.0.0.1", "--telemetry-host=127.0.0.1", f"--port={metrics_port}", f"--telemetry-port={telemetry_port}"]
            with (args.output / "process.log").open("w") as log:
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, cwd=directory, env={"PATH": "/usr/bin:/bin", "HOME": str(directory)})
                try:
                    for attempt in range(60):
                        try:
                            with urllib.request.urlopen(f"http://127.0.0.1:{metrics_port}/metrics", timeout=1) as response:
                                metrics = response.read().decode()
                            (args.output / "metrics.txt").write_text(metrics)
                            updated = re.search(r'^trivy_report_updated_timestamp_seconds\{[^\n]*\} ([^\n]+)', metrics, re.M)
                            created = re.search(r'^trivy_report_created_timestamp_seconds\{[^\n]*\} ([^\n]+)', metrics, re.M)
                            if updated and created:
                                assert float(updated[1]) == datetime.datetime(2026, 10, 15, 12, tzinfo=datetime.timezone.utc).timestamp()
                                assert float(created[1]) == datetime.datetime(2026, 10, 14, 12, tzinfo=datetime.timezone.utc).timestamp()
                                ports = {"metrics": metrics_port, "telemetry": telemetry_port}
                                for probe in ["readinessProbe", "livenessProbe"]:
                                    route = container[probe]["httpGet"]
                                    with urllib.request.urlopen(f"http://127.0.0.1:{ports[route['port']]}{route['path']}", timeout=2) as response:
                                        assert response.status == 200
                                assert not any("sendInitialEvents" in r["query"] for r in requests)
                                (args.output / "metrics.txt").write_text(metrics)
                                result.update(passed=True, updated_timestamp=float(updated[1]), created_timestamp=float(created[1]), probes={"readyz_telemetry": 200, "livez_metrics": 200}, requests=requests)
                                break
                        except (urllib.error.URLError, TimeoutError):
                            pass
                        if process.poll() is not None:
                            raise RuntimeError(f"KSM exited {process.returncode}")
                        time.sleep(1)
                    else:
                        raise RuntimeError("Expected report timestamps/probes did not become available; inspect fixture request and process logs")
                finally:
                    process.terminate()
                    process.wait(timeout=15)
    finally:
        stop.set()
        server.shutdown()
        server.server_close()
        result["requests"] = requests
        (args.output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
