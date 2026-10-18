%dw 2.0
/**
 * Shapes data for the patient portal. Presentation only: validation and
 * business rules belong to the Process API.
 */

/** The portal request is forwarded unchanged, with the channel set to PORTAL. */
fun toProcessRegistration(portalRequest: Object): Object =
    (portalRequest - "channel") ++ { channel: "PORTAL" }

/** Calendar date in the clinic's time zone, the "day of the request" for the age. */
fun todayIn(timeZone: String): Date =
    (now() >> timeZone) as Date

/** Completed years on a given day; a birthday counts once its month and day are reached. */
fun ageOn(birthDate: Date, day: Date): Number = do {
    var birthdayReached = (day.month > birthDate.month)
        or (day.month == birthDate.month and day.day >= birthDate.day)
    ---
    (day.year - birthDate.year) - (if (birthdayReached) 0 else 1)
}

/** Process API patient -> flat portal view. A missing phone stays missing. */
fun toPortalPatient(patient: Object, today: Date): Object = {
    patientId: patient.patientId,
    fullName: "$(patient.firstName) $(patient.lastName)",
    age: ageOn(patient.dateOfBirth as Date, today),
    category: patient.category,
    email: patient.contact.email,
    (phone: patient.contact.phone) if (patient.contact.phone != null),
    status: patient.status,
    registeredAt: patient.registeredAt
}
