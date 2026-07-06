variable "turso_db_url" {
  type    = string
  default = getenv("TURSO_DB_URL")
}

variable "turso_token" {
  type    = string
  default = getenv("TURSO_TOKEN")
}

locals {
  turso_test_url = "${var.turso_db_url}?authToken=${var.turso_token}"
}

env "turso_test" {
  src = "file://db/schema.sql"
  url = local.turso_test_url
  dev = "sqlite://file?mode=memory&_fk=1"

  exclude = ["_litestream*"]

  migration {
    dir = "file://db/migrations"
  }
}
