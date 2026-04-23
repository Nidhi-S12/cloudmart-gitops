output "sns_topic_arn" {
  description = "SNS topic ARN — passed to AlertManager config so it knows where to publish"
  value       = aws_sns_topic.alerts.arn
}
