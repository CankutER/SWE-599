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

variable "app_namespace" {
  type        = string
  description = "Namespace for app components (it will be created if needed)."
  default     = "app"
}

variable "github_pat" {
  type        = string
  description = "Personal Access Token for Github API"
  default     = "enter your github personal token"
}
variable "github_username" {
  type        = string
  description = "username for github"
  default     = "enter your github username"
}

variable "github_email" {
  type        = string
  description = "email for github"
  default     = "enter your github email"
}

variable "sonarqube_namespace" {
  type        = string
  description = "Namespace for GitHub actions resources"
  default     = "sonarqube-namespace"
}