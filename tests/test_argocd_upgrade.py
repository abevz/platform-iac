#!/usr/bin/env python3
"""Exercise actual JSON Patch application, preservation, drift rejection and rollback."""

import copy
import importlib.util
from pathlib import Path
import unittest

import jinja2
import jsonpatch
import yaml

ROOT = Path(__file__).resolve().parents[1]
ROLE = ROOT / "config/roles/argocd_install"
SPEC = importlib.util.spec_from_file_location(
    "upgrade", ROLE / "filter_plugins/upgrade.py"
)
UPGRADE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPGRADE)
DEFAULTS = yaml.safe_load((ROLE / "defaults/main.yml").read_text())
RELEASES = DEFAULTS["argocd_releases"]


def fixture(name="argocd-repo-server"):
    """Model a live resource with local configuration and an unrelated sidecar."""
    old = RELEASES["v3.4.2"]
    main_name = {
        "argocd-dex-server": "dex",
        "argocd-redis": "redis",
    }.get(name, name)
    image = old["dex_image"] if main_name == "dex" else old["image"]
    if main_name == "redis":
        image = "public.ecr.aws/docker/library/redis:8.2.3-alpine"
    spec = {
        "nodeSelector": {"node-role.kubernetes.io/control-plane": ""},
        "containers": [
            {"name": "sidecar", "image": "example/sidecar:1"},
            {
                "name": main_name,
                "image": image,
                "env": [{"name": "ARGOCD_SERVER_INSECURE", "value": "true"}],
                "args": ["--existing-local-argument"],
                "volumeMounts": [{"name": "local", "mountPath": "/local"}],
            },
        ],
        "volumes": [
            {"name": "local", "emptyDir": {}},
            {
                "name": "argocd-cmd-params-cm",
                "configMap": {"name": "argocd-cmd-params-cm"},
            },
        ],
    }
    if name in ["argocd-dex-server", "argocd-redis", "argocd-repo-server"]:
        spec["initContainers"] = [
            {
                "name": (
                    "secret-init" if name == "argocd-redis" else "copyutil"
                ),
                "image": old["image"],
                "securityContext": {"readOnlyRootFilesystem": True},
            }
        ]
    return {
        "apiVersion": "apps/v1",
        "kind": (
            "StatefulSet"
            if name == "argocd-application-controller"
            else "Deployment"
        ),
        "metadata": {
            "name": name,
            "namespace": "argocd",
            "uid": "existing-workload",
            "annotations": {"local": "preserve"},
        },
        "spec": {
            "replicas": 1,
            "template": {
                "metadata": {"annotations": {"checksum/local": "preserve"}},
                "spec": spec,
            },
        },
    }


def plan(resource, version="v3.4.10"):
    return UPGRADE.argocd_image_patch(resource, RELEASES, version)


