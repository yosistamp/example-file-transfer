# Full Stack File Upload System with Event-Driven Processing

This project implements a secure, full-stack file upload system using a combination of AWS services, orchestrated with Terraform and AWS SAM. It features a static frontend hosted on S3/CloudFront and a serverless backend. Users can upload files via a web interface, which are then stored in S3, with metadata recorded in DynamoDB. A subsequent processing workflow is triggered asynchronously using DynamoDB Streams, EventBridge Pipes, and Step Functions.

## Architecture

The system is composed of two main parts: the core infrastructure managed by Terraform, and the serverless application managed by AWS SAM.

### Data Flow

1.  A user navigates to the **CloudFront URL**, which serves the static frontend application from an **S3 Bucket**.
2.  The user authenticates with **Amazon Cognito** (outside the app, using AWS CLI) to get a JWT token.
3.  The user pastes the JWT token into the web UI, selects a file, adds a comment, and clicks "Upload".
4.  The frontend JavaScript sends a `POST` request to an **API Gateway** endpoint (`/upload`).
5.  The **Cognito Authorizer** validates the token.
6.  API Gateway invokes the **File Upload Lambda** function.
7.  The Lambda function decodes the file, saves it to a dedicated **S3 Storage Bucket**, and registers metadata in a **DynamoDB Table**.
8.  The `INSERT` event in DynamoDB creates a record in its **DynamoDB Stream**.
9.  An **EventBridge Pipe** polls the stream and invokes a **Step Functions** state machine.
10. The Step Functions workflow invokes a **Processing Lambda** for downstream tasks.

### Technology Stack

*   **Frontend:**
    *   **HTML, CSS, JavaScript:** A simple, static single-page application.
    *   **Amazon S3:** For static website hosting.
    *   **Amazon CloudFront:** To provide secure, low-latency content delivery.
*   **Infrastructure as Code:**
    *   **Terraform:** For core infrastructure (S3, DynamoDB, Cognito, ECR, CloudFront, etc.).
    *   **AWS SAM:** For the serverless application (API Gateway, Lambda Functions).
*   **Backend & Compute:**
    *   **AWS Lambda:** Two Python functions running in containers.
    *   **FastAPI:** A modern Python web framework for the upload API.
*   **Storage & Database:**
    *   **Amazon S3:** For durable file storage (separate from the frontend bucket).
    *   **Amazon DynamoDB:** For storing file metadata.
*   **Authentication & Authorization:**
    *   **Amazon Cognito:** For user authentication and API authorization.
*   **Integration & Orchestration:**
    *   **Amazon API Gateway (HTTP API):** To expose the REST endpoint.
    *   **Amazon DynamoDB Streams, EventBridge Pipes, Step Functions**.
*   **CI/CD:**
    *   **GitHub Actions:** For automated code quality checks and full-stack deployment.

---

## Deployment Instructions

### Prerequisites

*   AWS Account & AWS CLI configured
*   Terraform CLI
*   AWS SAM CLI
*   Docker
*   A GitHub repository with this code.

### Step 1: Deploy Core Infrastructure with Terraform

1.  Navigate to `infra/`, initialize (`terraform init`), and deploy (`terraform apply`).
2.  After deployment, retrieve the necessary values for the next step:
    ```sh
    terraform output
    ```

### Step 2: Configure GitHub Secrets for CD

The CD workflow requires several secrets to be set in your GitHub repository's settings (`Settings > Secrets and variables > Actions`).

1.  Create an IAM Role in AWS that GitHub Actions can assume. It needs permissions to deploy SAM applications, sync to S3, and create CloudFront invalidations. The trust policy must allow the GitHub OIDC provider.
2.  Add the following repository secrets using the values from the `terraform output`:
    *   `AWS_ROLE_TO_ASSUME`: The ARN of the IAM role for deployment.
    *   `AWS_REGION`: The AWS region where you deployed the resources (e.g., `ap-northeast-1`).
    *   `PROJECT_NAME`: The project name (default: `s3-dynamo-pipe-app`).
    *   `S3_BUCKET_NAME`: The `s3_bucket_name` value.
    *   `DYNAMODB_TABLE_NAME`: The `dynamodb_table_name` value.
    *   `COGNITO_USER_POOL_ID`: The `cognito_user_pool_id` value.
    *   `COGNITO_APP_CLIENT_ID`: The `cognito_app_client_id` value.
    *   `STATE_MACHINE_ARN`: The `sfn_state_machine_arn` value.
    *   `FRONTEND_S3_BUCKET_NAME`: The `frontend_s3_bucket_name` value.
    *   `FRONTEND_CLOUDFRONT_ID`: The `frontend_cloudfront_distribution_id` value.

### Step 3: Deploy via CI/CD

Pushing your code to the `main` branch will automatically trigger the GitHub Actions workflow. It will deploy the SAM backend, then deploy the frontend files to S3 and invalidate the CloudFront cache.

---

## How to Use the Application

### 1. Create and Authenticate a User

1.  **Create a user:** Create a user manually in your Cognito User Pool in the AWS Console.
2.  **Authenticate via AWS CLI:** Use the AWS CLI to sign in and get an **IdToken**. (See previous `README` versions for the exact `aws cognito-idp` commands if needed).

### 2. Upload a File

1.  **Get the Frontend URL:** Find the `frontend_cloudfront_domain_name` from the Terraform output.
2.  **Open the URL in your browser:** Navigate to `https://<your_cloudfront_domain_name>`.
3.  **Authorize:** Paste the `IdToken` you obtained from Cognito into the "Step 1: Authentication" text area.
4.  **Upload:** Choose a file, add an optional comment, and click the "Upload" button.

The status of the upload will be displayed on the page. You can check your S3 bucket and DynamoDB table to verify the results. The processing Lambda's logs in CloudWatch will show the event being processed moments later.