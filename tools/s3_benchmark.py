#!/usr/bin/env python3
"""Small S3 PUT/HEAD/GET benchmark using only Python stdlib.

This intentionally avoids requiring `mc` or AWS CLI on the operator machine.
The wrapper supplies credentials through environment variables loaded from SOPS.
"""

from __future__ import annotations

import csv
import datetime as dt
import hashlib
import hmac
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


def getenv_required(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"ERROR: {name} is required")
    return value


def split_sizes(value: str) -> list[int]:
    try:
        return [int(item) for item in value.split()]
    except ValueError as exc:
        raise SystemExit(f"ERROR: invalid S3_BENCH_SIZES value: {value}") from exc


def signing_key(secret_key: str, date_stamp: str, region: str) -> bytes:
    key = ("AWS4" + secret_key).encode("utf-8")
    for part in (date_stamp, region, "s3", "aws4_request"):
        key = hmac.new(key, part.encode("utf-8"), hashlib.sha256).digest()
    return key


class S3Client:
    def __init__(self) -> None:
        endpoint = getenv_required("S3_BENCH_ENDPOINT").rstrip("/")
        parsed = urllib.parse.urlsplit(endpoint)
        if not parsed.scheme or not parsed.netloc:
            raise SystemExit(f"ERROR: invalid S3_BENCH_ENDPOINT: {endpoint}")

        self.scheme = parsed.scheme
        self.netloc = parsed.netloc
        self.base_path = parsed.path.rstrip("/")
        self.access_key = getenv_required("S3_BENCH_ACCESS_KEY")
        self.secret_key = getenv_required("S3_BENCH_SECRET_KEY")
        self.region = os.environ.get("S3_BENCH_REGION", "us-east-1")
        self.timeout = float(os.environ.get("S3_BENCH_TIMEOUT", "120"))

        self.context = None
        if os.environ.get("S3_BENCH_INSECURE") == "1":
            self.context = ssl._create_unverified_context()  # noqa: S323

    def request(self, method: str, path: str, body: bytes = b"") -> bytes:
        request_path = f"{self.base_path}{path}"
        encoded_path = urllib.parse.quote(request_path, safe="/-_.~")
        url = urllib.parse.urlunsplit((self.scheme, self.netloc, encoded_path, "", ""))

        now = dt.datetime.now(dt.UTC)
        amz_date = now.strftime("%Y%m%dT%H%M%SZ")
        date_stamp = now.strftime("%Y%m%d")
        payload_hash = hashlib.sha256(body).hexdigest()

        headers = {
            "host": self.netloc,
            "x-amz-content-sha256": payload_hash,
            "x-amz-date": amz_date,
        }
        signed_headers = ";".join(sorted(headers))
        canonical_headers = "".join(f"{name}:{headers[name]}\n" for name in sorted(headers))
        canonical_request = "\n".join(
            [
                method,
                encoded_path,
                "",
                canonical_headers,
                signed_headers,
                payload_hash,
            ]
        )

        scope = f"{date_stamp}/{self.region}/s3/aws4_request"
        string_to_sign = "\n".join(
            [
                "AWS4-HMAC-SHA256",
                amz_date,
                scope,
                hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
            ]
        )
        signature = hmac.new(
            signing_key(self.secret_key, date_stamp, self.region),
            string_to_sign.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()

        request_headers = {
            "Authorization": (
                "AWS4-HMAC-SHA256 "
                f"Credential={self.access_key}/{scope}, "
                f"SignedHeaders={signed_headers}, "
                f"Signature={signature}"
            ),
            "X-Amz-Content-Sha256": payload_hash,
            "X-Amz-Date": amz_date,
        }

        data = body if method in {"PUT", "POST"} else None
        request = urllib.request.Request(url, data=data, headers=request_headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=self.timeout, context=self.context) as response:
                return response.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read(300).decode("utf-8", errors="replace")
            raise RuntimeError(f"{method} {path} failed: HTTP {exc.code} {detail}") from exc

    def bucket_exists(self, bucket: str) -> bool:
        try:
            self.request("HEAD", f"/{bucket}")
            return True
        except RuntimeError as exc:
            if "HTTP 404" in str(exc):
                return False
            raise

    def make_bucket(self, bucket: str) -> None:
        self.request("PUT", f"/{bucket}")

    def remove_bucket(self, bucket: str) -> None:
        self.request("DELETE", f"/{bucket}")

    def put_object(self, bucket: str, key: str, payload: bytes) -> None:
        self.request("PUT", f"/{bucket}/{key}", payload)

    def stat_object(self, bucket: str, key: str) -> None:
        self.request("HEAD", f"/{bucket}/{key}")

    def get_object(self, bucket: str, key: str) -> bytes:
        return self.request("GET", f"/{bucket}/{key}")

    def delete_object(self, bucket: str, key: str) -> None:
        self.request("DELETE", f"/{bucket}/{key}")


def mib_per_sec(size: int, seconds: float) -> str:
    if seconds <= 0:
        return "inf"
    return f"{size / seconds / 1024 / 1024:.2f}"


def measure(callable_obj) -> tuple[float, object]:
    start = time.perf_counter()
    result = callable_obj()
    return time.perf_counter() - start, result


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] in {"-h", "--help"}:
        print(
            "Usage: S3_BENCH_ENDPOINT=... S3_BENCH_ACCESS_KEY=... "
            "S3_BENCH_SECRET_KEY=... tools/s3_benchmark.py",
            file=sys.stderr,
        )
        return 0

    client = S3Client()
    bucket = os.environ.get("S3_BENCH_BUCKET", "platform-iac-s3-bench")
    prefix = os.environ.get("S3_BENCH_PREFIX", f"{dt.datetime.now(dt.UTC):%Y%m%dT%H%M%SZ}-{os.getpid()}")
    sizes = split_sizes(os.environ.get("S3_BENCH_SIZES", "4096 1048576 67108864"))
    iterations = int(os.environ.get("S3_BENCH_ITERATIONS", "3"))
    keep = os.environ.get("S3_BENCH_KEEP") == "1"

    created_bucket = False
    objects: list[str] = []
    writer = csv.writer(sys.stdout)
    writer.writerow(["op", "size_bytes", "iteration", "seconds", "mib_per_sec", "object"])

    try:
        if not client.bucket_exists(bucket):
            client.make_bucket(bucket)
            created_bucket = True

        for size in sizes:
            payload = os.urandom(size)
            for iteration in range(1, iterations + 1):
                key = f"{prefix}/{size}-{iteration}.bin"
                objects.append(key)

                seconds, _ = measure(lambda: client.put_object(bucket, key, payload))
                writer.writerow(["put", size, iteration, f"{seconds:.6f}", mib_per_sec(size, seconds), key])

                seconds, _ = measure(lambda: client.stat_object(bucket, key))
                writer.writerow(["stat", size, iteration, f"{seconds:.6f}", "", key])

                seconds, downloaded = measure(lambda: client.get_object(bucket, key))
                if len(downloaded) != size:
                    raise RuntimeError(f"GET {key} returned {len(downloaded)} bytes, expected {size}")
                writer.writerow(["get", size, iteration, f"{seconds:.6f}", mib_per_sec(size, seconds), key])
    finally:
        sys.stdout.flush()
        if not keep:
            for key in reversed(objects):
                try:
                    client.delete_object(bucket, key)
                except Exception as exc:  # pragma: no cover - cleanup best effort
                    print(f"WARN: failed to delete {bucket}/{key}: {exc}", file=sys.stderr)
            if created_bucket:
                try:
                    client.remove_bucket(bucket)
                except Exception as exc:  # pragma: no cover - cleanup best effort
                    print(f"WARN: failed to delete bucket {bucket}: {exc}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
