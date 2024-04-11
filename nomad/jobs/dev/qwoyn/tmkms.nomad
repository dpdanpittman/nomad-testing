variables {
  priv_key_network       = "qwoyn-1"
  nomad_node_unique_name = "testing-validators"
  chain_id               = "qwoyn-1"
  account_key_prefix     = "qwoynpub"
  consensus_key_prefix   = "qwoynvaloper"
  node_laddr             = ""

  config_repo_url = "https://raw.githubusercontent.com/cephalopodequipment/config/main"
}

job "" {
  datacenters = [
    "aws-cac"
  ]

  type = "service"

  group "tmkms" {

    constraint {
      attribute = "${node.unique.name}"
      value     = "${var.nomad_node_unique_name}"
    }

    service {
      name = "tmkms-softsign"
      tags = ["${var.chain_id}"]
    }

    task "softsign" {
      driver = "docker"

      vault {
        policies = ["nomad-configure-services"]
      }

      artifact {
        source = "${var.config_repo_url}/tmkms/consensus.key.tpl"
      }

      template {
        source      = "local/consensus.key.tpl"
        destination = "secrets/privkey"
      }

      artifact {
        source = "${var.config_repo_url}/tmkms/tmkms.toml.tpl"
      }

      template {
        source      = "local/tmkms.toml.tpl"
        destination = "local/tmkms.toml"
      }

      env {
        CHAIN_ID             = "${var.chain_id}"
        ACCT_KEY_PREFIX      = "${var.account_key_prefix}"
        CONSENSUS_KEY_PREFIX = "${var.consensus_key_prefix}"
        NODE_LADDR           = "${var.node_laddr}"
        PRIV_KEY_NETWORK     = "${var.priv_key_network}"
      }

      config {
        image   = "cephalopodequipment/tmkms:main-softsign"
        command = "start"

        mount {
          type   = "volume"
          target = "/home/tmkms"
          source = "tmkms-${var.chain_id}"
        }

        mount {
          type   = "bind"
          target = "/home/tmkms/secrets/consensus.key"
          source = "secrets/privkey"
        }

        mount {
          type   = "bind"
          target = "/home/tmkms/tmkms.toml"
          source = "local/tmkms.toml"
        }

        logging {
          type = "fluentd"
          config {
            fluentd-address              = "${attr.unique.network.ip-address}:5140"
            fluentd-async                = "true"
            fluentd-buffer-limit         = "17000"
            fluentd-sub-second-precision = "true"

            tag = "tmkms-${var.chain_id}"
          }
        }
      }

      resources {
        cpu    = 100
        memory = 100
      }
    }
  }
}
