"""Build narrowly scoped RFC 6902 patches for the reviewed Argo CD releases."""

import copy

WORKLOADS = {
    "argocd-applicationset-controller": (
        "Deployment",
        {"containers": {"argocd-applicationset-controller": "image"}},
    ),
    "argocd-dex-server": (
        "Deployment",
        {
            "containers": {"dex": "dex_image"},
            "initContainers": {"copyutil": "image"},
        },
    ),
    "argocd-notifications-controller": (
        "Deployment",
        {"containers": {"argocd-notifications-controller": "image"}},
    ),
    "argocd-redis": (
        "Deployment",
        {"initContainers": {"secret-init": "image"}},
    ),
    "argocd-repo-server": (
        "Deployment",
        {
            "containers": {"argocd-repo-server": "image"},
            "initContainers": {"copyutil": "image"},
        },
    ),
    "argocd-server": (
        "Deployment",
        {"containers": {"argocd-server": "image"}},
    ),
    "argocd-application-controller": (
        "StatefulSet",
        {"containers": {"argocd-application-controller": "image"}},
    ),
}
PARAMS_MOUNT = {
    "mountPath": "/home/argocd/params",
    "name": "argocd-cmd-params-cm",
}


def argocd_image_patch(resource, releases, target_version):
    """Keep configuration intact and reject image/layout drift atomically."""
    if target_version not in ("v3.4.2", "v3.4.10"):
        raise ValueError("No reviewed workload patch for this Argo CD version")
    name = resource["metadata"]["name"]
    if name not in WORKLOADS or resource["kind"] != WORKLOADS[name][0]:
        raise ValueError("Unexpected Argo CD workload identity")
    target = releases[target_version]
    spec = resource["spec"]["template"]["spec"]
    patch = []
    for collection, expected in WORKLOADS[name][1].items():
        containers = spec.get(collection, [])
        for container_name, image_key in expected.items():
            matches = [
                (i, c)
                for i, c in enumerate(containers)
                if c["name"] == container_name
            ]
            if len(matches) != 1:
                raise ValueError(
                    "Missing or duplicate expected Argo CD container"
                )
            index, container = matches[0]
            allowed = {release[image_key] for release in releases.values()}
            allowed.update(image.split("@")[0] for image in list(allowed))
            if container["image"] not in allowed:
                raise ValueError(
                    "Unexpected current image; refresh the reviewed baseline"
                )
            if container["image"] != target[image_key]:
                path = f"/spec/template/spec/{collection}/{index}"
                patch.extend(
                    [
                        {
                            "op": "test",
                            "path": path + "/name",
                            "value": container_name,
                        },
                        {
                            "op": "test",
                            "path": path + "/image",
                            "value": container["image"],
                        },
                        {
                            "op": "replace",
                            "path": path + "/image",
                            "value": target[image_key],
                        },
                    ]
                )
    if name == "argocd-repo-server":
        index = next(
            i for i, c in enumerate(spec["containers"]) if c["name"] == name
        )
        mounts = spec["containers"][index].get("volumeMounts", [])
        matches = [
            (i, m)
            for i, m in enumerate(mounts)
            if m["mountPath"] == PARAMS_MOUNT["mountPath"]
        ]
        if len(matches) > 1 or (matches and matches[0][1] != PARAMS_MOUNT):
            raise ValueError(
                "Unexpected params mount; preserve and review the local override"
            )
        mount_path = f"/spec/template/spec/containers/{index}/volumeMounts"
        if target_version == "v3.4.10" and not matches:
            volumes = [
                v
                for v in spec.get("volumes", [])
                if v["name"] == PARAMS_MOUNT["name"]
            ]
            if (
                len(volumes) != 1
                or volumes[0].get("configMap", {}).get("name")
                != PARAMS_MOUNT["name"]
            ):
                raise ValueError(
                    "Expected repo-server ConfigMap volume is missing"
                )
            if "volumeMounts" not in spec["containers"][index]:
                raise ValueError(
                    "Expected repo-server mount layout is missing"
                )
            patch.extend(
                [
                    {"op": "test", "path": mount_path, "value": mounts},
                    {
                        "op": "add",
                        "path": mount_path + "/-",
                        "value": dict(PARAMS_MOUNT),
                    },
                ]
            )
        elif target_version == "v3.4.2" and matches:
            patch.extend(
                [
                    {"op": "test", "path": mount_path, "value": mounts},
                    {"op": "remove", "path": mount_path + f"/{matches[0][0]}"},
                ]
            )
    if patch:
        uid = resource["metadata"].get("uid")
        if not uid:
            raise ValueError("A live workload UID is required")
        patch.insert(0, {"op": "test", "path": "/metadata/uid", "value": uid})
    return patch


def argocd_bootstrap_manifest(documents, releases, target_version):
    """Pin a complete verified upstream manifest before its first apply."""
    if target_version not in ("v3.4.2", "v3.4.10"):
        raise ValueError("No reviewed bootstrap for this Argo CD version")
    result = copy.deepcopy(documents)
    seen = set()
    for resource in result:
        if not resource or resource.get("kind") not in (
            "Deployment",
            "StatefulSet",
            "DaemonSet",
            "Job",
            "CronJob",
            "Pod",
        ):
            continue
        name = resource["metadata"]["name"]
        if (
            name not in WORKLOADS
            or name in seen
            or resource["kind"] != WORKLOADS[name][0]
        ):
            raise ValueError("Unexpected bootstrap workload identity")
        seen.add(name)
        spec = resource["spec"]["template"]["spec"]
        for collection, expected in WORKLOADS[name][1].items():
            for container_name, image_key in expected.items():
                matches = [
                    c
                    for c in spec.get(collection, [])
                    if c["name"] == container_name
                ]
                if len(matches) != 1:
                    raise ValueError(
                        "Missing or duplicate bootstrap container"
                    )
                allowed = {r[image_key] for r in releases.values()}
                allowed.update(image.split("@")[0] for image in list(allowed))
                if matches[0]["image"] not in allowed:
                    raise ValueError("Unexpected bootstrap image")
                matches[0]["image"] = releases[target_version][image_key]
    if seen != set(WORKLOADS):
        raise ValueError("Incomplete bootstrap workload manifest")
    return result


class FilterModule:
    """Expose the guarded patch builder to Ansible."""

    def filters(self):
        """Return the role's filter names."""
        return {
            "argocd_image_patch": argocd_image_patch,
            "argocd_bootstrap_manifest": argocd_bootstrap_manifest,
        }
