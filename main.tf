terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.74"
}


variable "token" {
  type = string
}

variable "cloud_id" {
  type = string
}

variable "folder_id" {
  type = string
}

provider "yandex" {
  token            = var.token
  cloud_id         = var.cloud_id
  folder_id        = var.folder_id
  zone             = "ru-central1-a"
  endpoint         = "api.cloud.yandex.net:443"
  storage_endpoint = "storage.yandexcloud.net"
}

resource "yandex_vpc_network" "spark-kafka" {
  folder_id = var.folder_id
  name = "spark-kafka"
}

resource "yandex_vpc_subnet" "spark-kafka-a" {
  name = "spark-kafka-a"
  zone = "ru-central1-a"
  network_id = yandex_vpc_network.spark-kafka.id
  v4_cidr_blocks = ["10.128.0.0/24"]
}

resource "yandex_vpc_subnet" "spark-kafka-b" {
  name = "spark-kafka-b"
  zone = "ru-central1-b"
  network_id = yandex_vpc_network.spark-kafka.id
  v4_cidr_blocks = ["10.129.0.0/24"]
}

resource "yandex_vpc_subnet" "spark-kafka-c" {
  name = "spark-kafka-c"
  zone = "ru-central1-c"
  network_id = yandex_vpc_network.spark-kafka.id
  v4_cidr_blocks = ["10.130.0.0/24"]
}

resource "random_password" "admin_password" {
  length  = 10
  special = false
}

resource "yandex_mdb_kafka_cluster" spark-kafka {
  depends_on = [yandex_vpc_subnet.spark-kafka-a, yandex_vpc_subnet.spark-kafka-b, yandex_vpc_subnet.spark-kafka-c]
  name        = "spark-kafka"
  network_id  = yandex_vpc_network.spark-kafka.id
  environment = "PRODUCTION"

  config {
    version          = "2.8"
    zones            = ["ru-central1-a", "ru-central1-b", "ru-central1-c"]
    brokers_count    = 1
    assign_public_ip = true
    kafka {
      resources {
        resource_preset_id = "s2.small"
        disk_type_id       = "network-ssd"
        disk_size          = 32
      }
      kafka_config {
        log_segment_bytes = 104857600
      }
    }
  }

  user {
    name     = "admin"
    password = random_password.admin_password.result
    permission {
      topic_name = "*"
      role = "ACCESS_ROLE_ADMIN"
    }
  }
}

resource "yandex_mdb_kafka_topic" topic1 {
  cluster_id         = yandex_mdb_kafka_cluster.spark-kafka.id
  name               = "topic1"
  partitions         = 3
  replication_factor = 3
}

resource "yandex_iam_service_account" "dataproc-sa" {
  name = "dataproc-sa"
}

resource "yandex_resourcemanager_folder_iam_binding" dataproc-agent {
  folder_id = var.folder_id
  members = ["serviceAccount:${yandex_iam_service_account.dataproc-sa.id}"]
  role = "dataproc.agent"
}

resource "yandex_resourcemanager_folder_iam_binding" storage-admin {
  folder_id = var.folder_id
  members = ["serviceAccount:${yandex_iam_service_account.dataproc-sa.id}"]
  role = "storage.admin"
}

resource "yandex_iam_service_account_static_access_key" dataproc-sa-key {
  service_account_id = yandex_iam_service_account.dataproc-sa.id
}

resource "yandex_storage_bucket" spark-kafka {
  bucket_prefix = "spark-kafka"
  access_key = yandex_iam_service_account_static_access_key.dataproc-sa-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.dataproc-sa-key.secret_key
}

resource "yandex_storage_object" spark-application {
  bucket = yandex_storage_bucket.spark-kafka.bucket
  key    = "spark-application.py"
  source = "spark-application.py"
  access_key = yandex_iam_service_account_static_access_key.dataproc-sa-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.dataproc-sa-key.secret_key
}

resource "yandex_dataproc_cluster" "spark-kafka" {
  name        = "spark-kafka"
  zone_id     = "ru-central1-a"
  ui_proxy    = true
  service_account_id = yandex_iam_service_account.dataproc-sa.id

  cluster_config {
    version_id = "2.0"

    hadoop {
      services = ["HDFS", "MAPREDUCE", "SPARK", "YARN", "ZEPPELIN"]
      ssh_public_keys = [
        file("~/.ssh/id_rsa.pub")]
    }

    subcluster_spec {
      name = "main"
      role = "MASTERNODE"
      resources {
        resource_preset_id = "s2.medium"
        disk_type_id       = "network-hdd"
        disk_size          = 200
      }
      subnet_id   = yandex_vpc_subnet.spark-kafka-a.id
      hosts_count = 1
    }

    subcluster_spec {
      name = "data"
      role = "DATANODE"
      resources {
        resource_preset_id = "s2.medium"
        disk_type_id       = "network-hdd"
        disk_size          = 200
      }
      subnet_id   = yandex_vpc_subnet.spark-kafka-a.id
      hosts_count = 1
    }
  }
}

resource "local_file" "terraform_values" {
  filename        = "populate_kafka_env.list"
  file_permission = "0664"
  content = templatefile("populate_kafka_env.list.template", {
      bootstrap_servers = join(",", compact([for s in tolist(yandex_mdb_kafka_cluster.spark-kafka.host) : (s.role == "KAFKA" ? format("%s:9091", s.name) : "")]))
      admin_password = random_password.admin_password.result
      bucket_name = yandex_storage_bucket.spark-kafka.bucket
    }
  )
}
