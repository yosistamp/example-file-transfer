import base64
import datetime
import os
from typing import Optional

import boto3
from fastapi import FastAPI, Request, HTTPException
from pydantic import BaseModel, Field

# -----------------------------------------------------------------------------
# FastAPI Application and AWS Clients
# -----------------------------------------------------------------------------
app = FastAPI()
s3_client = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

# -----------------------------------------------------------------------------
# Environment Variables
# -----------------------------------------------------------------------------
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME")
DYNAMODB_TABLE_NAME = os.environ.get("DYNAMODB_TABLE_NAME")
DESTINATION_SYSTEM_ID = os.environ.get("DESTINATION_SYSTEM_ID", "A01")

if not S3_BUCKET_NAME or not DYNAMODB_TABLE_NAME:
    raise RuntimeError("S3_BUCKET_NAME and DYNAMODB_TABLE_NAME must be set")

table = dynamodb.Table(DYNAMODB_TABLE_NAME)


# -----------------------------------------------------------------------------
# Pydantic Models for Request Body
# -----------------------------------------------------------------------------
class FileUploadRequest(BaseModel):
    file_name: str = Field(..., description="The name of the file.")
    comment: Optional[str] = Field(
        None, description="A comment about the file."
    )
    file_data: str = Field(..., description="Base64-encoded file content.")


# -----------------------------------------------------------------------------
# API Endpoint for File Upload
# -----------------------------------------------------------------------------
@app.post("/upload")
async def upload_file(request_data: FileUploadRequest, request: Request):
    """
    Handles file upload, saves file to S3, and records metadata in DynamoDB.
    The user ID is extracted from the Cognito authorizer context.
    """
    try:
        # Extract user ID (sub) from the Cognito authorizer claims
        aws_event = request.scope.get("aws.event", {})
        request_context = aws_event.get("requestContext", {})
        authorizer = request_context.get("authorizer", {})
        jwt_claims = authorizer.get("jwt", {}).get("claims", {})
        user_id = jwt_claims.get("sub")

        if not user_id:
            raise HTTPException(
                status_code=403, detail="User ID not found in token claims."
            )
    except Exception:
        raise HTTPException(
            status_code=403, detail="Could not validate user from token."
        )

    try:
        file_content = base64.b64decode(request_data.file_data)
    except (base64.binascii.Error, TypeError) as e:
        raise HTTPException(
            status_code=400, detail=f"Invalid Base64 data: {e}"
        )

    current_time = datetime.datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3]
    file_path = os.path.join(
        DESTINATION_SYSTEM_ID, user_id, current_time, request_data.file_name
    )

    # --- 1. Upload to S3 ---
    try:
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME, Key=file_path, Body=file_content
        )
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to upload file to S3: {e}"
        )

    # --- 2. Register metadata in DynamoDB ---
    try:
        item_to_register = {
            "FilePath": file_path,
            "UserID": user_id,
            "Comment": request_data.comment or "",
            "RegistrationDate": datetime.datetime.now(
                datetime.timezone.utc
            ).isoformat(),
            "DownloadCount": 0,
            "DestinationSystemID": DESTINATION_SYSTEM_ID,
            "IsDeleted": False,
        }
        table.put_item(Item=item_to_register)
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to register metadata in DynamoDB: {e}"
        )

    return {"message": "File uploaded successfully.", "s3_path": file_path}


# -----------------------------------------------------------------------------
# Health Check Endpoint
# -----------------------------------------------------------------------------
@app.get("/health")
async def health_check():
    """
    A simple health check endpoint.
    """
    return {"status": "ok"}