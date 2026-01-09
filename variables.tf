variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "region" {
  description = "The GCP region"
  type        = string
}

variable "org_id" {
  description = "The GCP organization ID (optional)"
  type        = string
}

variable "billing_account" {
  description = "The GCP billing account ID"
  type        = string
}
