variable "service_network_name" {
  description = "Name of the Lattice Service Network"
  type        = string
  default     = "central-lattice-network"
}

variable "share_principal_arn" {
  description = "ARN of the Organization or OU to share the Service Network with via RAM"
  type        = string
}

variable "provider_account_principals" {
  description = "List of Provider Account Root ARNs allowed to register services"
  type        = list(string)
}

variable "consumer_account_principals" {
  description = "List of Consumer Account Root ARNs allowed to read network info"
  type        = list(string)
}
