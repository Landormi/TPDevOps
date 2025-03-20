terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.91.0"
    }
  }
}

provider "aws" {
  region = "eu-west-3"
}

data "aws_iam_role" "existing_lambda_role" {
  name = "g2-lambda-exec-role"
}

resource "aws_iam_role" "lambda_exec_role" {
  count = length(data.aws_iam_role.existing_lambda_role.id) == 0 ? 1 : 0

  name               = "g2-lambda-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Attache la politique de logs CloudWatch à la Lambda
resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Crée un zip automatiquement depuis le dossier lambda/
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# Création de la Lambda
resource "aws_lambda_function" "my_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "g2-lambda-time"
  handler          = "index.handler"
  runtime          = "nodejs18.x"
  role             = aws_iam_role.lambda_exec_role.arn
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

# API Gateway HTTP
resource "aws_apigatewayv2_api" "api_gw" {
  name          = "g2-api"
  protocol_type = "HTTP"
}

# Intégration Lambda avec API Gateway
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.api_gw.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.my_lambda.invoke_arn
}

# Route GET /
resource "aws_apigatewayv2_route" "lambda_route" {
  api_id    = aws_apigatewayv2_api.api_gw.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# Déploiement automatique de l'API (stage $default)
resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.api_gw.id
  name        = "$default"
  auto_deploy = true
}

# Autorise API Gateway à appeler Lambda
resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api_gw.execution_arn}/*/*"
}
