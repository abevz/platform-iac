# infra/dev/localstack/backend.tf
terraform {
  backend "s3" {
    endpoint                    = "https://s3.minio.bevz.net"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
