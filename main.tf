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

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_cloudwatch_log_group" "lambdas" {
  name              = "/${var.project}/lambdas"
  retention_in_days = 14
}


##################
# pypdfium layer #
##################

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

###############
# count pages #
###############

resource "aws_iam_role" "count_pages" {
  name               = "${var.project}-count-pages"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "count_pages" {
  role       = aws_iam_role.count_pages.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "s3_read_manual_pdf" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main.arn}/${var.manual_pdf_key}"]
  }
}

resource "aws_iam_role_policy" "count_pages_s3_read_manual_pdf" {
  name   = "s3-read-manual-pdf"
  role   = aws_iam_role.count_pages.name
  policy = data.aws_iam_policy_document.s3_read_manual_pdf.json
}

data "archive_file" "count_pages" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/build/count_pages"
  output_path = "${path.module}/lambdas/build/count_pages.zip"
}

resource "aws_lambda_function" "count_pages" {
  function_name    = "${var.project}-count-pages"
  role             = aws_iam_role.count_pages.arn
  filename         = data.archive_file.count_pages.output_path
  source_code_hash = data.archive_file.count_pages.output_base64sha256

  handler       = "count_pages.lambda_handler"
  runtime       = "python3.14"
  architectures = ["arm64"]
  layers        = [aws_lambda_layer_version.pypdfium.arn]

  timeout     = 100
  memory_size = 128

  environment {
    variables = {
      BUCKET         = aws_s3_bucket.main.id
      MANUAL_PDF_KEY = var.manual_pdf_key
    }
  }

  logging_config {
    log_group             = aws_cloudwatch_log_group.lambdas.name
    log_format            = "JSON"
    application_log_level = "INFO"
  }
}

######################
# manual pdf to pngs #
######################

