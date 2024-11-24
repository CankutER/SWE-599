
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
      version = "2.16.1"
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
      
    }

    node {
      role = "worker"
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