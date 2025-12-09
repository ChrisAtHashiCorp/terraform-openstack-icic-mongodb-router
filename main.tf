resource "random_id" "cluster_id" {
  byte_length = 8
}

resource "random_id" "node_id" {
  count       = var.node_count
  byte_length = 8
}

locals {
  fqdns = [for i in range(var.node_count) : "${var.name_prefix}-${random_id.node_id[i].hex}.${var.domain}"]

  mongod-config = [for i in range(var.node_count) : templatefile("${path.module}/provision/mongod.conf.tftpl",
    {
      fqdn       = local.fqdns[i]
      configdb   = var.configdb
    }
  )]

  user-data = [for i in range(var.node_count) : templatefile("${path.module}/provision/cloud-init.yml.tftpl",
    {
      fqdn              = local.fqdns[i]
      configrs-hosts    = base64encode(join("\n", [ for k, v in var.configrs_hosts : "${v} ${k}" ]))
      mongod-config     = base64encode(local.mongod-config[i])
    }
  )]
}

resource "openstack_compute_keypair_v2" "sshkey" {
  name = "${var.sshkey_prefix}-${random_id.cluster_id.hex}"
}

data "openstack_networking_network_v2" "network" {
  name = var.network
}

resource "openstack_networking_port_v2" "port" {
  count = var.node_count

  name  = "port-${count.index}"
  network_id = data.openstack_networking_network_v2.network.id
}

resource "openstack_compute_instance_v2" "nodes" {
  count = var.node_count

  name        = local.fqdns[count.index]
  image_id    = var.image_id
  flavor_name = var.flavor
  key_pair    = openstack_compute_keypair_v2.sshkey.name
  user_data   = local.user-data[count.index]

  network {
    port = openstack_networking_port_v2.port[count.index].id
  }

  tags = ["cluster_id=${random_id.cluster_id.hex}", "managed=terraform"]

  lifecycle {
    ignore_changes = [user_data]
  }
}
