%dw 2.0
/**
 * Moves patient records between the JSON record contract and the patient
 * table. Formatting only; business rules belong to the Process API.
 */

/** Named parameters for the INSERT. An absent phone binds SQL NULL. */
fun toInsertParameters(record: Object): Object = {
    given_name: record.given_name,
    family_name: record.family_name,
    birth_date: record.birth_date as String,
    sex: record.sex,
    category: record.category,
    email: record.email,
    phone: record.phone,
    consent_data_processing: record.consent_data_processing,
    consent_sms: record.consent_sms,
    source: record.source
}

/**
 * Seconds since the epoch to an RFC 3339 UTC timestamp. The SELECT returns the
 * epoch rather than a JDBC timestamp so no JVM time zone is ever involved.
 */
fun epochToUtc(epochSeconds: Number): String =
    ((epochSeconds as DateTime) >> "UTC") as String { format: "uuuu-MM-dd'T'HH:mm:ss'Z'" }

/** A row selected by find-patient-by-id to the record contract. NULL phone is omitted. */
fun fromRow(row: Object): Object = {
    patient_id: row.patient_id,
    given_name: row.given_name,
    family_name: row.family_name,
    birth_date: row.birth_date,
    sex: row.sex,
    category: row.category,
    email: row.email,
    (phone: row.phone) if (row.phone != null),
    consent_data_processing: row.consent_data_processing,
    consent_sms: row.consent_sms,
    source: row.source,
    status: row.status,
    registered_at: epochToUtc(row.registered_epoch)
}
