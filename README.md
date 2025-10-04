# S3/DynamoDB File Upload System with Event-Driven Processing

This project implements a secure file upload system using a combination of AWS services, orchestrated with Terraform and AWS SAM. Users can upload files via a REST API, which are then stored in S3, with metadata recorded in DynamoDB. A subsequent processing workflow is triggered asynchronously using DynamoDB Streams, EventBridge Pipes, and Step Functions.

## Architecture

The system is composed of two main parts: the core infrastructure managed by Terraform, and the serverless application managed by AWS SAM.

### Data Flow

1.  A client authenticates with **Amazon Cognito** to get a JWT token.
2.  The client sends a `POST` request to an **API Gateway** endpoint (`/upload`) with the JWT token and a JSON payload containing file data (Base64-encoded).
3.  The **Cognito Authorizer** validates the token.
4.  API Gateway invokes the **File Upload Lambda** function.
5.  The Lambda function decodes the file, saves it to an **S3 Bucket**, and registers metadata (file path, user ID, etc.) in a **DynamoDB Table**.
6.  The `INSERT` event in DynamoDB creates a record in its **DynamoDB Stream**.
7.  An **EventBridge Pipe** polls the stream for new records.
8.  The Pipe filters for `INSERT` events and invokes a **Step Functions** state machine.
9.  The Step Functions workflow invokes a second **Processing Lambda** function with the event data for downstream tasks.

### Technology Stack

*   **Infrastructure as Code:**
    *   **Terraform:** For core infrastructure (S3, DynamoDB, Cognito, ECR, Pipes, SFN, IAM Roles).
    *   **AWS SAM:** For the serverless application (API Gateway, Lambda Functions).
*   **Compute:**
    *   **AWS Lambda:** Two Python functions running in containers.
    *   **Lambda Web Adapter:** To run a FastAPI application on Lambda.
*   **Application Backend:**
    *   **FastAPI:** A modern, fast Python web framework for the upload API.
*   **Storage & Database:**
    *   **Amazon S3:** For durable file storage.
    *   **Amazon DynamoDB:** For storing file metadata.
*   **Authentication & Authorization:**
    *   **Amazon Cognito:** For user authentication and API authorization.
*   **Integration & Orchestration:**
    *   **Amazon API Gateway (HTTP API):** To expose the REST endpoint.
    *   **Amazon DynamoDB Streams:** To capture data modification events.
    *   **Amazon EventBridge Pipes:** To connect the stream to the workflow.
    *   **AWS Step Functions:** To orchestrate the post-upload processing.
*   **CI/CD:**
    *   **GitHub Actions:** For automated code quality checks and deployment.

---

## Deployment Instructions

### Prerequisites

*   AWS Account & AWS CLI configured
*   Terraform CLI
*   AWS SAM CLI
*   Docker
*   A GitHub repository with this code.

### Step 1: Deploy Core Infrastructure with Terraform

1.  **Navigate to the infrastructure directory:**
    ```sh
    cd infra
    ```

2.  **Initialize Terraform:**
    ```sh
    terraform init
    ```

3.  **Deploy the resources:**
    Review the plan and apply it.
    ```sh
    terraform apply
    ```
    Enter `yes` when prompted.

4.  **Get the outputs:**
    After the deployment is complete, Terraform will output several values. These are needed for the next step. You can also retrieve them anytime with:
    ```sh
    terraform output
    ```
    You will get values for `s3_bucket_name`, `dynamodb_table_name`, `cognito_user_pool_id`, and `cognito_app_client_id`.

### Step 2: Configure GitHub Secrets for CD

The CD workflow (`.github/workflows/cd.yml`) requires several secrets to be set in your GitHub repository's settings.

