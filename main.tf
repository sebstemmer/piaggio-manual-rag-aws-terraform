terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "region" {
  type        = string
  default     = "eu-central-1"
}

provider "aws" {
  region = "${var.region}"
}

variable "project" {
  type        = string
  description = "Project prefix for resource names"
  default     = "piaggio-manual-rag"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "main" {
  bucket = "${var.project}-${data.aws_caller_identity.current.account_id}-${var.region}"
  force_destroy = true
}

output "bucket_name" {
  value = aws_s3_bucket.main.id
}

data "archive_file" "pypdfium_layer" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/build/pypdfium"
  output_path = "${path.module}/lambdas/build/pypdfium.zip"
}

resource "aws_lambda_layer_version" "pypdfium" {
  layer_name               = "${var.project}-pypdfium"
  filename                 = data.archive_file.pypdfium_layer.output_path
  source_code_hash         = data.archive_file.pypdfium_layer.output_base64sha256
  compatible_runtimes      = ["python3.14"]
  compatible_architectures = ["arm64"]
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

###############
# count pages #
###############



######################
# manual pdf to pngs #
######################

resource "aws_iam_role" "manual_pdf_to_pngs" {
  name               = "manual-pdf-to-pngs"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "manual_pdf_to_pngs_policy" {
  role       = aws_iam_role.manual_pdf_to_pngs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

variable "manual_pdf_key" {
  type    = string
  default = "manual_as_pdf/manual.pdf"
}

output "manual_pdf_key" {
  value = var.manual_pdf_key
}

data "aws_iam_policy_document" "s3_read_manual_pdf" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main.arn}/${var.manual_pdf_key}"]
  }
}

resource "aws_iam_role_policy" "s3_read_manual_pdf" {
  name   = "s3-read-manual-pdf"
  role   = aws_iam_role.manual_pdf_to_pngs.name
  policy = data.aws_iam_policy_document.s3_read_manual_pdf.json
}

variable "pngs_prefix" {
  type    = string
  default = "pngs"
}

data "aws_iam_policy_document" "s3_write_pngs" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.main.arn}/${var.pngs_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "s3_write_pngs" {
  name   = "s3-write-pngs"
  role   = aws_iam_role.manual_pdf_to_pngs.name
  policy = data.aws_iam_policy_document.s3_write_pngs.json
}

data "archive_file" "manual_pdf_to_pngs" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/build/pdf_to_pngs"
  output_path = "${path.module}/lambdas/build/pdf_to_pngs.zip"
}

resource "aws_lambda_function" "manual_pdf_to_pngs" {
  function_name    = "manual-pdf-to-pngs"
  role             = aws_iam_role.manual_pdf_to_pngs.arn
  filename         = data.archive_file.manual_pdf_to_pngs.output_path
  source_code_hash = data.archive_file.manual_pdf_to_pngs.output_base64sha256

  handler       = "pdf_to_pngs.lambda_handler"
  runtime       = "python3.14"
  architectures = ["arm64"]
  layers        = [aws_lambda_layer_version.pypdfium.arn]

  timeout     = 100
  memory_size = 128

  environment {
    variables = {
      BUCKET         = aws_s3_bucket.main.id
      MANUAL_PDF_KEY = var.manual_pdf_key
      OUT_KEY_PREFIX        = var.pngs_prefix
    }
  }
}

#############
# png to md #
#############

resource "aws_iam_role" "png_to_md" {
  name               = "png-to-md"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "png_to_md" {
  role       = aws_iam_role.png_to_md.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "s3_read_pngs" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main.arn}/${var.pngs_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "s3_read_pngs" {
  name   = "s3-read-pngs"
  role   = aws_iam_role.png_to_md.name
  policy = data.aws_iam_policy_document.s3_read_pngs.json
}

data "aws_iam_policy_document" "s3_write_md_chunks" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.main.arn}/${var.md_chunks_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "s3_write_md_chunks" {
  name   = "s3-write-md-chunks"
  role   = aws_iam_role.png_to_md.name
  policy = data.aws_iam_policy_document.s3_write_md_chunks.json
}

data "aws_iam_policy_document" "bedrock_invoke_model" {
  statement {
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*",
    ]
  }
}

resource "aws_iam_role_policy" "bedrock_invoke_model" {
  name   = "bedrock-invoke-model"
  role   = aws_iam_role.png_to_md.name
  policy = data.aws_iam_policy_document.bedrock_invoke_model.json
}

data "archive_file" "png_to_md" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/build/png_to_md"
  output_path = "${path.module}/lambdas/build/png_to_md.zip"
}

variable "md_chunks_prefix" {
  type    = string
  default = "md_chunks"
}

resource "aws_lambda_function" "png_to_md" {
  function_name    = "png_to_md"
  role             = aws_iam_role.png_to_md.arn
  filename         = data.archive_file.png_to_md.output_path
  source_code_hash = data.archive_file.png_to_md.output_base64sha256

  handler       = "png_to_md.lambda_handler"
  runtime       = "python3.14"
  architectures = ["arm64"]

  timeout     = 180
  memory_size = 512

  environment {
    variables = {
      BUCKET         = aws_s3_bucket.main.id
      IN_KEY_PREFIX  = var.pngs_prefix
      OUT_KEY_PREFIX = var.md_chunks_prefix
    }
  }
}

#################
# step function #
#################

data "aws_iam_policy_document" "step_function_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "prepare_manual_for_rag" {
  name               = "prepare-manual-for-rag"
  assume_role_policy = data.aws_iam_policy_document.step_function_assume.json
}

data "aws_iam_policy_document" "invoke_lambdas" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.manual_pdf_to_pngs.arn,
      aws_lambda_function.png_to_md.arn,
    ]
  }
}

resource "aws_iam_role_policy" "invoke_lambda" {
  name   = "invoke-lambda"
  role   = aws_iam_role.prepare_manual_for_rag.name
  policy = data.aws_iam_policy_document.invoke_lambdas.json
}

resource "aws_sfn_state_machine" "prepare_manual_for_rag" {
  name     = "prepare-manual-for-rag"
  role_arn = aws_iam_role.prepare_manual_for_rag.arn

  definition = jsonencode({
    StartAt = "RenderFirstPage"
    States = {
      RenderFirstPage = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.manual_pdf_to_pngs.arn
          Payload      = { page = 1 }
        }
        End = true
      }
    }
  })
}