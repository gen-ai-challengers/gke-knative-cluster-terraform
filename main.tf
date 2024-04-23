/**
 * Copyright 2018 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

data "google_project" "project" {
  project_id = var.project_id
}

module "gcp-network" {
  source  = "terraform-google-modules/network/google"
  version = ">= 7.5"

  project_id   = var.project_id
  network_name = var.network

  subnets = [
    {
      subnet_name   = var.subnetwork
      subnet_ip     = "10.0.0.0/17"
      subnet_region = var.region
    },
  ]

  secondary_ranges = {
    (var.subnetwork) = [
      {
        range_name    = var.ip_range_pods_name
        ip_cidr_range = var.ip_range_pods
      },
      {
        range_name    = var.ip_range_services_name
        ip_cidr_range = var.ip_range_services
      },
    ]
  }
}

module "enabled_google_apis" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 14.0"

  project_id                  = var.project_id
  disable_services_on_destroy = false

  activate_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "gkehub.googleapis.com",
    "anthosconfigmanagement.googleapis.com"
  ]
}

module "gke" {
  source                            = "terraform-google-modules/kubernetes-engine/google"
  version                           = "~> 30.0"
  project_id                        = module.enabled_google_apis.project_id
  name                              = var.cluster_name
  regional                          = false
  region                            = var.region
  zones                             = var.zones
  release_channel                   = "REGULAR"
  network                           = module.gcp-network.network_name
  subnetwork                        = module.gcp-network.subnets_names[0]
  ip_range_pods                     = var.ip_range_pods_name
  ip_range_services                 = var.ip_range_services_name
  network_policy                    = false
  cluster_resource_labels           = { "mesh_id" : "proj-${data.google_project.project.number}" }
  identity_namespace                = "${var.project_id}.svc.id.goog"
  deletion_protection               = false
  remove_default_node_pool          = true
  disable_legacy_metadata_endpoints = false
  cluster_autoscaling               = var.cluster_autoscaling
  node_pools = [
    {
      name              = "asm-node-pool"
      auto_upgrade      = true
      min_count         = 1
      max_count         = 3
      local_ssd_count   = 0
      disk_size_gb      = 30
      disk_type         = "pd-standard"
      machine_type      = "e2-standard-8"
      
    },
    {
      name                = "gpu-pool"
      machine_type        = "g2-standard-4"
      min_count           = 0
      max_count           = 1
      local_ssd_count     = 0
      disk_size_gb        = 30
      disk_type           = "pd-ssd"
      accelerator_count   = 1
      accelerator_type    = "nvidia-l4"
      gpu_driver_version  = "DEFAULT"
      auto_repair         = false
    },
  ]
}

module "asm" {
  source  = "terraform-google-modules/kubernetes-engine/google//modules/asm"
  version = "~> 30.0"

  project_id                = var.project_id
  cluster_name              = module.gke.name
  cluster_location          = module.gke.location
  enable_cni                = true
  enable_fleet_registration = true
  enable_mesh_feature       = var.enable_mesh_feature
  fleet_id                  = var.project_id

}
