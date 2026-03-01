################################################################################
# variables.tf
# All inputs are supplied by the Jenkins pipeline at runtime.
# Do NOT hardcode credentials here.
################################################################################

variable "semp_url" {
  description = "Solace SEMPv2 API base URL"
  type        = string
}

variable "admin_username" {
  description = "Solace admin username (injected from Jenkins credentials)"
  type        = string
  sensitive   = true
}

variable "admin_password" {
  description = "Solace admin password (injected from Jenkins credentials)"
  type        = string
  sensitive   = true
}

variable "message_vpn" {
  description = "Solace Message VPN name"
  type        = string
}

################################################################################
# Queue list
# Each entry:
#   name   (required) — queue name
#   topics (required) — list of topic subscriptions; empty list = no subscriptions
#   dmq    (required) — name of the associated DMQ queue; empty string = no DMQ
#
# The pipeline separates regular queues from DMQ queues automatically:
#   - A queue whose name appears as any other queue's 'dmq' value → DMQ queue
#   - All other queues → regular queues
################################################################################

variable "message_queues" {
  description = "All queues (regular + DMQ) parsed from MessageQueue.yaml"
  type = list(object({
    name   = string
    topics = list(string)
    dmq    = string
  }))
  default = []
}

################################################################################
# Config objects
# An empty string ("") means: use the Solace provider/broker default.
################################################################################

variable "mq_config" {
  description = "Settings applied to all regular Message Queues"
  type = object({
    ingress_enabled                     = string
    egress_enabled                      = string
    access_type                         = string
    max_msg_spool_usage                 = string
    owner                               = string
    permission                          = string
    max_bind_count                      = string
    max_delivered_unacked_msgs_per_flow = string
    delivery_count_enabled              = string
    delivery_delay                      = string
    respect_ttl                         = string
    max_ttl                             = string
    redelivery_enabled                  = string
    max_redelivery_count                = string
  })
}

variable "dmq_config" {
  description = "Settings applied to all Dead Message Queues"
  type = object({
    ingress_enabled                     = string
    egress_enabled                      = string
    access_type                         = string
    max_msg_spool_usage                 = string
    owner                               = string
    permission                          = string
    max_bind_count                      = string
    max_delivered_unacked_msgs_per_flow = string
    delivery_count_enabled              = string
    delivery_delay                      = string
    respect_ttl                         = string
    max_ttl                             = string
    redelivery_enabled                  = string
    max_redelivery_count                = string
  })
}