resource "aws_iam_role" "manual_pdf_to_pngs" {
  name               = "${var.project}-manual-pdf-to-pngs"
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

resource "aws_iam_role_policy" "manual_pdf_to_pngs_s3_read_manual_pdf" {
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
  function_name    = "${var.project}-manual-pdf-to-pngs"
  role             = aws_iam_role.manual_pdf_to_pngs.arn
  filename         = data.archive_file.manual_pdf_to_pngs.output_path
  source_code_hash = data.archive_file.manual_pdf_to_pngs.output_base64sha256

  handler       = "pdf_to_pngs.lambda_handler"
  runtime       = "python3.14"
  architectures = ["arm64"]
  layers        = [aws_lambda_layer_version.pypdfium.arn]

  timeout     = 100
  memory_size = 512

  environment {
    variables = {
      BUCKET         = aws_s3_bucket.main.id
      MANUAL_PDF_KEY = var.manual_pdf_key
      OUT_KEY_PREFIX        = var.pngs_prefix
    }
  }

  logging_config {
    log_group             = aws_cloudwatch_log_group.lambdas.name
    log_format            = "JSON"
    application_log_level = "INFO"
  }
}

#############
# png to md #
#############

resource "aws_iam_role" "png_to_md" {
  name               = "${var.project}-png-to-md"
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
      aws_lambda_function.count_pages.arn,
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
  function_name    = "${var.project}-png-to-md"
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

  logging_config {
    log_group             = aws_cloudwatch_log_group.lambdas.name
    log_format            = "JSON"
    application_log_level = "INFO"
  }
}

#############
# merge mds #
#############

resource "aws_iam_role" "merge_mds" {
  name               = "${var.project}-merge-mds"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "merge_mds" {
  role       = aws_iam_role.merge_mds.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "s3_read_mds" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main.arn}/${var.md_chunks_prefix}/*"]
  }
}

resource "aws_iam_role_policy" "s3_read_mds" {
  name   = "s3-read-mds"
  role   = aws_iam_role.merge_mds.name
  policy = data.aws_iam_policy_document.s3_read_mds.json
}

variable "merged_md_key" {
  type    = string
  default = "merged_md/merged.md"
}

data "aws_iam_policy_document" "s3_write_merged_md" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.main.arn}/${var.merged_md_key}"]
  }
}

resource "aws_iam_role_policy" "s3_write_merged_md" {
  name   = "s3-write-merged-md"
  role   = aws_iam_role.merge_mds.name
  policy = data.aws_iam_policy_document.s3_write_merged_md.json
}

data "archive_file" "merge_mds" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/build/merge_mds"
  output_path = "${path.module}/lambdas/build/merge_mds.zip"
}

resource "aws_lambda_function" "merge_mds" {
  function_name    = "${var.project}-merge-mds"
  role             = aws_iam_role.merge_mds.arn
  filename         = data.archive_file.merge_mds.output_path
  source_code_hash = data.archive_file.merge_mds.output_base64sha256

  handler       = "merge_mds.lambda_handler"
  runtime       = "python3.14"
  architectures = ["arm64"]

  timeout     = 100
  memory_size = 128

  environment {
    variables = {
      BUCKET         = aws_s3_bucket.main.id
      IN_KEY_PREFIX  = var.md_chunks_prefix
      OUT_KEY = var.merged_md_key
    }
  }

  logging_config {
    log_group             = aws_cloudwatch_log_group.lambdas.name
    log_format            = "JSON"
    application_log_level = "INFO"
  }
}

############
# chunking #
############

resource "aws_iam_role" "chunking" {
  name               = "${var.project}-chunking"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "chunking" {
  role       = aws_iam_role.chunking.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "s3_read_merged_md" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.main.arn}/${var.merged_md_key}"]
  }
}

resource "aws_iam_role_policy" "s3_read_merged_md" {
  name   = "s3-read-merged-md"
  role   = aws_iam_role.chunking.name
  policy = data.aws_iam_policy_document.s3_read_merged_md.json
}

variable "chunks_key" {
  type    = string
  default = "chunks/chunks.ljson"
}

data "aws_iam_policy_document" "s3_write_chunks" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.main.arn}/${var.chunks_key}"]
  }
}

resource "aws_iam_role_policy" "s3_write_chunks" {
  name   = "s3-write-chunks"
  role   = aws_iam_role.chunking.name
  policy = data.aws_iam_policy_document.s3_write_chunks.json
}

data "archive_file" "chunking" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/build/chunking"
  output_path = "${path.module}/lambdas/build/chunking.zip"
}

resource "aws_lambda_function" "chunking" {
  function_name    = "${var.project}-chunking"
  role             = aws_iam_role.chunking.arn
  filename         = data.archive_file.chunking.output_path
  source_code_hash = data.archive_file.chunking.output_base64sha256

  handler       = "chunking.lambda_handler"
  runtime       = "python3.14"
  architectures = ["arm64"]

  timeout     = 100
  memory_size = 128

  environment {
    variables = {
      BUCKET         = aws_s3_bucket.main.id
      IN_KEY  = var.merged_md_key
      OUT_KEY = var.chunks_key
    }
  }

  logging_config {
    log_group             = aws_cloudwatch_log_group.lambdas.name
    log_format            = "JSON"
    application_log_level = "INFO"
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
  name               = "${var.project}-prepare-manual-for-rag"
  assume_role_policy = data.aws_iam_policy_document.step_function_assume.json
}

data "aws_iam_policy_document" "invoke_lambdas" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [
      aws_lambda_function.count_pages.arn,
      aws_lambda_function.manual_pdf_to_pngs.arn,
      aws_lambda_function.png_to_md.arn,
      aws_lambda_function.merge_mds.arn,
      aws_lambda_function.chunking.arn
    ]
  }
}

resource "aws_iam_role_policy" "invoke_lambda" {
  name   = "invoke-lambda"
  role   = aws_iam_role.prepare_manual_for_rag.name
  policy = data.aws_iam_policy_document.invoke_lambdas.json
}

resource "aws_sfn_state_machine" "prepare_manual_for_rag" {
  name     = "${var.project}-prepare-manual-for-rag"
  role_arn = aws_iam_role.prepare_manual_for_rag.arn

  definition = jsonencode({
    QueryLanguage = "JSONata"
    StartAt       = "count-pages"
    States = {

      "count-pages" = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Arguments = {
          FunctionName = aws_lambda_function.count_pages.arn
        }
        Assign = {
          totalPages = "{% $states.result.Payload.total_pages %}"
          modelId    = "{% $states.input.model_id %}"
          startAt    = "{% $states.input.start_at %}"

          chunkSize    = "{% $states.input.chunk_size %}"
          chunkOverlap = "{% $states.input.chunk_overlap %}"
        }
        Next = "route"
      }

      "route" = {
        Type = "Choice"
        Choices = [
          {
            Condition = "{% $startAt = 'all' %}"
            Next      = "pdf-to-pngs"
          },
          {
            Condition = "{% $startAt = 'pngs-to-mds' %}"
            Next      = "pngs-to-mds"
          },
          {
            Condition = "{% $startAt = 'merge-mds' %}"
            Next      = "merge-mds"
          },
          {
            Condition = "{% $startAt = 'chunking' %}"
            Next      = "chunking"
          },
        ]
      }

      "pdf-to-pngs" = {
        Type           = "Map"
        Items          = "{% [1..$totalPages] %}"
        MaxConcurrency = 5
        ItemProcessor = {
          ProcessorConfig = { Mode = "INLINE" }
          StartAt         = "pdf-page-to-png"
          States = {
            "pdf-page-to-png" = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Arguments = {
                FunctionName = aws_lambda_function.manual_pdf_to_pngs.arn
                Payload      = { page = "{% $states.input %}" }
              }
              Output = "{% $states.result.Payload %}"
              End    = true
            }
          }
        }
        Next = "pngs-to-mds"
      }

      "pngs-to-mds" = {
        Type           = "Map"
        Items          = "{% [1..$totalPages] %}"
        MaxConcurrency = 5
        ItemProcessor = {
          ProcessorConfig = { Mode = "INLINE" }
          StartAt         = "png-to-md"
          States = {
            "png-to-md" = {
              Type     = "Task"
              Resource = "arn:aws:states:::lambda:invoke"
              Arguments = {
                FunctionName = aws_lambda_function.png_to_md.arn
                Payload = {
                  page     = "{% $states.input %}"
                  model_id = "{% $modelId %}"
                }
              }
              Output = "{% $states.result.Payload %}"
              End    = true
            }
          }
        }
        Next = "merge-mds"
      }

      "merge-mds" = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Arguments = {
          FunctionName = aws_lambda_function.merge_mds.arn
          Payload      = { total_pages = "{% $totalPages %}" }
        }
        Output = "{% $states.result.Payload %}"
        Next   = "chunking"
      }

      "chunking" = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Arguments = {
          FunctionName = aws_lambda_function.chunking.arn
          Payload = {
            chunk_size    = "{% $chunkSize %}"
            chunk_overlap = "{% $chunkOverlap %}"
          }
        }
        Output = "{% $states.result.Payload %}"
        End    = true
      }
    }
  })
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.prepare_manual_for_rag.arn
}
