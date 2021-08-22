//API should be enabled on project:
//API [cloudresourcemanager.googleapis.com]
//API Compute Engine API
//API DNS api
//export GOOGLE_APPLICATION_CREDENTIALS={C:\Service\cloudx\cloudx-finaltask-3a66417d9198.json}
//terraform init
//terraform plan

provider "google" {
    // Compatible with TF11
    //version = "<=0.11.0"
    
    // Compatibel with TF12.31
    version = "~> 2.5"
    
    //credentials = file("C:\Service\cloudx\cloudx-finaltask-3a66417d9198.json")
    project = "cloudx-finaltask"
    region = "us-central1"
}

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