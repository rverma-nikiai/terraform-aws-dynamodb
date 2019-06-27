module "dynamodb_label" {
  source     = "git::https://github.com/cloudposse/terraform-null-label.git?ref=tags/0.14.1"
  namespace  = var.namespace
  stage      = var.stage
  name       = var.name
  delimiter  = var.delimiter
  attributes = var.attributes
  tags       = var.tags
}

resource "null_resource" "global_secondary_index_names" {
  count = (var.enabled == "true" ? 1 : 0) * length(var.global_secondary_index_map)

  # Convert the multi-item `global_secondary_index_map` into a simple `map` with just one item `name` since `triggers` does not support `lists` in `maps` (which are used in `non_key_attributes`)
  # See `examples/complete`
  # https://www.terraform.io/docs/providers/aws/r/dynamodb_table.html#non_key_attributes-1
  triggers = {
    "name" = var.global_secondary_index_map[count.index]["name"]
  }
}

resource "null_resource" "local_secondary_index_names" {
  count = (var.enabled == "true" ? 1 : 0) * length(var.local_secondary_index_map)

  # Convert the multi-item `local_secondary_index_map` into a simple `map` with just one item `name` since `triggers` does not support `lists` in `maps` (which are used in `non_key_attributes`)
  # See `examples/complete`
  # https://www.terraform.io/docs/providers/aws/r/dynamodb_table.html#non_key_attributes-1
  triggers = {
    "name" = var.local_secondary_index_map[count.index]["name"]
  }
}

resource "aws_dynamodb_table" "default" {
  count            = var.enabled == "true" ? 1 : 0
  name             = module.dynamodb_label.id
  billing_mode     = var.billing_mode
  read_capacity    = var.autoscale_min_read_capacity
  write_capacity   = var.autoscale_min_write_capacity
  hash_key         = var.hash_key
  range_key        = var.range_key
  stream_enabled   = var.enable_streams
  stream_view_type = var.enable_streams == "true" ? var.stream_view_type : ""

  server_side_encryption {
    enabled = var.enable_encryption
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  lifecycle {
    ignore_changes = [
      read_capacity,
      write_capacity,
    ]
  }

  attribute {
    name = var.hash_key
    type = var.hash_key_type
  }

  dynamic "attribute" {
    for_each = length(var.range_key) > 0 ? 1 : 0
    content {
      name = var.range_key
      type = var.range_key_type
    }
  }

  dynamic "attribute" {
    for_each = var.dynamodb_attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_index_map

    content {
      name               = global_secondary_index.value.name
      hash_key           = global_secondary_index.value.hash_key
      projection_type    = global_secondary_index.value.projection_type
      range_key          = lookup(global_secondary_index.value, "range_key", null)
      non_key_attributes = lookup(global_secondary_index.value, "non_key_attributes", null)
      read_capacity      = lookup(global_secondary_index.value, "read_capacity", null)
      write_capacity     = lookup(global_secondary_index.value, "write_capacity", null)
    }
  }

  dynamic "local_secondary_index" {
    for_each = var.local_secondary_index_map

    content {
      name               = local_secondary_index.value.name
      projection_type    = local_secondary_index.value.projection_type
      range_key          = local_secondary_index.value.range_key
      non_key_attributes = lookup(local_secondary_index.value, "non_key_attributes", null)
    }
  }


  ttl {
    attribute_name = var.ttl_attribute
    enabled        = true
  }

  tags = module.dynamodb_label.tags
}

module "dynamodb_autoscaler" {
  source                       = "git::https://github.com/rverma-nikiai/terraform-aws-dynamodb-autoscaler.git?ref=master"
  enabled                      = var.enabled == "true" && var.enable_autoscaler == "true" && var.billing_mode == "PROVISIONED"
  namespace                    = var.namespace
  stage                        = var.stage
  name                         = var.name
  delimiter                    = var.delimiter
  attributes                   = var.attributes
  dynamodb_table_name          = concat(aws_dynamodb_table.default.*.id, [""])[0]
  dynamodb_table_arn           = concat(aws_dynamodb_table.default.*.arn, [""])[0]
  dynamodb_indexes             = null_resource.global_secondary_index_names.*.triggers.name
  autoscale_write_target       = var.autoscale_write_target
  autoscale_read_target        = var.autoscale_read_target
  autoscale_min_read_capacity  = var.autoscale_min_read_capacity
  autoscale_max_read_capacity  = var.autoscale_max_read_capacity
  autoscale_min_write_capacity = var.autoscale_min_write_capacity
  autoscale_max_write_capacity = var.autoscale_max_write_capacity
}

