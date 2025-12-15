provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_compute_network" "vpc_network" {
  name = "ha-scalable-vpc"
}

resource "google_compute_subnetwork" "public" {
  name          = "public-subnet"
  ip_cidr_range = "10.10.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_subnetwork" "private" {
  name          = "private-subnet"
  ip_cidr_range = "10.10.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc_network.id
  private_ip_google_access = true
}

resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = google_compute_network.vpc_network.name
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "allow-ssh"
  network = google_compute_network.vpc_network.name
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance_template" "app_template" {
  name         = "app-template"
  machine_type = "e2-micro"
  region       = var.region
  tags         = ["http-server"]
  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
  }
  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    access_config {}
  }
  metadata_startup_script = <<-EOT
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    echo 'Hello from GCP Terraform!' > /var/www/html/index.html
    systemctl enable nginx
    systemctl start nginx
  EOT
}

resource "google_compute_instance_group_manager" "app_mig" {
  name               = "app-mig"
  base_instance_name = "app-instance"
  region             = var.region
  version {
    instance_template = google_compute_instance_template.app_template.id
  }
  target_size = 2
  auto_healing_policies {
    health_check      = google_compute_health_check.default.id
    initial_delay_sec = 60
  }
}

resource "google_compute_health_check" "default" {
  name               = "app-health-check"
  check_interval_sec = 5
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 2
  http_health_check {
    port = 80
  }
}

resource "google_compute_backend_service" "default" {
  name                  = "app-backend-service"
  protocol              = "HTTP"
  port_name             = "http"
  timeout_sec           = 10
  health_checks         = [google_compute_health_check.default.id]
  backend {
    group = google_compute_instance_group_manager.app_mig.instance_group
  }
}

resource "google_compute_url_map" "default" {
  name            = "app-url-map"
  default_service = google_compute_backend_service.default.id
}

resource "google_compute_target_http_proxy" "default" {
  name   = "app-http-proxy"
  url_map = google_compute_url_map.default.id
}

resource "google_compute_global_forwarding_rule" "default" {
  name       = "app-forwarding-rule"
  target     = google_compute_target_http_proxy.default.id
  port_range = "80"
  ip_protocol = "TCP"
}
