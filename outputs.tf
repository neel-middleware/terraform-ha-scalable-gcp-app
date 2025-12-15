output "load_balancer_ip" {
  value       = google_compute_global_forwarding_rule.default.ip_address
  description = "The external IP address of the HTTP load balancer"
}
