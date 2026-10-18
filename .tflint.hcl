plugin "aws" {
    enabled = true
    version = "0.28.0"
    source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
    # Fix error: module = true removed
    # "local" checks local modules (./modules/...), "all" checks external modules too
    call_module_type = "local"
    force = false
}

rule "terraform_required_version" {
    enabled = false
}

rule "terraform_unused_declarations" {
    enabled = false
}
