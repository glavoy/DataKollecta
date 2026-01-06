# Survey System Migration: FTP to Supabase (HTTP)

This document outlines the transition from a folder-based discovery method (FTP) to a secure, link-based retrieval method (HTTP).

---

## 1. The List (Discovery)
*How the application identifies available surveys.*

| Feature | Old Method (FTP) | New Method (Supabase) |
| :--- | :--- | :--- |
| **Action** | Log in and query folder contents. | Authenticate and receive an API response. |
| **Process** | Asks: "What files are in this folder?" | Receives a structured **JSON** text response. |
| **Result** | A list of raw filenames (e.g., `survey1.zip`). | Metadata containing survey names and secure URLs. |

### Example JSON Response
```json
"surveys": [
  {
    "name": "Malaria Survey 2024",
    "download_url": "[https://api.supabase.com/storage/v1/object/sign/surveys/r21/survey1.zip?token=abc](https://api.supabase.com/storage/v1/object/sign/surveys/r21/survey1.zip?token=abc)..."
  }
]
```

---

## 2. The Download (Retrieval)
*How the data is transferred to the device.*

* **Old Method (FTP):** The application issued a manual `Get File` command for a specific filename (e.g., `survey1.zip`).
* **New Method (Supabase):** The application utilizes the `download_url` provided in the JSON response. This link is a **Signed URL** that includes a secret access token. The app performs a standard **HTTP GET request**, identical to a web browser downloading a file.

---

## Summary
> The "List" of available files is now integrated into the **login response validation**, and the "Download" process utilizes **specific secure links** provided dynamically in that response.