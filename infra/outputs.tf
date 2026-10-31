# --- Auth Outputs (auth.yml) -------------------------------------------------
output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}
output "user_pool_client_id" {
  description = "Cognito User Pool Web Client ID"
  value       = aws_cognito_user_pool_client.web.id
}
output "issuer" {
  description = "The 'iss' of every token; its signing keys are at <Issuer>/.well-known/jwks.json"
  value       = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}
output "hosted_domain" {
  description = "Cognito OAuth hosted domain"
  value       = "${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com"
}
output "google_redirect_uri" {
  description = "Redirect URI to configure in Google Cloud Console"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.region}.amazoncognito.com/oauth2/idpresponse"
}
output "google_enabled" {
  description = "Whether Google sign-in is enabled"
  value       = var.google_client_id != "" ? "true" : "false"
}
# CloudFormation exact casing aliases (for Makefile / legacy script compatibility)
output "UserPoolId" {
  value = aws_cognito_user_pool.main.id
}