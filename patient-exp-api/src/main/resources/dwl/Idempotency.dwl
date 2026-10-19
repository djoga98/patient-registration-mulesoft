%dw 2.0
import hashWith from dw::Crypto
import toHex from dw::core::Binaries

/**
 * Idempotency-Key handling for POST /api/patients (see idempotency.xml).
 *
 * Each key has one Object Store entry:
 *   IN_PROGRESS  { state, requestHash, startedAtMillis } while the first request runs
 *   COMPLETED    { state, requestHash, status, location, body, completedAtMillis }
 * requestHash ties the key to one request body, so a key reused for a different
 * registration is rejected instead of replaying someone else's response.
 */

/** The value with every object's keys sorted, recursively: the same JSON in any key order. */
fun canonical(value: Any): Any = value match {
    case obj is Object -> (obj orderBy $$) mapObject ((v, k) -> { (k): canonical(v) })
    case arr is Array -> arr map canonical($)
    else -> value
}

/** SHA-256 (hex) of the canonical JSON of a request body. */
fun fingerprint(body: Any): String =
    lower(toHex(hashWith(write(canonical(body), "application/json", { indent: false }) as Binary { encoding: "UTF-8" }, "SHA-256")))

fun epochMillis(instant: DateTime): Number =
    instant as Number { unit: "milliseconds" }

fun inProgressEntry(requestHash: String, instant: DateTime): Object = {
    state: "IN_PROGRESS",
    requestHash: requestHash,
    startedAtMillis: epochMillis(instant)
}

/** The response to replay for later requests with the same key. The body is kept as JSON text. */
fun completedEntry(requestHash: String, status: Number, location: String, body: Any, instant: DateTime): Object = {
    state: "COMPLETED",
    requestHash: requestHash,
    status: status,
    location: location,
    body: write(body, "application/json", { indent: false }) as String,
    completedAtMillis: epochMillis(instant)
}

/**
 * What to do with a request whose key is already stored:
 *   REPLAY       same body, first request completed: answer with the stored response
 *   MISMATCH     the key was used for a different body (422)
 *   IN_PROGRESS  same body, first request still running (409)
 *   CLAIM        the entry is gone (expired) or abandoned (IN_PROGRESS older than
 *                staleAfterMillis, e.g. the first request's runtime crashed): process
 */
fun decide(entry: Object, requestHash: String, instant: DateTime, staleAfterMillis: Number): String =
    if (entry.state != "IN_PROGRESS" and entry.state != "COMPLETED") "CLAIM"
    else if (entry.requestHash != requestHash) "MISMATCH"
    else if (entry.state == "COMPLETED") "REPLAY"
    else if (epochMillis(instant) - (entry.startedAtMillis default 0) > staleAfterMillis) "CLAIM"
    else "IN_PROGRESS"
