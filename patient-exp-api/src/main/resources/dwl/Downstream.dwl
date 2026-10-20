%dw 2.0
/**
 * Interprets a lower API's HTTP response, so errors keep their meaning on the
 * way up: a 404/409/422/400 carrying one of the shared error codes becomes the
 * same code here; anything else unsuccessful is a DOWNSTREAM_ERROR (502).
 * Identical in patient-prc-api and patient-exp-api.
 */

var propagatedCodes = {
    "400": [ "BAD_REQUEST" ],
    "404": [ "PATIENT_NOT_FOUND" ],
    "409": [ "DUPLICATE_PATIENT" ],
    "422": [ "INVALID_BIRTH_DATE", "CONSENT_REQUIRED" ]
}

/** The error.code of a standard error body, or null for any other body (HTML, text, empty). */
fun bodyErrorCode(body: Any): String | Null =
    if (body is Object and body.error is Object and body.error.code is String) body.error.code
    else null

/** null when the status is 2xx; otherwise the catalogue code to answer with. */
fun errorCodeFor(statusCode: Number, body: Any): String | Null = do {
    var code = bodyErrorCode(body)
    ---
    if (statusCode >= 200 and statusCode < 300) null
    else if ((propagatedCodes[statusCode as String] default []) contains code) code
    else "DOWNSTREAM_ERROR"
}

/**
 * client_id / client_secret headers for the lower API's Client ID Enforcement policy
 * (API Manager). None when no client ID is configured: locally and in environments
 * where the lower API is not managed.
 */
fun clientCredentialHeaders(clientId: String | Null, clientSecret: String | Null): Object =
    if (isBlank(clientId)) {} else { client_id: clientId, client_secret: clientSecret default "" }
