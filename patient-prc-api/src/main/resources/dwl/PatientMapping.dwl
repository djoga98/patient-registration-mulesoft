%dw 2.0
import ageOn, categoryFor from dwl::RegistrationRules

/**
 * Mapping between the portal field names (this API's contract) and the record
 * format of the Patient System API, in both directions.
 */

var sexByGender = { female: "F", male: "M", other: "O" }
var genderBySex = { F: "female", M: "male", O: "other" }

/**
 * Trims leading/trailing whitespace, including Unicode separators such as the
 * no-break space that String.trim() leaves in place.
 */
fun trimUnicode(text: String): String =
    text replace /^[\s\p{Z}]+|[\s\p{Z}]+$/ with ""

/** Trim; first letter upper case, the rest lower case ("  ana " -> "Ana", "KOVAČ" -> "Kovač"). */
fun normaliseName(name: String): String = do {
    var trimmed = trimUnicode(name)
    ---
    if (sizeOf(trimmed) <= 1) upper(trimmed)
    else upper(trimmed[0]) ++ lower(trimmed[1 to -1])
}

fun normaliseEmail(email: String): String =
    lower(trimUnicode(email))

/** Removes spaces, dashes and brackets. Absent, null or blank phones give null. */
fun normalisePhone(phone: String | Null): String | Null = do {
    var compact = if (phone == null) "" else (phone replace /[\s\p{Z}\-()\[\]]/ with "")
    ---
    if (isEmpty(compact)) null else compact
}

/** Portal registration -> System API record. A missing phone is left out, not sent as null. */
fun toRecord(registration: Object, today: Date): Object = do {
    var phone = normalisePhone(registration.contact.phone)
    ---
    {
        given_name: normaliseName(registration.firstName),
        family_name: normaliseName(registration.lastName),
        birth_date: registration.dateOfBirth as String,
        sex: sexByGender[registration.gender],
        category: categoryFor(ageOn(registration.dateOfBirth as Date, today)),
        email: normaliseEmail(registration.contact.email),
        (phone: phone) if (phone != null),
        consent_data_processing: registration.consents.dataProcessing,
        consent_sms: registration.consents.smsReminders default false,
        source: registration.channel
    }
}

/** System API record -> portal field names (Process API response). */
fun toPatient(record: Object): Object = {
    patientId: record.patient_id,
    firstName: record.given_name,
    lastName: record.family_name,
    dateOfBirth: record.birth_date,
    gender: genderBySex[record.sex],
    category: record.category,
    contact: {
        email: record.email,
        (phone: record.phone) if (record.phone != null)
    },
    consents: {
        dataProcessing: record.consent_data_processing,
        smsReminders: record.consent_sms
    },
    status: record.status,
    registeredAt: record.registered_at
}
