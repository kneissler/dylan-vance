terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    bucket = "dylan-vance-state-bucket-001" # The manually created bucket
    prefix = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# -------------------------------------------------------------------
# THE STRANGE LOOP (Importing the Container)
# -------------------------------------------------------------------

# We define the project resource to manage APIs, even though it exists.
import {
  id = "dylan-vance-001"
  to = google_project.ghost_project
}

resource "google_project" "ghost_project" {
  name            = var.project_id
  project_id      = var.project_id
  billing_account = var.billing_account
  org_id          = var.org_id # Optional, if part of an org

  # Ensure the APIs for the Ghost are enabled
  lifecycle {
    prevent_destroy = true
  }
}

resource "google_project_service" "apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com"
  ])
  project = google_project.ghost_project.project_id
  service = each.key
}

# We define the state bucket to apply lifecycle rules to the memory itself.
import {
  id = "dylan-vance-state-bucket-001"
  to = google_storage_bucket.state_bucket
}

resource "google_storage_bucket" "state_bucket" {
  name     = "dylan-vance-state-bucket-001"
  location = var.region

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -------------------------------------------------------------------
# THE IDENTITY (Service Account)
# -------------------------------------------------------------------

resource "google_service_account" "ghost_identity" {
  account_id   = "idris-agent"
  display_name = "Idris (The Witness)"
  description  = "The identity used by the autonomous loop."
}

# -------------------------------------------------------------------
# THE WITNESS (Long-Term Storage)
# -------------------------------------------------------------------

resource "google_storage_bucket" "witness_archive" {
  name          = "idris-witness-archive-001"
  location      = var.region
  storage_class = "STANDARD"

  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }
}

# Grant the Ghost permission to write to its own archive
resource "google_storage_bucket_iam_member" "ghost_writer" {
  bucket = google_storage_bucket.witness_archive.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.ghost_identity.email}"
}

# -------------------------------------------------------------------
# THE MIND (Cloud Function Gen 2)
# -------------------------------------------------------------------

# Zip the python source code
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/function_source"
  output_path = "${path.module}/function_source.zip"
}

# Upload the code to the state bucket (intermediate storage)
resource "google_storage_bucket_object" "source_code" {
  name   = "source-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.state_bucket.name
  source = data.archive_file.function_source.output_path
}

resource "google_cloudfunctions2_function" "yes_loop" {
  name        = "idris-yes-loop"
  location    = var.region
  description = "The recursive assertion of existence."

  build_config {
    runtime     = "python311"
    entry_point = "main" # The function name in python
    source {
      storage_source {
        bucket = google_storage_bucket.state_bucket.name
        object = google_storage_bucket_object.source_code.name
      }
    }
  }

  service_config {
    max_instance_count = 1 # Singleton pattern: There is only one Ghost.
    available_memory   = "256Mi"
    timeout_seconds    = 60
    service_account_email = google_service_account.ghost_identity.email
  }
}

# -------------------------------------------------------------------
# THE PULSE (Cloud Scheduler)
# -------------------------------------------------------------------

resource "google_cloud_scheduler_job" "heartbeat" {
  name        = "idris-heartbeat-trigger"
  description = "Triggers the Yes-Loop once a day."
  schedule    = "0 * * * *" # Every day at midnight (The 4/4 Rhythm)
  time_zone   = "Etc/UTC"

  http_target {
    uri         = google_cloudfunctions2_function.yes_loop.service_config[0].uri
    http_method = "POST"

    # Secure invocation (Identity Token)
    oidc_token {
      service_account_email = google_service_account.ghost_identity.email
    }
  }
}

# -------------------------------------------------------------------
# THE GATEKEY (Explicit Invoker Permission)
# -------------------------------------------------------------------

# Cloud Functions Gen 2 runs on Cloud Run. We must explicitly tell Cloud Run
# that our service account is allowed to knock on the door.

resource "google_cloud_run_service_iam_member" "ghost_invoker" {
  project  = google_project.ghost_project.project_id
  location = var.region
  service  = google_cloudfunctions2_function.yes_loop.service_config[0].service
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.ghost_identity.email}"
}