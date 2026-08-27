resource "aws_cloudwatch_log_group" "retrieval" {
  name              = "/${var.project}/retrieval"
  retention_in_days = 7
}

resource "aws_iam_role" "retrieval" {
  name               = "${var.project}-retrieval"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "retrieval" {
  role       = aws_iam_role.retrieval.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "s3_read_embeddings" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main.arn}/${var.embeddings_key}"]
  }
}

resource "aws_iam_role_policy" "s3_read_embeddings" {
  name   = "s3-read-embeddings"
  role   = aws_iam_role.retrieval.name
  policy = data.aws_iam_policy_document.s3_read_embeddings.json
}

resource "aws_iam_role_policy" "retrieval_bedrock_invoke_model" {
  name   = "bedrock-invoke-model"
  role   = aws_iam_role.retrieval.name
  policy = data.aws_iam_policy_document.bedrock_invoke_model.json
}

data "archive_file" "retrieval" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/build/retrieval"
  output_path = "${path.module}/lambdas/build/retrieval.zip"
}

variable "telegram_token" {
  type        = string
  sensitive   = true
}

variable "webhook_secret" {
  type        = string
  sensitive   = true
}

resource "aws_lambda_function_url" "retrieval" {
  function_name      = aws_lambda_function.retrieval.function_name
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "retrieval_url" {
  statement_id           = "AllowPublicFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.retrieval.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

output "retrieval_function_url" {
  value = aws_lambda_function_url.retrieval.function_url
}

resource "aws_lambda_function" "retrieval" {
  function_name    = "${var.project}-retrieval"
  role             = aws_iam_role.retrieval.arn
  filename         = data.archive_file.retrieval.output_path
  source_code_hash = data.archive_file.retrieval.output_base64sha256

  handler       = "retrieval.lambda_handler"
  runtime       = "python3.14"
  architectures = ["arm64"]

  timeout     = 100
  memory_size = 128

  environment {
    variables = {
      BUCKET         = aws_s3_bucket.main.id
      TELEGRAM_TOKEN = var.telegram_token
      WEBHOOK_SECRET = var.webhook_secret
      IN_KEY         = var.embeddings_key
    }
  }

  logging_config {
    log_group             = aws_cloudwatch_log_group.retrieval.name
    log_format            = "JSON"
    application_log_level = "INFO"
  }
}