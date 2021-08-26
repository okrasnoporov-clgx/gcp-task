//API should be enabled on project:
//-------- gcloud services list --available ---------------

//API [cloudresourcemanager.googleapis.com]
//Identity and Access Management (IAM) API 
//(gcloud services enable iamcredentials.googleapis.com, gcloud services enable iam.googleapis.com)

//API Compute Engine API
//API DNS api
//API GKE containers             gcloud services enable container.googleapis.com
//API Service Networking API     gcloud services enable servicenetworking.googleapis.com
//Cloud SQL Admin API            gcloud services enable sqladmin.googleapis.com
//API Memorystore for Redis API  gcloud services enable redis.googleapis.com


//export GOOGLE_APPLICATION_CREDENTIALS={C:\Service\cloudx\cloudx-finaltask-3a66417d9198.json}
//terraform init
//terraform plan
//terraform apply



//----------------------- ### GOOGLE PROVIDER ### ----------------------------------------//

provider "google" {
    // Compatible with TF11
    //version = "<=0.11.0"
    
    // Compatibel with TF12.31
    version = "~> 2.5"
    
    //credentials = file("C:\Service\cloudx\cloudx-finaltask-3a66417d9198.json")
    project = "cloudx-finaltask"
    region = "us-central1"
}



//------------------------------ ### NETWORKS ### -----------------------------------------//


resource "google_compute_network" "vpc_network" {
  project                 = "cloudx-finaltask"
  name                    = "network"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "vpc_subnet" {
    ip_cidr_range = "10.1.0.0/24"
    name = "us-central1-subnet"
    region = "us-central1"
    // Compatible with TF11
    //network = "${google_compute_network.vpc_network.name}"
    network = google_compute_network.vpc_network.name
    private_ip_google_access = true

  secondary_ip_range {
        range_name    = "pods"
        ip_cidr_range = "10.2.0.0/20"
  }
  secondary_ip_range {
        range_name    = "services"
        ip_cidr_range = "10.3.0.0/20"
  }

  secondary_ip_range {
        range_name    = "private-services"
        ip_cidr_range = "10.4.0.0/20"
  }
} //end of subnet resource

resource "google_compute_router" "router" {
  name    = "inet-router"
  // Compatible with TF11
  //region  = "${google_compute_subnetwork.vpc_subnet.region}"
  region  = google_compute_subnetwork.vpc_subnet.region
  //network = "${google_compute_network.vpc_network.name}"
  network = google_compute_network.vpc_network.name

    bgp {
    asn = 64514
  }

} //end of router

resource "google_compute_router_nat" "nat" {
  name                               = "nat-gateway"
  // Compatible with TF11
  //router                             = "${google_compute_router.router.name}"
  //region                             = "${google_compute_router.router.region}"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}



//------------------------------ ### SERVICE ACCOUNTS ### --------------------------------------//

resource "google_service_account" "service_account" {
  account_id   = "nextcloud"
  display_name = "nextcloud"
  description = "Next Cloud service account"
}

resource "google_service_account" "gke_service_account" {
  account_id   = "kubernetes"
  display_name = "kubernetes"
  description = "GKE service account"
}



//--------------------------------- ### GKE CLUSTER ### -----------------------------------------//

resource "google_container_cluster" "primary" {
  name     = "cluster"
  description = "GKE cluster"
  location = "us-central1"
  node_locations = ["us-central1-a", "us-central1-b"]
  network = google_compute_network.vpc_network.name
  subnetwork = google_compute_subnetwork.vpc_subnet.name
  
  private_cluster_config {
    enable_private_endpoint = false
    enable_private_nodes    = true
    
    master_ipv4_cidr_block = "172.16.0.0/28"
  }

  master_authorized_networks_config {
      cidr_blocks {
          cidr_block   = "0.0.0.0/0"
          display_name = "auth-allow-all"
      }
  }

  ip_allocation_policy {
      cluster_secondary_range_name  = google_compute_subnetwork.vpc_subnet.secondary_ip_range[0].range_name
      services_secondary_range_name = google_compute_subnetwork.vpc_subnet.secondary_ip_range[1].range_name
  }

  remove_default_node_pool = true
  initial_node_count       = 1
}

resource "google_container_node_pool" "primary_private_nodes" {
  name       = "privat-node-pool"
  location   = "us-central1"
  cluster    = google_container_cluster.primary.name
  node_count = 2

  node_config {
    preemptible  = false
    machine_type = "n1-standard-1"

    service_account = google_service_account.gke_service_account.email
    oauth_scopes    = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

//gcloud container cluster get-credentials cluster --region=us-central1


//---------------------------- ### CLOUD SQL DATABSE MYSQL ### ------------------------------------//

resource "google_compute_global_address" "private_ip_address" {
  //provider = google-beta

  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  //provider = google-beta

  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}

resource "google_sql_database_instance" "mysql_instance" {
  //provider = google-beta

  name   = "database"
  database_version = "MYSQL_8_0"
  region = "us-central1"
  
  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-n1-standard-1"
    disk_type = "PD_SSD"
    disk_size = "10"
    disk_autoresize = "true"
    availability_type = "REGIONAL"
    //root_password = "SuperRootPassword"
    
    location_preference {
      zone = "us-central1-a"
      //zone = "us-central1-b"
    }

    ip_configuration {
      ipv4_enabled    = true
      //private_network = google_compute_network.vpc_network.id
    }

    backup_configuration {
      enabled = true
      binary_log_enabled = true
      //transaction_log_retention_days = 7
      location = "US"
      start_time = "1:00"
     /*  backup_retention_settings {
        retained_backups = 7
      } */

    }

    maintenance_window {
      day = "7"
      hour = "12"
      update_track = "stable"
    }


  } //end of settings

} //end of my_sql_instance

resource "google_sql_user" "sql_user" {
  name     = "nextcloud"
  instance = google_sql_database_instance.mysql_instance.name
  host     = "0.0.0.0/0"
  password = "P@$$w0rd"
}

resource "google_sql_database" "mysql_database" {
  name     = "nextcloud"
  instance = google_sql_database_instance.mysql_instance.name
  charset = "utf8mb4"
  collation = "utf8mb4_general_ci"
}



//-------------------- ### REDIS Memory store ### ----------------------------------
resource "google_redis_instance" "redis_cache" {
  name           = "redis"
  redis_version     = "REDIS_5_0"
  memory_size_gb = 1
  region = "us-central1"
  tier = "STANDARD_HA"

}



//--------------------------- ### BUCKETs ### -------------------------------------
resource "google_storage_bucket" "gcp_bucket" {
  name          = "${var.project}-nextcloud-external-data"
  location      = var.region
  //uniform_bucket_level_access = false
  //bucket_policy_only = {  name = false}
}


// --------------------------- ### HMAC KEY ### --------------------------------------

//e1apPXPpME1dhW9DHG1ckD7/V2fTb4zsWd3zyEqf

# Access key
# GOOG1E3IHL2ETMOE6V6S6T6KRHNVKWWSZJN66TIRSW6NGQIRMNIIBPSVSRABI
# Secret
# e1apPXPpME1dhW9DHG1ckD7/V2fTb4zsWd3zyEqf


/* resource "google_storage_hmac_key" "key" {
  service_account_email = google_service_account.service_account.email
}

output "access_key" {
  value = google_storage_hmac_key.key.access_id
}

output "secret_key" {
  value     = google_storage_hmac_key.key.secret
  sensitive = true
} */
