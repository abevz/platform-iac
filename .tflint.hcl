plugin "aws" {
    enabled = true
    version = "0.28.0"
    source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
    # Исправление ошибки: module = true удален
    # "local" проверяет локальные модули (./modules/...), "all" проверяет и внешние
    call_module_type = "local"
    force = false
}

rule "terraform_required_version" {
    enabled = false
}

rule "terraform_unused_declarations" {
    enabled = false
}