1.  Go to `Settings > Secrets and variables > Actions` in your GitHub repo.
2.  Create an IAM Role in your AWS account that GitHub Actions can assume. It needs permissions to deploy SAM applications (e.g., `AdministratorAccess` for simplicity, but a more restricted policy is recommended for production). The trust policy should allow the GitHub OIDC provider.
3.  Add the following repository secrets:
    *   `AWS_ROLE_TO_ASSUME`: The ARN of the IAM role you created for deployment. This role needs permissions to deploy SAM applications and also the `states:UpdateStateMachine` permission.
    *   `AWS_REGION`: The AWS region where you deployed the resources (e.g., `ap-northeast-1`).
    *   `PROJECT_NAME`: The project name used in `variables.tf` (default: `s3-dynamo-pipe-app`).
    *   `S3_BUCKET_NAME`: The `s3_bucket_name` value from the Terraform output.
    *   `DYNAMODB_TABLE_NAME`: The `dynamodb_table_name` value from the Terraform output.
    *   `COGNITO_USER_POOL_ID`: The `cognito_user_pool_id` value from the Terraform output.
    *   `COGNITO_APP_CLIENT_ID`: The `cognito_app_client_id` value from the Terraform output.
    *   `STATE_MACHINE_ARN`: The `sfn_state_machine_arn` value from the Terraform output.

### Step 3: Deploy the SAM Application via CI/CD

Pushing your code to the `main` branch will automatically trigger the GitHub Actions workflow.

1.  Commit and push all the code to your `main` branch.
    ```sh
    git add .
    git commit -m "Initial project setup"
    git push origin main
    ```
2.  Go to the "Actions" tab in your GitHub repository to monitor the `Deploy SAM Application` workflow. It will build the container images, push them to ECR, and deploy the SAM stack.

---

## How to Use the API

### 1. Create and Authenticate a User

1.  **Create a user:** Since user registration is not enabled in the app, create a user manually in the AWS Console. Go to your Cognito User Pool, and under the "Users" tab, create a new user. Make sure to set a temporary password.
2.  **Confirm the user:** When you first sign in, you will be required to change the password. Use the AWS CLI to do this.
    ```sh
    aws cognito-idp admin-initiate-auth \
      --user-pool-id <YOUR_COGNITO_USER_POOL_ID> \
      --client-id <YOUR_COGNITO_APP_CLIENT_ID> \
      --auth-flow ADMIN_USER_PASSWORD_AUTH \
      --auth-parameters USERNAME=<username>,PASSWORD=<temporary_password>
    ```
    You will receive a `ChallengeName: 'NEW_PASSWORD_REQUIRED'`.

3.  **Set the final password:**
    ```sh
    aws cognito-idp admin-respond-to-auth-challenge \
      --user-pool-id <YOUR_COGNITO_USER_POOL_ID> \
      --client-id <YOUR_COGNITO_APP_CLIENT_ID> \
      --challenge-name NEW_PASSWORD_REQUIRED \
      --challenge-responses USERNAME=<username>,NEW_PASSWORD=<your_new_strong_password> \
      --session <session_from_previous_command>
    ```
    This command will return an `IdToken`.

### 2. Upload a File

Use the `IdToken` from the previous step to call the `/upload` endpoint.

1.  **Encode a file in Base64:**
    On macOS or Linux:
    ```sh
    BASE64_CONTENT=$(base64 -i my-test-file.txt)
    ```

2.  **Send the request:**
    Replace the placeholders with your actual values.
    ```sh
    API_ENDPOINT=$(aws cloudformation describe-stacks --stack-name s3-dynamo-pipe-app-sam-app --query "Stacks[0].Outputs[?OutputKey=='ApiEndpoint'].OutputValue" --output text)
    ID_TOKEN="..." # Paste the IdToken here

    curl -X POST "${API_ENDPOINT}/upload" \
      -H "Authorization: ${ID_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{
        "file_name": "my-test-file.txt",
        "comment": "This is a test file.",
        "file_data": "'"${BASE64_CONTENT}"'"
      }'
    ```

If successful, you will receive a `{"message":"File uploaded successfully.","s3_path":"..."}` response. You can then check your S3 bucket and DynamoDB table to verify the results. The processing Lambda's logs in CloudWatch will show the event being processed.