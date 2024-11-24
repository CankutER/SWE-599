variable "kind_cluster_config_path" {
  type        = string
  description = "The location where this cluster's kubeconfig will be saved to."
  default     = "~/.kube/config"
}


variable "ingress_nginx_namespace" {
  type        = string
  description = "The nginx ingress namespace (it will be created if needed)."
  default     = "ingress-nginx"
}

variable "actions_namespace" {
  type        = string
  description = "Namespace for GitHub actions resources"
  default     = "actions-namespace"
}

variable "github_pat" {
  type        = string
  description = "Personal Access Token for Github API"
  default     = "enter your github personal token"
}

variable "sonarqube_namespace" {
  type        = string
  description = "Namespace for GitHub actions resources"
  default     = "sonarqube-namespace"
}