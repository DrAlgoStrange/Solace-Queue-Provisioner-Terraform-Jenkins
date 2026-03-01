################################################################################
# main.tf — Solace Queue Provisioner
#
# All queues (regular + DMQ) are declared in a single list variable: message_queues.
# The pipeline splits them automatically:
#   - A queue whose name appears as another queue's 'dmq' value → DMQ queue
#   - All other queues → regular queues
#
# The 'dmq' field on a regular queue wires the dead_msg_queue attribute to the
# named DMQ queue.  If 'dmq' is "" the queue has no DMQ association.
################################################################################

terraform {
  required_providers {
    solacebroker = {
      source  = "SolaceProducts/solacebroker"
      version = "~> 1.0"
    }
  }
  required_version = ">= 1.3.0"
}

################################################################################
# Provider
################################################################################
provider "solacebroker" {
  url      = var.semp_url
  username = var.admin_username
  password = var.admin_password

  request_timeout_duration = "120s"
  request_min_interval     = "100ms"
}

################################################################################
# Locals — split the single list into regular queues and DMQ queues
################################################################################
locals {

  # Collect the set of all DMQ names referenced across all queue entries
  dmq_names_set = toset([
    for q in var.message_queues : q.dmq
    if q.dmq != ""
  ])

  # Regular queues = entries whose name is NOT in the DMQ names set
  regular_queues = [
    for q in var.message_queues : q
    if !contains(local.dmq_names_set, q.name)
  ]

  # DMQ queues = entries whose name IS in the DMQ names set
  dmq_queues = [
    for q in var.message_queues : q
    if contains(local.dmq_names_set, q.name)
  ]

  # Flatten topic pairs for regular queues  →  key = "queueName||topic"
  mq_topic_pairs = merge([
    for q in local.regular_queues : {
      for t in q.topics :
        "${q.name}||${t}" => {
          queue_name   = q.name
          topic_string = t
        }
    }
  ]...)

  # Flatten topic pairs for DMQ queues
  dmq_topic_pairs = merge([
    for q in local.dmq_queues : {
      for t in q.topics :
        "${q.name}||${t}" => {
          queue_name   = q.name
          topic_string = t
        }
    }
  ]...)
}

################################################################################
# Regular Message Queues
################################################################################
resource "solacebroker_msg_vpn_queue" "message_queues" {
  for_each = { for q in local.regular_queues : q.name => q }

  msg_vpn_name = var.message_vpn
  queue_name   = each.key

  # --- Access ---
  ingress_enabled = var.mq_config.ingress_enabled != "" ? tobool(var.mq_config.ingress_enabled) : null
  egress_enabled  = var.mq_config.egress_enabled  != "" ? tobool(var.mq_config.egress_enabled)  : null
  access_type     = var.mq_config.access_type     != "" ? var.mq_config.access_type              : null

  # --- Quota ---
  max_msg_spool_usage = var.mq_config.max_msg_spool_usage != "" ? tonumber(var.mq_config.max_msg_spool_usage) : null

  # --- Ownership & Permissions ---
  owner      = var.mq_config.owner      != "" ? var.mq_config.owner      : null
  permission = var.mq_config.permission != "" ? var.mq_config.permission  : null

  # --- Consumer Limits ---
  max_bind_count                      = var.mq_config.max_bind_count                      != "" ? tonumber(var.mq_config.max_bind_count)                      : null
  max_delivered_unacked_msgs_per_flow = var.mq_config.max_delivered_unacked_msgs_per_flow != "" ? tonumber(var.mq_config.max_delivered_unacked_msgs_per_flow) : null

  # --- DMQ association (per-queue, declared in MessageQueue.yaml) ---
  # each.value.dmq is "" when no DMQ is declared for this queue
  dead_msg_queue = each.value.dmq != "" ? each.value.dmq : null

  # --- Delivery ---
  delivery_count_enabled = var.mq_config.delivery_count_enabled != "" ? tobool(var.mq_config.delivery_count_enabled)  : null
  delivery_delay         = var.mq_config.delivery_delay         != "" ? tonumber(var.mq_config.delivery_delay)         : null

  # --- TTL ---
  respect_ttl_enabled = var.mq_config.respect_ttl != "" ? tobool(var.mq_config.respect_ttl) : null
  max_ttl     = var.mq_config.max_ttl     != "" ? tonumber(var.mq_config.max_ttl)   : null

  # --- Redelivery ---
  redelivery_enabled   = var.mq_config.redelivery_enabled   != "" ? tobool(var.mq_config.redelivery_enabled)    : null
  max_redelivery_count = var.mq_config.max_redelivery_count != "" ? tonumber(var.mq_config.max_redelivery_count) : null

  lifecycle { prevent_destroy = false }
}

