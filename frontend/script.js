document.addEventListener('DOMContentLoaded', () => {
    const idTokenInput = document.getElementById('idToken');
    const fileInput = document.getElementById('fileInput');
    const commentInput = document.getElementById('commentInput');
    const uploadButton = document.getElementById('uploadButton');
    const statusDiv = document.getElementById('status');

    // !!! IMPORTANT !!!
    // Replace this placeholder with your actual API Gateway endpoint URL.
    const apiEndpoint = '<YOUR_API_GATEWAY_ENDPOINT>/upload';

    uploadButton.addEventListener('click', async () => {
        const idToken = idTokenInput.value.trim();
        const file = fileInput.files[0];
        const comment = commentInput.value.trim();

        // --- Basic Validation ---
        if (!idToken) {
            showStatus('error', 'Error: Cognito ID Token is required.');
            return;
        }
        if (!file) {
            showStatus('error', 'Error: Please select a file to upload.');
            return;
        }

        // --- Show loading state ---
        showStatus('success', 'Reading file...');
        uploadButton.disabled = true;
        uploadButton.textContent = 'Uploading...';

        // --- Read file as Base64 ---
        const reader = new FileReader();
        reader.readAsDataURL(file);
        reader.onload = async () => {
            // The result includes the data URL prefix (e.g., "data:text/plain;base64,"),
            // so we need to split it off to get only the Base64 content.
            const base64Content = reader.result.split(',')[1];

            const payload = {
                file_name: file.name,
                comment: comment,
                file_data: base64Content
            };

            try {
                showStatus('success', 'Sending data to the server...');

                const response = await fetch(apiEndpoint, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': idToken
                    },
                    body: JSON.stringify(payload)
                });

                const result = await response.json();

                if (!response.ok) {
                    // Handle HTTP errors (e.g., 4xx, 5xx)
                    const errorMessage = result.detail || `HTTP error! Status: ${response.status}`;
                    throw new Error(errorMessage);
                }

                showStatus('success', `Success! File uploaded successfully. S3 Path: ${result.s3_path}`);

            } catch (error) {
                console.error('Upload failed:', error);
                showStatus('error', `Upload failed: ${error.message}`);
            } finally {
                // --- Reset button state ---
                uploadButton.disabled = false;
                uploadButton.textContent = 'Upload';
            }
        };

        reader.onerror = (error) => {
            console.error('File reading error:', error);
            showStatus('error', 'Error: Could not read the selected file.');
            uploadButton.disabled = false;
            uploadButton.textContent = 'Upload';
        };
    });

    function showStatus(type, message) {
        statusDiv.className = type;
        statusDiv.textContent = message;
    }
});