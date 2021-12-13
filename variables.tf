variable "location" {
  type    = string
  default = "East US 2"

  validation {
    condition     = length(var.location) > 0
    error_message = "The location value must be set."
  }
}

variable "subscription_id" {
  type    = string
  default = ""
}

variable "admin_user" {
  type    = string
  default = "mladmin"
}

variable admin_public_key {
  type    = string
  default = ""
}
