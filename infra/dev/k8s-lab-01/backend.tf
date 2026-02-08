terraform {
  backend "s3" {
    # Bucket and key are set dynamically via -backend-config
    # Endpoint is set via environment or -backend-config

    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
