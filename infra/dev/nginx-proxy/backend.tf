#terraform {
#  backend "s3" {
#    # 'key' и 'bucket' будут переданы динамически
#
#    # Укажите эндпоинт Вашего MinIO
#    endpoint = "https://s3.minio.example.com"
#
#    region                      = "us-east-1"
#    skip_credentials_validation = true
#    skip_metadata_api_check     = true
#    force_path_style            = true
#  }
#}