################################################################################
# Regular Queue — Topic Subscriptions
################################################################################
resource "solacebroker_msg_vpn_queue_subscription" "mq_subscriptions" {
  for_each = local.mq_topic_pairs

  msg_vpn_name       = var.message_vpn
  queue_name         = each.value.queue_name
  subscription_topic = each.value.topic_string

  depends_on = [solacebroker_msg_vpn_queue.message_queues]
}

################################################################################
# Dead Message Queues
# Created first so regular queues can reference them in dead_msg_queue
################################################################################
resource "solacebroker_msg_vpn_queue" "dead_message_queues" {
  for_each = { for q in local.dmq_queues : q.name => q }

  msg_vpn_name = var.message_vpn
  queue_name   = each.key

  ingress_enabled = var.dmq_config.ingress_enabled != "" ? tobool(var.dmq_config.ingress_enabled) : null
  egress_enabled  = var.dmq_config.egress_enabled  != "" ? tobool(var.dmq_config.egress_enabled)  : null
  access_type     = var.dmq_config.access_type     != "" ? var.dmq_config.access_type              : null

  max_msg_spool_usage = var.dmq_config.max_msg_spool_usage != "" ? tonumber(var.dmq_config.max_msg_spool_usage) : null

  owner      = var.dmq_config.owner      != "" ? var.dmq_config.owner      : null
  permission = var.dmq_config.permission != "" ? var.dmq_config.permission  : null

  max_bind_count                      = var.dmq_config.max_bind_count                      != "" ? tonumber(var.dmq_config.max_bind_count)                      : null
  max_delivered_unacked_msgs_per_flow = var.dmq_config.max_delivered_unacked_msgs_per_flow != "" ? tonumber(var.dmq_config.max_delivered_unacked_msgs_per_flow) : null

  delivery_count_enabled = var.dmq_config.delivery_count_enabled != "" ? tobool(var.dmq_config.delivery_count_enabled)  : null
  delivery_delay         = var.dmq_config.delivery_delay         != "" ? tonumber(var.dmq_config.delivery_delay)         : null

  respect_ttl_enabled = var.mq_config.respect_ttl != "" ? tobool(var.mq_config.respect_ttl) : null
  max_ttl     = var.dmq_config.max_ttl     != "" ? tonumber(var.dmq_config.max_ttl)   : null

  redelivery_enabled   = var.dmq_config.redelivery_enabled   != "" ? tobool(var.dmq_config.redelivery_enabled)    : null
  max_redelivery_count = var.dmq_config.max_redelivery_count != "" ? tonumber(var.dmq_config.max_redelivery_count) : null

  lifecycle { prevent_destroy = false }
}

################################################################################
# Dead Message Queue — Topic Subscriptions
################################################################################
resource "solacebroker_msg_vpn_queue_subscription" "dmq_subscriptions" {
  for_each = local.dmq_topic_pairs

  msg_vpn_name       = var.message_vpn
  queue_name         = each.value.queue_name
  subscription_topic = each.value.topic_string

  depends_on = [solacebroker_msg_vpn_queue.dead_message_queues]
}
