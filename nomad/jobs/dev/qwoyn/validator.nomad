# CONSUL_PATH env variable must be set before rendering.
# Example: CONSUL_PATH="cosmoshub/sentry0" levant render -out jobs/prod/cosmoshub/sentry0.nomad templates/node/node.levant
# refer to infra/docs/port-management.md

variables {
  config_repo_url    = "https://raw.githubusercontent.com/cephalopodequipment/config/main"
  genesis_bucket_url = "https://cec-genesis-files.s3.ca-central-1.amazonaws.com"

  network          = "qwoyn-1"
  sdk_version      = "0.47.x"
  chain_id         = "qwoyn-1"
  home_dir         = "/root/qwoynd/.qwoynd"
  node_id          = "validator"
}

job "osmosis-testnet-validator" {
  datacenters = [
    "dc1"
  ]

  reschedule {
    attempts       = "3"
    interval       = "1h"
    delay          = "30s"
    delay_function = "exponential"
    max_delay      = "120s"
    unlimited      = false
  }

  type = "service"

  group "node-tasks" {
    constraint {
      attribute = "${node.unique.name}"
      value     = "dev1"
    }

    network {
      mode = "host"
      port "rpc" {
        static = "27020"
        to     = "26657"
      }

      port "leet" { static = "27021" }
      port "grpc" { static = "27022" }
      port "prom" { static = "27024" }
      port "tmkms" { static = "27025" }
      port "pprof" { static = "27026" }

      port "p2p" { static = "32702" }
    }

    task osmosis-testnet_validator {
      driver = "docker"

      service {
        name    = "network-node"
        tags    = ["node-sdk", "${var.chain_id}", "${var.node_id}"]
        address = "${attr.unique.network.ip-address}"

        meta {
          # camel case so it doesn't break json processing in zabbix
          # Used in:
          #  - Zabbix item "Cosmos SDK" in "Node job discovery" template
          PortRpc         = "${NOMAD_HOST_PORT_rpc}"
          PortRest        = "${NOMAD_HOST_PORT_leet}"
          PortGrpc        = "${NOMAD_HOST_PORT_grpc}"
          PortProm        = "${NOMAD_HOST_PORT_prom}"
          NodeHomeDir     = "${var.home_dir}"
          ConsulPath      = "osmosis-testnet/validator"
          ChainId         = "${var.chain_id}"
          TaskName        = "${NOMAD_TASK_NAME}"
          SDKVersion      = "${var.sdk_version}"
          Network         = "${var.network}"
        }
      }

      restart {
        attempts = "3"
        delay    = "15s"
        interval = "10m"
        mode     = "fail"
      }

      env {
        CONSUL_PATH = "networks/osmosis-testnet/validator"
        VALIDATOR   = "true"
      }

      artifact {
        source = "${var.config_repo_url}/cosmos-sdk/${var.sdk_version}/app.toml.tpl"
      }

      artifact {
        source = "${var.config_repo_url}/cosmos-sdk/${var.sdk_version}/config.toml.tpl"
      }

      artifact {
        source = "${var.config_repo_url}/cosmos-sdk/client.toml.tpl"
      }

      artifact {
        source      = "${var.genesis_bucket_url}/${var.chain_id}.json.tgz"
        destination = "local/genesis.json.tmp"
        mode        = "file"
      }

      template {
        source      = "local/genesis.json.tmp"
        destination = "local/genesis.json"
        perms       = "646"
      }

      template {
        data        = "{{ key \"node.id/${var.node_id}/node_key\" }}"
        destination = "local/node_key.json"
      }

      template {
        data        = "{{ key \"node.id/${var.node_id}/priv_validator_key\" }}"
        destination = "local/priv_validator_key.json"
      }

      template {
        source      = "local/config.toml.tpl"
        destination = "local/config.toml"
        perms       = "646"
      }

      template {
        source      = "local/app.toml.tpl"
        destination = "local/app.toml"
      }

      template {
        source      = "local/client.toml.tpl"
        destination = "local/client.toml"
      }

      template {
        data        = <<EOF
DOCKER_IMAGE_TAG={{ key "networks/osmosis-testnet/validator/nomad_job/docker_image_tag" }}
EOF
        destination = "var.env"
        env         = true
      }

      config {
        image   = "cephalopodequipment/osmosisd:${DOCKER_IMAGE_TAG}"
        command = "start"

        ports = [
          "p2p",
          "rpc",
          "grpc",
          "leet",
          "prom",
          "tmkms",
          "pprof"
        ]

        mount {
          type   = "volume"
          target = "${var.home_dir}"
          source = "${var.network}-${var.node_id}"
        }

        mount {
          type   = "bind"
          target = "${var.home_dir}/config/config.toml"
          source = "local/config.toml"
        }

        mount {
          type   = "bind"
          target = "${var.home_dir}/config/app.toml"
          source = "local/app.toml"
        }

        mount {
          type   = "bind"
          target = "${var.home_dir}/config/client.toml"
          source = "local/client.toml"
        }

        mount {
          type   = "bind"
          target = "${var.home_dir}/config/genesis.json"
          source = "local/genesis.json"
        }

        mount {
          type   = "bind"
          target = "${var.home_dir}/config/node_key.json"
          source = "local/node_key.json"
        }

        mount {
          type   = "bind"
          target = "${var.home_dir}/config/priv_validator_key.json"
          source = "local/priv_validator_key.json"
        }

        mount {
          type     = "bind"
          target   = "/etc/localtime"
          source   = "/etc/localtime"
          readonly = true
        }

        logging {
          type = "fluentd"
          config {
            fluentd-address              = "${attr.unique.network.ip-address}:5140"
            fluentd-async                = "true"
            fluentd-buffer-limit         = "17000"
            fluentd-sub-second-precision = "true"

            tag = "node.sdk.osmosis-testnet.validator"
          }
        }
      }

      resources {
        cpu    = 5000
        memory = 24000
      }
    }
  }
}