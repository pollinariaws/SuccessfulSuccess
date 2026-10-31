# Look up the default VPC and networking (matches reports.sh logic)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

data "aws_route_table" "default" {
  vpc_id = data.aws_vpc.default.id
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

# Look up backend stack and lambda configuration
data "aws_cloudformation_stack" "backend" {
  name = "${var.project_name}-backend"
}

data "aws_cloudformation_stack" "ecr" {
  name = "${var.project_name}-ecr"
}

data "aws_lambda_function" "backend" {
  function_name = "${var.project_name}-backend"
}

locals {
  vpc_id            = var.vpc_id != "" ? var.vpc_id : data.aws_vpc.default.id
  subnet_ids        = length(var.subnet_ids) > 0 ? var.subnet_ids : data.aws_subnets.default.ids
  route_table_id    = var.route_table_id != "" ? var.route_table_id : data.aws_route_table.default.id
  security_group_id = var.security_group_id != "" ? var.security_group_id : data.aws_cloudformation_stack.backend.outputs["FunctionSecurityGroupId"]
  database_url      = var.database_url != "" ? var.database_url : data.aws_lambda_function.backend.environment[0].variables["DATABASE_URL"]
  image_uri         = var.image_uri != "" ? var.image_uri : "${data.aws_cloudformation_stack.ecr.outputs["RepositoryUri"]}:${var.image_tag}"
}
