variable "region" {
  description = "The AWS region to deploy resources in"
  type        = string
  default     = "us-west-1"
}

variable "vpc_id" {
  description = "The VPC ID to associate with the VPC Lattice Service Network"
  type        = string
  default     = ""  
}

variable "central_account_id" {
  description = "The AWS Account ID of the Central VPC Lattice Network account"
  type        = string
  default     = ""  
}

variable "vpc_lattice_consumer" {
  description = "Whether this module is being deployed as a VPC Lattice Consumer"
  type        = bool
  default     = false  
}

variable "vpc_lattice_provider" {
  description = "Whether this module is being deployed as a VPC Lattice Provider"
  type        = bool
  default     = false  
}

