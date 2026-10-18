%dw 2.0
/**
 * Registration business rules. "Today" is the calendar date in the clinic's
 * time zone (clinic.timeZone), so a birth registered just after midnight local
 * time is not rejected because UTC is still on the previous day.
 */

fun todayIn(timeZone: String): Date =
    (now() >> timeZone) as Date

/** Rule INVALID_BIRTH_DATE: a date of birth may be today but not later. */
fun isBornInFuture(dateOfBirth: String, today: Date): Boolean =
    (dateOfBirth as Date) > today

/** Rule CONSENT_REQUIRED: only an explicit true counts as consent (the spec guarantees a boolean). */
fun hasDataProcessingConsent(registration: Object): Boolean =
    registration.consents.dataProcessing default false

/**
 * Completed years of age on a given day. The birthday counts once its month and
 * day are reached, so someone born on 29 February turns a year older on
 * 1 March in non-leap years (same result as java.time.Period).
 */
fun ageOn(birthDate: Date, day: Date): Number = do {
    var birthdayReached = (day.month > birthDate.month)
        or (day.month == birthDate.month and day.day >= birthDate.day)
    ---
    (day.year - birthDate.year) - (if (birthdayReached) 0 else 1)
}

/** Under 18 MINOR, 18 to 64 ADULT, 65 and over SENIOR. */
fun categoryFor(age: Number): String =
    if (age < 18) "MINOR"
    else if (age < 65) "ADULT"
    else "SENIOR"
