#!/bin/bash

# Function to enter container network namespace (CRI-O/Containerd)
# Usage: source knet.sh; knet <pod_name>

function knet() {
    if [ -z "$1" ]; then
        echo "Usage: knet <partial_pod_name>"
        return 1
    fi

    # Find container ID (2>/dev/null suppresses crictl noise)
    local container_id=$(sudo crictl ps --name "$1" --state Running -q 2>/dev/null | head -n 1)

    if [ -z "$container_id" ]; then
        echo "Container with name '$1' not found."
        return 1
    fi

    local pid=$(sudo crictl inspect --output go-template --template '{{.info.pid}}' "$container_id" 2>/dev/null)

    if [ -z "$pid" ]; then
        echo "Failed to get PID."
        return 1
    fi

    echo "Entering container network: $1 (PID: $pid)"
    echo "Filesystem remains from HOST. Host utilities are available."

    # Pass bash command: "Set red prompt and stay in shell"
    # --norc prevents .bashrc from overwriting our custom prompt
    sudo nsenter -t "$pid" -n /bin/bash --norc -c "export PS1='\[\e[1;31m\](CONTAINER-NET)\[\e[0m\] \u@\h:\w\$ '; exec /bin/bash --norc"
}
