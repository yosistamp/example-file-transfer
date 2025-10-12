import datetime
import os
import logging
from typing import Optional, Callable, Awaitable

import boto3
from fastapi import FastAPI, Request, HTTPException, UploadFile, File, Form
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response


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
STAGE = "prod"
if not S3_BUCKET_NAME or not DYNAMODB_TABLE_NAME:
    raise RuntimeError("S3_BUCKET_NAME and DYNAMODB_TABLE_NAME must be set")

table = dynamodb.Table(DYNAMODB_TABLE_NAME)


# Logging Middleware
class CustomLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: Callable[[Request], Awaitable[Response]]) -> Response:
        log_data = {
            "method": request.method,
            "url": str(request.url),
            "headers": dict(request.headers),
        }

        content_type = request.headers.get("content-type", "")
        if request.method == "POST":
            try:
                if "application/json" in content_type:
                    log_data["body"] = await request.json()
                elif "multipart/form-data" in content_type:
                    form = await request.form()
                    log_data["form"] = {}
                    for key, value in form.items():
                        if hasattr(value, "filename"):
                            log_data["form"][key] = {
                                "filename": value.filename,
                                "content_type": value.content_type,
                                "size": len(await value.read())
                            }
                        else:
                            log_data["form"][key] = value
            except Exception as e:
                log_data["error"] = f"Failed to parse body: {e}"

        logger.info(log_data)
        response = await call_next(request)
        return response


# Middleware registration
app.add_middleware(CustomLoggingMiddleware)

# -----------------------------------------------------------------------------
# API Endpoint for File Upload
# -----------------------------------------------------------------------------
@app.post("/{}/upload".format(STAGE))
async def upload_file(
    request: Request,
    file: UploadFile = File(...),
    comment: Optional[str] = Form(None),
):
    """
    Handles file upload using multipart/form-data, saves file to S3,
    and records metadata in DynamoDB.
    """
    try:
        claims = request.scope.get("aws.event", {}).get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
        user_id = claims.get("sub")
        if not user_id:
            raise HTTPException(status_code=403, detail="User ID not found in token claims.")
    except Exception:
        raise HTTPException(status_code=403, detail="Could not validate user from token.")

    file_content = await file.read()
    if not file_content:
        raise HTTPException(status_code=400, detail="File content is empty.")

    current_time = datetime.datetime.now().strftime("%Y%m%d%H%M%S%f")[:-3]
    # Use the original filename from the upload
    file_path = os.path.join(
        DESTINATION_SYSTEM_ID, user_id, current_time, file.filename
    )

    # --- 1. Upload to S3 ---
    try:
        s3_client.put_object(Bucket=S3_BUCKET_NAME, Key=file_path, Body=file_content)
    except Exception as e:
        logging.error(f"S3 upload failed: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to upload file to S3: {e}")

    # --- 2. Register metadata in DynamoDB ---
    try:
        item_to_register = {
            "FilePath": file_path,
            "UserID": user_id,
            "Comment": comment or "",
            "RegistrationDate": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "DownloadCount": 0,
            "DestinationSystemID": DESTINATION_SYSTEM_ID,
            "IsDeleted": False,
        }
        table.put_item(Item=item_to_register)
    except Exception as e:
        logging.error(f"DynamoDB put_item failed: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to register metadata in DynamoDB: {e}")

    return {"message": "File uploaded successfully.", "s3_path": file_path}


# -----------------------------------------------------------------------------
# Health Check Endpoint
# -----------------------------------------------------------------------------
@app.get("/{}/health".format(STAGE))
async def health_check():
    """
    A simple health check endpoint.
    """
    return {"status": "ok"}
