"""
Shared Testinfra fixtures for all molecule scenarios.
"""

import pytest


@pytest.fixture
def mailserver_base_path():
    """Return the base path for mailserver installation."""
    return "/opt/mailserver"


@pytest.fixture
def docker_compose_path(mailserver_base_path):
    """Return path to docker-compose.yaml."""
    return f"{mailserver_base_path}/docker-compose.yaml"