class UpgradeTests(unittest.TestCase):
    def test_bootstrap_pins_before_apply_and_preserves_configuration(self):
        resources = [fixture(name) for name in UPGRADE.WORKLOADS]
        for resource in resources:
            del resource["metadata"]["uid"]
        resources += [
            {
                "kind": "ConfigMap",
                "metadata": {"name": "argocd-cm"},
                "data": {"url": "https://example.test"},
            },
            {"kind": "Secret", "metadata": {"name": "argocd-secret"}},
        ]
        before = copy.deepcopy(resources)
        for version in RELEASES:
            result = UPGRADE.argocd_bootstrap_manifest(
                resources, RELEASES, version
            )
            for old, new in zip(before[:7], result[:7]):
                expected = copy.deepcopy(old)
                for collection, containers in UPGRADE.WORKLOADS[
                    old["metadata"]["name"]
                ][1].items():
                    for container in expected["spec"]["template"]["spec"][
                        collection
                    ]:
                        if container["name"] in containers:
                            container["image"] = RELEASES[version][
                                containers[container["name"]]
                            ]
                self.assertEqual(new, expected)
            self.assertEqual(result[7:], before[7:])
        self.assertEqual(resources, before)
        for invalid in [resources[1:], resources + [resources[0]]]:
            with self.assertRaises(ValueError):
                UPGRADE.argocd_bootstrap_manifest(invalid, RELEASES, "v3.4.10")
        invalid = copy.deepcopy(resources)
        invalid[0]["spec"]["template"]["spec"]["containers"][1][
            "image"
        ] = "unexpected:latest"
        with self.assertRaises(ValueError):
            UPGRADE.argocd_bootstrap_manifest(invalid, RELEASES, "v3.4.10")

    def test_bootstrap_gate_rejects_existing_partial_installation(self):
        tasks = yaml.safe_load((ROLE / "tasks/present.yml").read_text())
        gate = next(
            t for t in tasks if t["name"].startswith("Refuse bootstrap")
        )
        expression = gate["ansible.builtin.assert"]["that"][0]
        template = jinja2.Environment().from_string("{{ " + expression + " }}")
        for controller, namespace, allowed in [
            (0, 1, False),
            (0, 0, True),
            (1, 1, True),
        ]:
            value = template.render(
                argocd_existing_controller={"resources": [{}] * controller},
                argocd_existing_namespace={"resources": [{}] * namespace},
            )
            self.assertEqual(value, str(allowed))

    def test_upgrade_and_rollback_preserve_local_configuration_for_all_workloads(
        self,
    ):
        names = [
            "argocd-application-controller",
            "argocd-applicationset-controller",
            "argocd-dex-server",
            "argocd-notifications-controller",
            "argocd-redis",
            "argocd-repo-server",
            "argocd-server",
        ]
        self.assertEqual(
            set(names), {x["name"] for x in DEFAULTS["argocd_workloads"]}
        )
        for name in names:
            with self.subTest(name=name):
                before = fixture(name)
                after = jsonpatch.apply_patch(before, plan(before))
                restored = jsonpatch.apply_patch(after, plan(after, "v3.4.2"))
                self.assertEqual(before, restored)
                self.assertEqual(plan(after), [])
                changes = jsonpatch.make_patch(before, after).patch
                self.assertTrue(changes)
                for change in changes:
                    self.assertTrue(
                        change["path"].endswith("/image")
                        or "/volumeMounts/" in change["path"],
                        change,
                    )
                self.assertEqual(
                    after["spec"]["template"]["spec"]["containers"][0][
                        "image"
                    ],
                    "example/sidecar:1",
                )
                self.assertEqual(before["metadata"], after["metadata"])
                if name == "argocd-redis":
                    self.assertEqual(
                        before["spec"]["template"]["spec"]["containers"],
                        after["spec"]["template"]["spec"]["containers"],
                    )

    def test_existing_unpinned_tags_are_replaced_with_reviewed_digests(self):
        before = fixture("argocd-dex-server")
        spec = before["spec"]["template"]["spec"]
        spec["containers"][1]["image"] = "ghcr.io/dexidp/dex:v2.45.0"
        spec["initContainers"][0]["image"] = "quay.io/argoproj/argocd:v3.4.2"
        after = jsonpatch.apply_patch(before, plan(before))
        self.assertEqual(
            after["spec"]["template"]["spec"]["containers"][1]["image"],
            RELEASES["v3.4.10"]["dex_image"],
        )
        self.assertEqual(
            after["spec"]["template"]["spec"]["initContainers"][0]["image"],
            RELEASES["v3.4.10"]["image"],
        )

    def test_concurrent_image_change_is_rejected_atomically(self):
        before = fixture()
        patch = plan(before)
        changed = copy.deepcopy(before)
        changed["spec"]["template"]["spec"]["containers"][1][
            "image"
        ] = "unexpected/image:2"
        with self.assertRaises(jsonpatch.JsonPatchTestFailed):
            jsonpatch.apply_patch(changed, patch)
        self.assertEqual(
            changed["spec"]["template"]["spec"]["containers"][1]["image"],
            "unexpected/image:2",
        )

    def test_recreated_resource_or_reordered_container_is_rejected(self):
        for field in ["uid", "containers"]:
            with self.subTest(field=field):
                before = fixture()
                changed = copy.deepcopy(before)
                if field == "uid":
                    changed["metadata"]["uid"] = "replacement"
                else:
                    changed["spec"]["template"]["spec"]["containers"].reverse()
                with self.assertRaises(jsonpatch.JsonPatchTestFailed):
                    jsonpatch.apply_patch(changed, plan(before))

    def test_concurrent_mount_change_is_rejected(self):
        before = fixture()
        changed = copy.deepcopy(before)
        changed["spec"]["template"]["spec"]["containers"][1][
            "volumeMounts"
        ].append({"name": "another", "mountPath": "/another"})
        with self.assertRaises(jsonpatch.JsonPatchTestFailed):
            jsonpatch.apply_patch(changed, plan(before))

    def test_unreviewed_image_release_and_mount_are_rejected(self):
        for defect in ["image", "mount", "volume", "container", "uid", "kind"]:
            with self.subTest(defect=defect):
                resource = fixture()
                spec = resource["spec"]["template"]["spec"]
                if defect == "image":
                    spec["containers"][1][
                        "image"
                    ] = "quay.io/argoproj/argocd:v3.5.4"
                elif defect == "mount":
                    spec["containers"][1]["volumeMounts"].append(
                        {"name": "custom", "mountPath": "/home/argocd/params"}
                    )
                elif defect == "volume":
                    spec["volumes"] = []
                elif defect == "container":
                    spec["containers"].pop()
                elif defect == "uid":
                    del resource["metadata"]["uid"]
                else:
                    resource["kind"] = "StatefulSet"
                with self.assertRaises(ValueError):
                    plan(resource)
        with self.assertRaises(ValueError):
            plan(fixture(), "v3.5.4")

    def test_rollback_removes_only_the_added_params_mount(self):
        before = fixture()
        after = jsonpatch.apply_patch(before, plan(before))
        mounts = after["spec"]["template"]["spec"]["containers"][1][
            "volumeMounts"
        ]
        self.assertEqual(
            mounts,
            [{"name": "local", "mountPath": "/local"}, UPGRADE.PARAMS_MOUNT],
        )
        self.assertEqual(
            jsonpatch.apply_patch(after, plan(after, "v3.4.2")), before
        )

    def test_empty_requested_version_uses_default_and_url_tracks_it(self):
        tasks = yaml.safe_load((ROLE / "tasks/present.yml").read_text())
        expression = tasks[0]["ansible.builtin.set_fact"][
            "argocd_target_version"
        ]
        env = jinja2.Environment(undefined=jinja2.StrictUndefined)
        for requested, expected in [("", "v3.4.10"), ("v3.4.2", "v3.4.2")]:
            target = env.from_string(expression).render(
                requested_version=requested, **DEFAULTS
            )
            self.assertEqual(target, expected)
            url = env.from_string(DEFAULTS["argocd_install_url"]).render(
                argocd_target_version=target
            )
            self.assertIn("/" + expected + "/", url)


if __name__ == "__main__":
    unittest.main()
