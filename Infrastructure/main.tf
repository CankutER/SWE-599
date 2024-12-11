
terraform {
  required_providers {
    kind = {
      source = "tehcyx/kind"
      version = "0.7.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.33.0"
    }
     helm = {
      source = "hashicorp/helm"
    }
  }
}

provider "kind" {
}

provider "kubernetes" {
  config_path = pathexpand(var.kind_cluster_config_path)
}

provider "helm" {
  kubernetes {
    config_path = pathexpand(var.kind_cluster_config_path)
  }
}

resource "kind_cluster" "default" {
  name = "swe-599"
  wait_for_ready = true
  kubeconfig_path = pathexpand(var.kind_cluster_config_path)
  kind_config {
    kind = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"
       kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]
      
      
      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }
      extra_port_mappings {
        container_port = 443
        host_port      = 443
      }
       extra_port_mappings {
        container_port = 5433
        host_port      = 5433
      }
      
    }

    node {
      role = "worker"
      labels = {
        "sonarqube" = "true"
      }
      
    }

    node {
      role = "worker" 
    }
  }
}


resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"

  namespace        = var.ingress_nginx_namespace
  create_namespace = true

  values = [file("nginx_ingress_values.yaml")]

  depends_on = [kind_cluster.default]
}


resource "kubernetes_secret" "github_pat" {
  metadata {
    name = "github-pat"
    namespace = var.actions_namespace
  }

  data = {
    github_token = var.github_pat
  }

  depends_on = [ helm_release.actions_runner_controller]
}

resource "helm_release" "actions_runner_controller" {
  name       = "actions-runner-controller"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set-controller"

  namespace        = var.actions_namespace
  create_namespace = true

  depends_on = [kind_cluster.default]
}

resource "helm_release" "actions_runner_set" {
  name       = "actions-runner-set"
  repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
  chart      = "gha-runner-scale-set"

  namespace        = var.actions_namespace
  create_namespace = true

  values = [file("arc_runner_set_values.yaml")]

  depends_on = [kind_cluster.default,helm_release.actions_runner_controller,kubernetes_secret.github_pat]
}

resource "helm_release" "sonarqube" {
  name       = "sonarqube"
  repository = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart      = "sonarqube"

  namespace        = var.sonarqube_namespace
  create_namespace = true

  values = [file("sonarqube-values.yaml")]

  depends_on = [kind_cluster.default]
}

resource "helm_release" "postgres" {
  name       = "postgres"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "postgresql"

  namespace        = var.app_namespace
  create_namespace = true

  values = [file("postgres-values.yaml")]

  depends_on = [kind_cluster.default]
}

data "kubernetes_service" "postgres_service" {
  metadata {
    name      = "${resource.helm_release.postgres.name}-postgresql" 
    namespace = var.app_namespace
  }
}


resource "kubernetes_secret" "ghcr_secret" {
  depends_on = [ helm_release.postgres ]
  metadata {
    name      = "ghcr-secret"
    namespace = var.app_namespace
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      "auths" = {
        "ghcr.io" = {
          "username" = "${var.github_username}"
          "password" = "${var.github_pat}"
          "email"    = "${var.github_email}"
        }
      }
    })
  }
}

resource "kubernetes_deployment" "app_backend" {
  depends_on = [ kubernetes_secret.ghcr_secret, helm_release.postgres ]
  metadata {
    name      = "app-backend"
    namespace = var.app_namespace
    labels = {
      app = "app-backend"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "app-backend"
      }
    }

    template {
      metadata {
        labels = {
          app = "app-backend"
        }
      }

      spec {
        container {
          name  = "app-backend"
          image = "ghcr.io/${lower(var.github_username)}/app-backend:latest"
           env {
            name  = "db_url"
            value = "jdbc:postgresql://${resource.helm_release.postgres.name}-postgresql:5433/communitter"
          }
           env {
            name  = "db_username"
            value = "postgres"
          }

          env {
            name  = "db_password"
            value = "postgres"
          }
          port {
            container_port = 8080
          }
        }

        image_pull_secrets {
          name = kubernetes_secret.ghcr_secret.metadata[0].name
        }
      }
    }
  }
}

resource "kubernetes_service" "app_backend_service" {
  depends_on = [ kubernetes_deployment.app_backend ]
  metadata {
    name      = "app-backend-service"
    namespace = var.app_namespace
    labels = {
      app = "app-backend"
    }
  }

  spec {
    selector = {
      app = "app-backend"
    }

    port {
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }
}

# Kubernetes Ingress to connect to the service
resource "kubernetes_ingress_v1" "app_backend_ingress" {
  metadata {
    name      = "app-backend-ingress"
    namespace = var.app_namespace
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" = "/"
    }
  }

  spec {
    rule {
      host = "backend.local.com"

      http {
        path {
          path = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.app_backend_service.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }
    }
  }
}




/*resource "kubernetes_ingress_v1" "postgres_ingress" {
  metadata {
    name      = "postgres-ingress"
    namespace = var.app_namespace
    annotations = {
      "nginx.ingress.kubernetes.io/backend-protocol" = "TCP"
    }
  }

  spec {
    rule {
      host = "postgres.local.com"

      http {
        path {
          path     = "/"

          backend {
            service {
              name = data.kubernetes_service.postgres_service.metadata[0].name
              port {
                number = 5433
              }
            }
          }
        }
      }
    }
  }
}*/

/*
resource "kubernetes_config_map" "tcp_services" {
  metadata {
    name      = "tcp-services"
    namespace = "ingress-nginx" # Replace with your NGINX ingress namespace
  }

  data = {
    "80" = "${var.app_namespace}/${data.kubernetes_service.postgres_service.metadata[0].name}:5433" # Map port 5432 to PostgreSQL service
  }
}
*/

/*
resource "null_resource" "wait_for_ingress_nginx" {
  triggers = {
    key = uuid()
  }

  provisioner "local-exec" {
    command = <<EOF
      printf "\nWaiting for the nginx ingress controller...\n"
      kubectl wait --namespace ${helm_release.ingress_nginx.namespace} \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=90s
    EOF
  }

  depends_on = [helm_release.ingress_nginx]
}
*/