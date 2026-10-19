%dw 2.0
/**
 * Structured application log events, identical in the three patient APIs.
 *
 * Every application log message is one single-line JSON object: an event name, the
 * correlation ID and a few non-personal fields (method, path, status, codes,
 * durations). The message itself is structured, not only the log4j2 layout,
 * because CloudHub 2.0 replaces file appenders and their layouts with its own
 * collector; the message is what reaches Runtime Manager unchanged.
 *
 * Never pass payloads or patient fields: only identifiers and technical values.
 */

/**
 * The log message for one event, on one line. Fields follow the event and
 * correlationId keys. "as String" makes it plain text for the logger; a value still
 * typed application/json would be serialised a second time (quoted and escaped).
 */
fun event(name: String, correlationId: String | Null, fields: Object = {}): String =
    write({ event: name, correlationId: correlationId } ++ fields, "application/json", { indent: false }) as String

/** Milliseconds elapsed since a start time taken with now() as Number { unit: "milliseconds" }. */
fun elapsedMillis(startMillis: Number | Null): Number =
    (now() as Number { unit: "milliseconds" }) - (startMillis default 0)
