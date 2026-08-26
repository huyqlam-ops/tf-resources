variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "suffix"              { type = string }

variable "storage" {
  type = object({
    id                        = string
    name                      = string
    container_name            = string
    checkpoint_container_name = string
  })
}

variable "eventhub" {
  type = object({
    namespace_id   = string
    namespace_name = string
    name           = string
  })
}

variable "cosmosdb" {
  type = object({
    id            = string
    name          = string
    endpoint      = string
    database_name = string
  })
}
