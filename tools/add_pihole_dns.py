#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
import yaml
import urllib.parse
import os
import requests

def get_sops_decoded_secrets(secrets_file_path):
    """Decrypts the SOPS file and returns the data."""
    try:
        process = subprocess.run(
            ['sops', '-d', secrets_file_path],
            capture_output=True,
            text=True,
            check=True
        )
        return yaml.safe_load(process.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error decrypting SOPS file: {e}", file=sys.stderr)
        print(f"Stdout: {e.stdout}", file=sys.stderr)
        print(f"Stderr: {e.stderr}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print("Error: 'sops' command not found. Please ensure SOPS is installed and in your PATH.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"An unexpected error occurred while handling SOPS file: {e}", file=sys.stderr)
        sys.exit(1)

def authenticate_pihole(pihole_ip, web_password):
    """Authenticates to Pi-hole and returns session ID (SID) and CSRF token."""
    auth_url = f"http://{pihole_ip}/api/auth"
    payload = {"password": web_password}
    headers = {"Content-Type": "application/json"} # Add Content-Type header
    print(f"Attempting to authenticate to Pi-hole at {pihole_ip} with JSON payload.")
    try:
        # Send payload as JSON
        response = requests.post(auth_url, data=json.dumps(payload), headers=headers, timeout=10)
        response.raise_for_status() # Raise an exception for bad status codes

        data = response.json()
        if data.get("session") and data["session"].get("valid") is True:
            sid = data["session"].get("sid")
            csrf_token = data["session"].get("csrf")
            if sid and csrf_token:
                print("Authentication successful. SID and CSRF token obtained.")
                return {"sid": sid, "csrf": csrf_token}
            else:
                print(f"Authentication succeeded but SID or CSRF token missing in response: {data}")
                return None
        else:
            print(f"Authentication failed. Response: {data}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"Error during Pi-hole authentication: {e}")
        # If the error is an HTTPError, print the response content for more details
        if isinstance(e, requests.exceptions.HTTPError) and e.response is not None:
            print(f"Pi-hole auth error response: {e.response.status_code} - {e.response.text}")
        return None
    except json.JSONDecodeError as e:
        print(f"Error decoding JSON from Pi-hole authentication response: {e}. Response text: {response.text}")
        return None

def get_dns_records(pihole_ip, sid, csrf_token, debug=False):
    """Get all custom DNS records from Pi-hole.

    Tries multiple API endpoints that might exist in different Pi-hole versions.
    """
    # Use same endpoints as the add/delete operations
    # And also try some other common endpoints for different Pi-hole versions
    api_endpoints = [
        "/api/config/dns/hosts",
        "/api/dns/customdns",
        "/admin/api.php?customdns",
        "/api/customdns"
    ]

    print(f"Fetching current DNS records from Pi-hole...")

    for endpoint in api_endpoints:
        api_url = f"http://{pihole_ip}{endpoint}"

        command_parts = [
            'curl', '-s',
            '-H', "Content-Type: application/json",
            '-H', f"X-CSRF-Token: {csrf_token}",
            '--cookie', f"SID={sid}",
            api_url
        ]

        if debug:
            print(f"DEBUG: Trying Pi-hole API endpoint: {endpoint}")
            print(f"DEBUG_COMMAND: {' '.join(command_parts)}")

        try:
            result = subprocess.run(command_parts, capture_output=True, text=True, check=False)
            response_text = result.stdout.strip()

            if debug:
                print(f"DEBUG: Pi-hole endpoint {endpoint} response: '{response_text[:100]}...' (Return code: {result.returncode})")

            if result.returncode == 0 and response_text:
                try:
                    response_json = json.loads(response_text)

                    # Different Pi-hole API versions might return data in different formats
                    # Let's handle various known response formats:

                    # Case 1: Direct list of records
                    if isinstance(response_json, list):
                        print(f"Successfully retrieved {len(response_json)} DNS records from Pi-hole using endpoint {endpoint}.")
                        return response_json

                    # Case 2: Data in a "data" field
                    elif isinstance(response_json, dict) and "data" in response_json and isinstance(response_json["data"], list):
                        print(f"Successfully retrieved {len(response_json['data'])} DNS records from Pi-hole using endpoint {endpoint}.")
                        return response_json["data"]

                    # Case 3: Specific format with "customdns" field (some Pi-hole versions)
                    elif isinstance(response_json, dict) and "customdns" in response_json and isinstance(response_json["customdns"], list):
                        print(f"Successfully retrieved {len(response_json['customdns'])} DNS records from Pi-hole using endpoint {endpoint}.")
                        return response_json["customdns"]

                    # Case 4: Data in a nested structure (config -> dns -> hosts)
                    elif isinstance(response_json, dict) and "config" in response_json and isinstance(response_json["config"], dict) and \
                         "dns" in response_json["config"] and isinstance(response_json["config"]["dns"], dict) and \
                         "hosts" in response_json["config"]["dns"]:
                        hosts = response_json["config"]["dns"]["hosts"]
                        if isinstance(hosts, list):
                            # Parse entries like "10.10.10.187 pi.alert" into structured records
                            records = []
                            for entry in hosts:
                                if isinstance(entry, str) and " " in entry:
                                    parts = entry.split(" ", 1)
                                    if len(parts) == 2:
                                        ip = parts[0].strip()
                                        domain = parts[1].strip()
                                        records.append({"domain": domain, "ip": ip})
                            print(f"Successfully retrieved {len(records)} DNS records from Pi-hole using endpoint {endpoint}.")
                            return records

                    # Case 5: Empty but valid response (no custom records)
                    elif isinstance(response_json, dict) and ("success" in response_json or "took" in response_json):
                        print(f"Pi-hole responded successfully, but no custom DNS records found (endpoint {endpoint}).")
                        return []

                    elif debug:
                        print(f"DEBUG: Endpoint {endpoint} returned unexpected format: {json.dumps(response_json, indent=2)[:200]}...")

                except json.JSONDecodeError:
                    if debug:
                        print(f"DEBUG: Failed to parse response from endpoint {endpoint} as JSON: {response_text[:100]}...")

            # Continue to the next endpoint if this one didn't work

        except Exception as e:
            if debug:
                print(f"DEBUG: Error trying endpoint {endpoint}: {e}")

    # If we reach here, we couldn't get records from any endpoint
    print("Warning: Unable to retrieve custom DNS records from any Pi-hole API endpoint.")

    # As a last resort, try to get custom.list directly via SSH
    print("Attempting to check if there are entries in custom.list file on Pi-hole...")

    # Just tell the user there might be records we can't retrieve
    print("Note: There might be DNS records in Pi-hole that we couldn't retrieve via the API.")
    return []

    try:
        result = subprocess.run(command_parts, capture_output=True, text=True, check=False)
        response_text = result.stdout.strip()

        if debug:
            print(f"Pi-hole DNS API raw response: '{response_text}' (Return code: {result.returncode})")

        if result.returncode == 0:
            try:
                response_json = json.loads(response_text)
                if isinstance(response_json, list):
                    print(f"Successfully retrieved {len(response_json)} DNS records from Pi-hole.")
                    return response_json
                else:
                    print(f"Retrieved data is not a list: {response_json}")
                    return []
            except json.JSONDecodeError:
                print(f"Failed to parse Pi-hole response as JSON: {response_text}")
                return []
        else:
            print(f"Failed to get DNS records. curl command failed. Status: {result.returncode}", file=sys.stderr)
            print(f"Curl Stdout: {result.stdout.strip()}", file=sys.stderr)
            print(f"Curl Stderr: {result.stderr.strip()}", file=sys.stderr)
            return []
    except Exception as e:
        print(f"An unexpected error occurred during Pi-hole DNS API call: {e}", file=sys.stderr)
        return []

def add_dns_record(pihole_ip, sid, csrf_token, domain, ip_address, debug=False):
    """Adds a DNS record to Pi-hole via its API using PUT /api/config/dns/hosts/."""

    encoded_entry = urllib.parse.quote(f"{ip_address} {domain}")
    api_url = f"http://{pihole_ip}/api/config/dns/hosts/{encoded_entry}"

    command_parts = [
        'curl', '-s', '-X', 'PUT',
        '-H', "Content-Type: application/json",
        '-H', f"X-CSRF-Token: {csrf_token}",
        '--cookie', f"SID={sid}",
        api_url
    ]

    if debug:
        print(f"DEBUG_COMMAND: {' '.join(command_parts)}")

    print(f"Attempting to add/update DNS record: {domain} -> {ip_address}")

    try:
        result = subprocess.run(command_parts, capture_output=True, text=True, check=False)
        response_text = result.stdout.strip()
        print(f"Pi-hole DNS API raw response: '{response_text}' (Return code: {result.returncode})")

        if result.returncode == 0: # curl command executed successfully
            if not response_text: # Truly empty response
                print(f"Successfully added/updated DNS record for {domain} -> {ip_address} (empty response interpreted as success)")
                return True

            try:
                response_json = json.loads(response_text)
                if not isinstance(response_json, dict):
                    # If it's JSON but not a dictionary, it's unexpected.
                    print(f"Failed to add DNS record for {domain}. Unexpected JSON type (expected dict, got {type(response_json).__name__}): {response_text}", file=sys.stderr)
                    return False

                # Now we know response_json is a dictionary
                if response_json.get("success") is True:
                    message = response_json.get("message", "Action successful.") # Provide a default message
                    print(f"Successfully added/updated DNS record for {domain} -> {ip_address}. Pi-hole message: {message}")
                    return True
                elif "error" in response_json:
                    error_details = response_json.get("error", {})
                    error_message = error_details.get("message", "Unknown error")
                    if isinstance(error_details, dict):
                         hint = error_details.get("hint", "")
                         key = error_details.get("key", "N/A")
                         error_message = f"{key}: {error_message}. Hint: {hint}"
                    print(f"Failed to add DNS record for {domain}. Pi-hole API error: {error_message}", file=sys.stderr)
                    return False
                elif "took" in response_json: # This is the observed success case from user logs
                    print(f"Successfully added/updated DNS record for {domain} -> {ip_address} (API reported 'took': {response_json.get('took')}, interpreted as success)")
                    return True
                elif response_text == "{}": # Empty JSON object, sometimes used for success
                    print(f"Successfully added/updated DNS record for {domain} -> {ip_address} (empty JSON object '{{}}' interpreted as success)")
                    return True
                else:
                    # JSON dictionary, but not matching known success/error patterns
                    print(f"Failed to add DNS record for {domain}. Unexpected JSON dictionary content: {response_text}", file=sys.stderr)
                    return False

            except json.JSONDecodeError:
                # Non-JSON response (and not empty, as that's handled above)
                print(f"Failed to add DNS record for {domain}. Non-JSON response from Pi-hole: {response_text}", file=sys.stderr)
                return False
        else: # curl command itself failed
            print(f"Failed to add DNS record for {domain}. curl command failed. Status: {result.returncode}", file=sys.stderr)
            print(f"Curl Stdout: {result.stdout.strip()}", file=sys.stderr)
            print(f"Curl Stderr: {result.stderr.strip()}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"An unexpected error occurred during Pi-hole DNS API call: {e}", file=sys.stderr)
        return False

def delete_dns_record(pihole_ip, sid, csrf_token, domain, ip_address, debug=False):
    """Deletes a DNS record from Pi-hole via its API using DELETE /api/config/dns/hosts/."""

    encoded_entry = urllib.parse.quote(f"{ip_address} {domain}")
    api_url = f"http://{pihole_ip}/api/config/dns/hosts/{encoded_entry}"

    command_parts = [
        'curl', '-s', '-X', 'DELETE',
        '-H', "Content-Type: application/json", # Though not strictly needed for DELETE with no body
        '-H', f"X-CSRF-Token: {csrf_token}",
        '--cookie', f"SID={sid}",
        api_url
    ]

    if debug:
        print(f"DEBUG_COMMAND: {' '.join(command_parts)}")

    print(f"Attempting to delete DNS record: {domain} -> {ip_address}")
    # print(f"Executing command: {' '.join(command_parts)}") # Avoid printing tokens/sid

    try:
        result = subprocess.run(command_parts, capture_output=True, text=True, check=False)
        response_text = result.stdout.strip()
        print(f"Pi-hole DNS API raw response (delete): '{response_text}' (Return code: {result.returncode})")

        if result.returncode == 0: # curl command executed successfully
            if not response_text: # Empty response is often success for DELETE
                print(f"Successfully deleted DNS record for {domain} -> {ip_address} (empty response interpreted as success)")
                return True

            try:
                response_json = json.loads(response_text)
                if not isinstance(response_json, dict):
                    print(f"Failed to delete DNS record for {domain}. Unexpected JSON type (expected dict, got {type(response_json).__name__}): {response_text}", file=sys.stderr)
                    return False

                if response_json.get("success") is True:
                    message = response_json.get("message", "Action successful.")
                    print(f"Successfully deleted DNS record for {domain} -> {ip_address}. Pi-hole message: {message}")
                    return True
                elif "error" in response_json:
                    error_details = response_json.get("error", {})
                    error_message = error_details.get("message", "Unknown error")
                    if isinstance(error_details, dict):
                         hint = error_details.get("hint", "")
                         key = error_details.get("key", "N/A")
                         error_message = f"{key}: {error_message}. Hint: {hint}"
                    print(f"Failed to delete DNS record for {domain}. Pi-hole API error: {error_message}", file=sys.stderr)
                    return False
                # Pi-hole might return something like {"message": "Deleted ..."} without a top-level "success" key
                # or just {"took": ...} as observed for add. For delete, an empty response is common.
                # Let's assume if no error and it's a dict, it might be a custom success message.
                # The primary check for delete is often an empty body and 200/204 status.
                # Since curl -s hides status, we rely on returncode 0 and parseable/empty response.
                elif response_text == "{}": # Empty JSON object
                    print(f"Successfully deleted DNS record for {domain} -> {ip_address} (empty JSON object '{{}}' interpreted as success)")
                    return True
                else:
                    # If it's a dict but doesn't match known patterns, treat as unexpected for now.
                    # It could be a success message like {"message": "Record deleted"} without a success flag.
                    # For now, being conservative. If Pi-hole returns such a message, this can be refined.
                    print(f"Deleted DNS record for {domain} -> {ip_address} (response interpreted as informational, assuming success if no error: {response_text})")
                    return True # Assuming if no error and some JSON, it might be okay for delete.

            except json.JSONDecodeError:
                print(f"Failed to delete DNS record for {domain}. Non-JSON response from Pi-hole: {response_text}", file=sys.stderr)
                return False
        else: # curl command itself failed
            print(f"Failed to delete DNS record for {domain}. curl command failed. Status: {result.returncode}", file=sys.stderr)
            print(f"Curl Stdout: {result.stdout.strip()}", file=sys.stderr)
            print(f"Curl Stderr: {result.stderr.strip()}", file=sys.stderr)
            return False
    except Exception as e:
        print(f"An unexpected error occurred during Pi-hole DNS API call (delete): {e}", file=sys.stderr)
        return False

def get_terraform_outputs(tf_dir):
    """
    Executes 'tofu output -json' in the specified directory to retrieve VM details
    by parsing the 'ansible_inventory_data' output.
    """
    try:
        # Выполняем 'tofu output -json'
        result = subprocess.run(
            ["tofu", "output", "-json"],
            cwd=tf_dir,
            capture_output=True,
            text=True,
            check=True,
            encoding='utf-8' # Явно указываем кодировку
        )
        terraform_output_json = json.loads(result.stdout)

        # Ищем 'ansible_inventory_data'
        inventory_data_str = terraform_output_json.get("ansible_inventory_data", {}).get("value")

        if not inventory_data_str:
            print("Error: 'ansible_inventory_data' output is empty or not found in Terraform output.", file=sys.stderr)
            return None, None

        # Десериализуем вложенный JSON
        inventory_data = json.loads(inventory_data_str)
        hostvars = inventory_data.get("_meta", {}).get("hostvars")

        if not hostvars:
            print("Error: '_meta.hostvars' not found in ansible_inventory_data.", file=sys.stderr)
            return None, None

        # Извлекаем хосты и IP
        vm_ipv4_addresses_output = []
        vm_fqdns_output = []

        for hostname, data in hostvars.items():
            vm_ipv4_addresses_output.append(data.get("ansible_host"))
            vm_fqdns_output.append(data.get("vm_name", hostname)) # Используем vm_name или hostname

        if not vm_ipv4_addresses_output or not vm_fqdns_output:
            print("Error: No hosts found in _meta.hostvars.", file=sys.stderr)
            return None, None

        return vm_ipv4_addresses_output, vm_fqdns_output

    except subprocess.CalledProcessError as e:
        print(f"Failed to get Terraform outputs (CalledProcessError): {e}", file=sys.stderr)
        print(f"Stderr: {e.stderr}", file=sys.stderr)
        return None, None
    except json.JSONDecodeError as e:
        print(f"Failed to parse JSON from Terraform output: {e}", file=sys.stderr)
        print(f"Raw output: {result.stdout[:200]}...", file=sys.stderr)
        return None, None
    except KeyError as e:
        print(f"Failed to find expected key in Terraform output: {e}", file=sys.stderr)
        return None, None
    except Exception as e:
        print(f"An unexpected error occurred in get_terraform_outputs: {e}", file=sys.stderr)
        return None, None

def load_sops_secrets(custom_secrets_file_path=None, debug=False): # Add debug parameter
    """Loads secrets from the SOPS file.
    Uses custom_secrets_file_path if provided, otherwise defaults to
    ../terraform/secrets.sops.yaml relative to this script.
    """
    sops_file_to_use = None
    if custom_secrets_file_path:
        sops_file_to_use = custom_secrets_file_path
        # Ensure the provided path is absolute, as cpc provides it this way.
        # If a user provides a relative path, it will be resolved relative to CWD.
        if not os.path.isabs(sops_file_to_use):
            if debug: print(f"DEBUG: Provided secrets file path '{sops_file_to_use}' is not absolute. Resolving against CWD '{os.getcwd()}'.") # Conditional print
            sops_file_to_use = os.path.abspath(sops_file_to_use)
        if debug: print(f"DEBUG: Using SOPS secrets file provided via argument: {sops_file_to_use}") # Conditional print
    else:
        try:
            script_path = os.path.abspath(__file__)
            script_dir = os.path.dirname(script_path)
            default_sops_path = os.path.abspath(os.path.join(script_dir, "..", "terraform", "secrets.sops.yaml"))
            sops_file_to_use = default_sops_path
            if debug: print(f"DEBUG: Using default SOPS secrets file: {sops_file_to_use}") # Conditional print
        except Exception as e:
            print(f"Error determining default SOPS file path: {e}", file=sys.stderr)
            sys.exit(1)

    if not os.path.exists(sops_file_to_use):
        print(f"Error: SOPS secrets file not found at {sops_file_to_use}", file=sys.stderr)
        sys.exit(1)

    return get_sops_decoded_secrets(sops_file_to_use)

def prompt_for_selection(records, action_description):
    """Display the records and prompt the user to select one or all."""
    print(f"\nAvailable records for {action_description}:")
    for i, record in enumerate(records, 1):
        print(f"{i}. {record['domain']} -> {record['ip']}")

    print(f"\nOptions:")
    print(f"a. All records")
    print(f"q. Quit without changes")

    while True:
        choice = input(f"\nSelect an option (1-{len(records)}, a, q): ").strip().lower()

        if choice == 'q':
            return []
        elif choice == 'a':
            return records
        else:
            try:
                idx = int(choice) - 1
                if 0 <= idx < len(records):
                    return [records[idx]]
                else:
                    print(f"Invalid selection. Please choose between 1 and {len(records)}, 'a' for all, or 'q' to quit.")
            except ValueError:
                print("Invalid input. Please enter a number, 'a' for all, or 'q' to quit.")

def main():
    parser = argparse.ArgumentParser(description="Manage Pi-hole DNS records based on Terraform outputs.")
    parser.add_argument(
        "--action",
        choices=['list', 'add', 'unregister-dns', 'interactive-add', 'interactive-unregister'],
        required=True,
        help="Action to perform: 'list' to show records, 'add' or 'unregister-dns' for DNS records, 'interactive-add' or 'interactive-unregister' for interactive mode."
    )
    parser.add_argument(
        "--tf-dir",
        required=True,
        help="Path to the Terraform directory containing outputs.tf and potentially .tfvars files."
    )
    parser.add_argument(
        "--secrets-file",
        help="Path to the SOPS-encrypted secrets YAML file. Defaults to ../terraform/secrets.sops.yaml relative to this script."
    )
    parser.add_argument(
        "--domain-suffix",
        help="Filter DNS records by this domain suffix (e.g., 'bevz.net'). Used to identify cluster records."
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable debug mode (prints curl commands and other debug info)."
    )

    args = parser.parse_args()

    if args.debug:
        print(f"DEBUG: Script arguments: {args}")

    # Load secrets
    secrets = load_sops_secrets(args.secrets_file, debug=args.debug) # Pass debug flag
    if not secrets:
        sys.exit(1)

    # Correctly access nested Pi-hole credentials
    pihole_data = secrets.get('pihole')
    if not pihole_data and 'default' in secrets:
        pihole_data = secrets.get('default', {}).get('pihole')

    if not pihole_data:
        print("Error: 'pihole' key not found in secrets file, neither at the root nor under 'default'.", file=sys.stderr)
        if args.debug:
            print(f"DEBUG: Loaded secrets structure: {secrets}")
        sys.exit(1)

    pihole_ip = pihole_data.get('ip_address')
    pihole_web_password = pihole_data.get('web_password')

    if not pihole_ip or not pihole_web_password:
        print("Error: Pi-hole IP address or web password not found within the 'pihole' configuration block.", file=sys.stderr)
        if args.debug: # Conditional print
            print(f"DEBUG: Loaded pihole data: {pihole_data}")
        sys.exit(1)

    # Authenticate to Pi-hole
    auth_details = authenticate_pihole(pihole_ip, pihole_web_password)
    if not auth_details:
        print("Failed to authenticate with Pi-hole. Exiting.", file=sys.stderr)
        sys.exit(1)

    sid = auth_details["sid"]
    csrf_token = auth_details["csrf"]

    # Get current DNS records from Pi-hole
    current_records = get_dns_records(pihole_ip, sid, csrf_token, debug=args.debug)

    if args.action == "list":
        # Just print the current DNS records and exit
        if current_records:
            print("\nCurrent DNS records in Pi-hole:")
            for i, record in enumerate(current_records, 1):
                ip = record.get("ip", "N/A")
                domain = record.get("domain", "N/A")
                print(f"{i}. {domain} -> {ip}")
        else:
            print("No custom DNS records found in Pi-hole.")
        sys.exit(0)

    # Get Terraform outputs
# Get Terraform outputs
    vm_ipv4_addresses_output, vm_fqdns_output = get_terraform_outputs(args.tf_dir)

    if vm_ipv4_addresses_output is None or vm_fqdns_output is None:
       # Error message is already printed inside the function
       sys.exit(1)

    if args.debug:
        print(f"DEBUG: Extracted vm_ipv4_addresses_output: {vm_ipv4_addresses_output} (type: {type(vm_ipv4_addresses_output)})")
        print(f"DEBUG: Extracted vm_fqdns_output: {vm_fqdns_output} (type: {type(vm_fqdns_output)})")

    if not vm_ipv4_addresses_output or not vm_fqdns_output:
        print("Error: vm_ipv4_addresses_output or vm_fqdns_output is empty after extracting from Terraform output.")
        sys.exit(1)

    # Handle both list and dict types for outputs
    # If they are dicts, we assume keys match between FQDNs and IPs

    terraform_records = []
    for ip, domain in zip(vm_ipv4_addresses_output, vm_fqdns_output):
        terraform_records.append({"domain": domain, "ip": ip})
    #    print(f"ERROR: vm_fqdns_output (type: {type(vm_fqdns_output)}) and vm_ipv4_addresses_output (type: {type(vm_ipv4_addresses_output)}) are of incompatible or mixed types. Both must be lists or both must be dictionaries.")
    #    sys.exit(1)

    # Compare Terraform records with Pi-hole records
    if not terraform_records:
        print("INFO: No DNS records found in Terraform outputs. Nothing to process.")
        sys.exit(0)

    # Convert Pi-hole records to a set for easy comparison
    pihole_domains = {rec.get("domain"): rec.get("ip") for rec in current_records if rec.get("domain") and rec.get("ip")}

    # Determine missing/existing records
    records_to_add = []
    for rec in terraform_records:
        domain = rec["domain"]
        ip = rec["ip"]

        if domain not in pihole_domains:
            # Not in Pi-hole, should be added
            records_to_add.append(rec)
        elif pihole_domains[domain] != ip:
            # In Pi-hole but IP differs, should be updated
            records_to_add.append(rec)

    # Determine records to delete (in Pi-hole but not in Terraform)
    terraform_domains = {rec["domain"] for rec in terraform_records}
    records_to_delete = []

    # Get domain suffix from args or use defaults
    domain_suffixes = []
    if args.domain_suffix:
        # Ensure the suffix starts with a dot
        suffix = args.domain_suffix if args.domain_suffix.startswith('.') else f".{args.domain_suffix}"
        domain_suffixes.append(suffix)
    else:
        # Default domain suffixes
        domain_suffixes = [".bevz.net", ".lan"]

    if args.debug:
        print(f"DEBUG: Using domain suffixes for filtering: {domain_suffixes}")

    for rec in current_records:
        domain = rec.get("domain")
        ip = rec.get("ip")

        if domain and domain not in terraform_domains:
            # Skip non-cluster records by checking domain suffix
            if any(domain.endswith(suffix) for suffix in domain_suffixes):
                records_to_delete.append({"domain": domain, "ip": ip})

    # Process according to action
    if args.action == "interactive-add":
        # Interactive mode for adding
        if not records_to_add:
            print("INFO: All Terraform records already exist in Pi-hole with correct IPs.")
            sys.exit(0)

        print(f"Found {len(records_to_add)} records to add/update in Pi-hole.")
        selected_records = prompt_for_selection(records_to_add, "addition/update")

        if not selected_records:
            print("No records selected for addition. Exiting.")
            sys.exit(0)

        records_to_process = selected_records
        action = "add"

    elif args.action == "interactive-unregister":
        # Interactive mode for deletion
        # Only show cluster records from current cluster for deletion
        cluster_records = []
        for rec in terraform_records:
            domain = rec["domain"]
            ip = rec["ip"]

            if domain in pihole_domains:
                cluster_records.append({"domain": domain, "ip": pihole_domains[domain]})

        if not cluster_records:
            print("INFO: No cluster records found in Pi-hole to delete.")
            sys.exit(0)

        print(f"Found {len(cluster_records)} cluster records in Pi-hole.")
        selected_records = prompt_for_selection(cluster_records, "deletion")

        if not selected_records:
            print("No records selected for deletion. Exiting.")
            sys.exit(0)

        records_to_process = selected_records
        action = "unregister-dns"

    elif args.action == "add":
        # Normal add mode
        if not records_to_add:
            print("INFO: All Terraform records already exist in Pi-hole with correct IPs.")
            sys.exit(0)

        records_to_process = records_to_add
        action = "add"

    elif args.action == "unregister-dns":
        # Normal delete mode
        records_to_process = terraform_records
        action = "unregister-dns"

    if not records_to_process:
        print("INFO: No matching DNS records found to process.")
        # sys.exit(0) # Allow script to finish normally even if no records
    else:
        if args.debug:
            print(f"DEBUG: Records to process ({action}): {records_to_process}")
            print("DEBUG: Debug mode enabled, showing records and exiting without processing:")
            for record in records_to_process:
                print(f"  - {record['domain']} -> {record['ip']}")
            sys.exit(0)
        else:
            print(f"INFO: Found {len(records_to_process)} DNS records to process with action '{action}'")

    for record in records_to_process:
        domain = record["domain"]
        ip_address = record["ip"]
        if action == "add":
            print(f"Attempting to add DNS record: {domain} -> {ip_address}")
            add_dns_record(pihole_ip, sid, csrf_token, domain, ip_address, debug=args.debug)
        elif action == "unregister-dns": # Changed from "delete"
            print(f"Attempting to unregister DNS record: {domain} (IP: {ip_address})")
            delete_dns_record(pihole_ip, sid, csrf_token, domain, ip_address, debug=args.debug)

    print(f"INFO: Script finished processing DNS records with action '{action}'.")

if __name__ == "__main__":
    main()
