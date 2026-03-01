################################################################################
# outputs.tf
################################################################################

output "created_message_queues" {
  description = "Regular queue names created/managed"
  value       = [for q in solacebroker_msg_vpn_queue.message_queues : q.queue_name]
}

output "created_dead_message_queues" {
  description = "Dead Message Queue names created/managed"
  value       = [for q in solacebroker_msg_vpn_queue.dead_message_queues : q.queue_name]
}

output "created_mq_subscriptions" {
  description = "Topic subscriptions on regular queues"
  value       = [for s in solacebroker_msg_vpn_queue_subscription.mq_subscriptions : "${s.queue_name} → ${s.subscription_topic}"]
}

output "created_dmq_subscriptions" {
  description = "Topic subscriptions on Dead Message Queues"
  value       = [for s in solacebroker_msg_vpn_queue_subscription.dmq_subscriptions : "${s.queue_name} → ${s.subscription_topic}"]
}

output "total_queues" {
  description = "Total queues created/managed"
  value       = length(solacebroker_msg_vpn_queue.message_queues) + length(solacebroker_msg_vpn_queue.dead_message_queues)
}

output "total_subscriptions" {
  description = "Total topic subscriptions created/managed"
  value       = length(solacebroker_msg_vpn_queue_subscription.mq_subscriptions) + length(solacebroker_msg_vpn_queue_subscription.dmq_subscriptions)
}
