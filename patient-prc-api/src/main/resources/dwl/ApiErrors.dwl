%dw 2.0
/**
 * Error catalogue. The three patient APIs carry an identical copy, so every
 * layer answers with the same code, status and message for the same problem.
 * Messages are fixed strings: no exception text, SQL or host names ever reach
 * a response.
 */

var catalogue = {
    BAD_REQUEST:            { status: 400, message: "The request does not match the API specification." },
    RESOURCE_NOT_FOUND:     { status: 404, message: "The requested resource does not exist." },
    METHOD_NOT_ALLOWED:     { status: 405, message: "The HTTP method is not supported for this resource." },
    NOT_ACCEPTABLE:         { status: 406, message: "The requested response media type is not supported." },
    UNSUPPORTED_MEDIA_TYPE: { status: 415, message: "The request media type is not supported." },
    PATIENT_NOT_FOUND:      { status: 404, message: "No patient exists with the given patient ID." },
    DUPLICATE_PATIENT:      { status: 409, message: "A patient with the same name and date of birth already exists." },
    INVALID_BIRTH_DATE:     { status: 422, message: "Date of birth must not be in the future." },
    CONSENT_REQUIRED:       { status: 422, message: "Consent to data processing is required for registration." },
    INTERNAL_ERROR:         { status: 500, message: "An unexpected error occurred." },
    NOT_IMPLEMENTED:        { status: 501, message: "The operation is not implemented." },
    DOWNSTREAM_ERROR:       { status: 502, message: "A downstream service is unavailable or did not respond in time." }
}

/**
 * Mule error types with a fixed meaning. Errors raised by the application use
 * the APP namespace with the catalogue code as identifier (APP:DUPLICATE_PATIENT).
 * Anything not listed is unexpected and becomes INTERNAL_ERROR.
 */
var codesByErrorType = {
    "APIKIT:BAD_REQUEST":            "BAD_REQUEST",
    "APIKIT:NOT_FOUND":              "RESOURCE_NOT_FOUND",
    "APIKIT:METHOD_NOT_ALLOWED":     "METHOD_NOT_ALLOWED",
    "APIKIT:NOT_ACCEPTABLE":         "NOT_ACCEPTABLE",
    "APIKIT:UNSUPPORTED_MEDIA_TYPE": "UNSUPPORTED_MEDIA_TYPE",
    "APIKIT:NOT_IMPLEMENTED":        "NOT_IMPLEMENTED",
    "HTTP:CONNECTIVITY":             "DOWNSTREAM_ERROR",
    "HTTP:TIMEOUT":                  "DOWNSTREAM_ERROR",
    "HTTP:SERVICE_UNAVAILABLE":      "DOWNSTREAM_ERROR",
    "MULE:RETRY_EXHAUSTED":          "DOWNSTREAM_ERROR",
    "DB:CONNECTIVITY":               "DOWNSTREAM_ERROR"
}

fun qualifiedName(errorType): String =
    "$(errorType.namespace default ""):$(errorType.identifier default "")"

fun codeFor(errorType): String =
    if (errorType.namespace == "APP" and catalogue[errorType.identifier] != null)
        errorType.identifier
    else
        codesByErrorType[qualifiedName(errorType)] default "INTERNAL_ERROR"

fun statusFor(code: String): Number =
    (catalogue[code] default catalogue.INTERNAL_ERROR).status

fun utcTimestamp(instant: DateTime): String =
    (instant >> "UTC") as String { format: "uuuu-MM-dd'T'HH:mm:ss'Z'" }

fun errorBody(code: String, correlationId: String, instant: DateTime): Object = {
    error: {
        code: code,
        message: (catalogue[code] default catalogue.INTERNAL_ERROR).message,
        correlationId: correlationId,
        timestamp: utcTimestamp(instant)
    }
}
