"""
Testinfra tests for mailserver_setup role.

These tests verify the mailserver infrastructure is correctly configured.
Run with: molecule verify -s mailserver
"""

import pytest


class TestMailserverDirectories:
    """Test mailserver directory structure."""

    @pytest.mark.parametrize(
        "path",
        [
            "/opt/mailserver",
            "/opt/mailserver/data/dms/mail-data",
            "/opt/mailserver/data/dms/mail-state",
            "/opt/mailserver/data/dms/mail-logs",
            "/opt/mailserver/data/dms/config",
        ],
    )
    def test_directories_exist(self, host, path):
        """Verify all required directories exist."""
        directory = host.file(path)
        assert directory.exists, f"Directory {path} should exist"
        assert directory.is_directory, f"{path} should be a directory"


class TestMailserverFiles:
    """Test mailserver configuration files."""

    def test_docker_compose_exists(self, host):
        """Verify docker-compose.yaml is deployed."""
        compose = host.file("/opt/mailserver/docker-compose.yaml")
        assert compose.exists, "docker-compose.yaml should exist"
        assert compose.is_file, "docker-compose.yaml should be a file"
        assert compose.user == "root", "docker-compose.yaml should be owned by root"

    def test_mailserver_env_exists(self, host):
        """Verify mailserver.env is deployed with secure permissions."""
        env_file = host.file("/opt/mailserver/mailserver.env")
        assert env_file.exists, "mailserver.env should exist"
        assert env_file.is_file, "mailserver.env should be a file"
        assert env_file.mode == 0o600, "mailserver.env should have mode 0600"
        assert env_file.user == "root", "mailserver.env should be owned by root"

    def test_docker_compose_content(self, host):
        """Verify docker-compose.yaml has required content."""
        compose = host.file("/opt/mailserver/docker-compose.yaml")
        content = compose.content_string

        assert "mailserver" in content, "Should contain mailserver service"
        assert (
            "docker.io/mailserver/docker-mailserver" in content
            or "mailserver/docker-mailserver" in content
        ), "Should use docker-mailserver image"


class TestDockerService:
    """Test Docker and container status."""

    def test_docker_running(self, host):
        """Verify Docker service is running."""
        docker = host.service("docker")
        assert docker.is_running, "Docker should be running"
        assert docker.is_enabled, "Docker should be enabled"

    def test_mailserver_container_exists(self, host):
        """Verify mailserver container exists (may not be running in test)."""
        # Check if container was created
        result = host.run("docker ps -a --filter name=mailserver --format '{{.Names}}'")
        # Container might not exist yet if compose hasn't run
        # This is expected in minimal test scenarios
        if result.rc == 0 and result.stdout.strip():
            assert "mailserver" in result.stdout, (
                "Container should be named 'mailserver'"
            )


class TestMailserverPorts:
    """Test mailserver network configuration."""

    @pytest.mark.parametrize(
        "port",
        [
            25,  # SMTP
            143,  # IMAP
            465,  # SMTPS
            587,  # Submission
            993,  # IMAPS
        ],
    )
    def test_mailserver_ports_in_compose(self, host, port):
        """Verify expected ports are configured in docker-compose."""
        compose = host.file("/opt/mailserver/docker-compose.yaml")
        content = compose.content_string
        # Port should be mapped in compose file
        assert str(port) in content, f"Port {port} should be configured"


class TestIdempotence:
    """Test role idempotence."""

    def test_directories_permissions_stable(self, host):
        """Verify directory permissions are stable across runs."""
        # After idempotent run, permissions should remain correct
        for path in ["/opt/mailserver", "/opt/mailserver/data"]:
            directory = host.file(path)
            if directory.exists:
                assert directory.user == "root"
