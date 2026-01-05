module "vpc_lattice_network" {
  source = "./../../modules/vpc-lattice-network"
  count  = var.vpc_lattice_network_enabled ? 1 : 0

  share_principal_arn         = "arn:aws:organizations::network:organization/xxxxx"
  provider_account_principals = ["arn:aws:iam::provider:root"]
  consumer_account_principals = ["arn:aws:iam::consumer:root"]
}
