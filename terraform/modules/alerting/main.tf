# -------------------------------------------------------
# SNS topic for AlertManager → email notifications
# AlertManager publishes to this topic via IRSA
# SNS fans out to all email subscribers
# -------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"

  tags = {
    Name        = "${var.project_name}-${var.environment}-alerts"
    Project     = var.project_name
    Environment = var.environment
  }
}

# -------------------------------------------------------
# Email subscription — AWS sends a confirmation link
# to the address; must click it before alerts are delivered
# -------------------------------------------------------
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
