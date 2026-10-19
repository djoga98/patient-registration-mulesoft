#!/usr/bin/env node
// Generates postman/patient-registration.postman_collection.json from the nine
// sample cases of the assignment. Kept as code so the request bodies stay byte-exact
// copies of the PDF and the test scripts stay reviewable.
//
//   node scripts/build-postman-collection.js
'use strict';
const fs = require('fs');
const path = require('path');

const cases = [
    {
        n: 1, method: 'POST', name: 'Ana Kovač (messy casing and phone) -> 201 ADULT',
        body: {
            firstName: ' ana ', lastName: 'KOVAČ', dateOfBirth: '1985-04-12', gender: 'female',
            contact: { email: 'Ana.Kovac@Example.com', phone: '+387 61 111-222' },
            consents: { dataProcessing: true, smsReminders: false }
        },
        tests: [
            "pm.test('201 Created', () => pm.response.to.have.status(201));",
            "const p = pm.response.json();",
            "pm.test('patientId is PAT- plus six digits', () => pm.expect(p.patientId).to.match(/^PAT-\\d{6}$/));",
            "pm.test('fullName normalised', () => pm.expect(p.fullName).to.eql('Ana Kovač'));",
            "pm.test('category ADULT', () => pm.expect(p.category).to.eql('ADULT'));",
            "pm.test('email lower case', () => pm.expect(p.email).to.eql('ana.kovac@example.com'));",
            "pm.test('phone compacted', () => pm.expect(p.phone).to.eql('+38761111222'));",
            "pm.test('status ACTIVE', () => pm.expect(p.status).to.eql('ACTIVE'));",
            "pm.test('age is completed years today', () => pm.expect(p.age).to.eql(ageOn('1985-04-12')));",
            "pm.test('registeredAt is UTC', () => pm.expect(p.registeredAt).to.match(/^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$/));",
            "pm.test('Location header points at the patient', () => pm.expect(pm.response.headers.get('Location')).to.eql('/api/patients/' + p.patientId));",
            "pm.test('only portal fields', () => pm.expect(Object.keys(p).sort()).to.eql(['age','category','email','fullName','patientId','phone','registeredAt','status']));",
            "pm.collectionVariables.set('case1PatientId', p.patientId);"
        ]
    },
    {
        n: 2, method: 'POST', name: 'Luka Petrović (no phone) -> 201 MINOR, no phone field',
        body: {
            firstName: 'Luka', lastName: 'Petrović', dateOfBirth: '2012-09-03', gender: 'male',
            contact: { email: 'luka.petrovic@example.com' },
            consents: { dataProcessing: true }
        },
        tests: [
            "pm.test('201 Created', () => pm.response.to.have.status(201));",
            "const p = pm.response.json();",
            "pm.test('category MINOR', () => pm.expect(p.category).to.eql('MINOR'));",
            "pm.test('no phone field', () => pm.expect(p).to.not.have.property('phone'));",
            "pm.test('fullName', () => pm.expect(p.fullName).to.eql('Luka Petrović'));"
        ]
    },
    {
        n: 3, method: 'POST', name: 'Milena Jović (SMS reminders on) -> 201 SENIOR, phone 065222333',
        body: {
            firstName: 'Milena', lastName: 'Jović', dateOfBirth: '1950-01-20', gender: 'female',
            contact: { email: 'milena.jovic@example.com', phone: '(065) 222 333' },
            consents: { dataProcessing: true, smsReminders: true }
        },
        tests: [
            "pm.test('201 Created', () => pm.response.to.have.status(201));",
            "const p = pm.response.json();",
            "pm.test('category SENIOR', () => pm.expect(p.category).to.eql('SENIOR'));",
            "pm.test('phone compacted', () => pm.expect(p.phone).to.eql('065222333'));"
        ]
    },
    {
        n: 4, method: 'POST', name: '\"ANA kovač\", same birth date as case 1 -> 409 DUPLICATE_PATIENT',
        body: {
            firstName: 'ANA', lastName: 'kovač', dateOfBirth: '1985-04-12', gender: 'female',
            contact: { email: 'ana.k@example.com' },
            consents: { dataProcessing: true }
        },
        tests: expectError(409, 'DUPLICATE_PATIENT')
    },
    {
        n: 5, method: 'POST', name: 'Ivan Marić (data-processing consent false) -> 422 CONSENT_REQUIRED',
        body: {
            firstName: 'Ivan', lastName: 'Marić', dateOfBirth: '1978-11-30', gender: 'male',
            contact: { email: 'ivan.maric@example.com' },
            consents: { dataProcessing: false }
        },
        tests: expectError(422, 'CONSENT_REQUIRED')
    },
    {
        n: 6, method: 'POST', name: 'Sara Ilić (birth date in the future) -> 422 INVALID_BIRTH_DATE',
        body: {
            firstName: 'Sara', lastName: 'Ilić', dateOfBirth: '2030-05-01', gender: 'female',
            contact: { email: 'sara.ilic@example.com' },
            consents: { dataProcessing: true }
        },
        tests: expectError(422, 'INVALID_BIRTH_DATE')
    },
    {
        n: 7, method: 'POST', name: 'No email and gender unknown -> 400 BAD_REQUEST',
        body: {
            firstName: 'Petar', lastName: 'Babić', dateOfBirth: '1992-06-15', gender: 'unknown',
            contact: { phone: '+387 66 444 555' },
            consents: { dataProcessing: true }
        },
        tests: expectError(400, 'BAD_REQUEST')
    },
    {
        n: 8, method: 'GET', name: 'the patient created in case 1 -> 200 Ana Kovač',
        path: '{{case1PatientId}}',
        tests: [
            "pm.test('200 OK', () => pm.response.to.have.status(200));",
            "const p = pm.response.json();",
            "pm.test('same patient as case 1', () => pm.expect(p.patientId).to.eql(pm.collectionVariables.get('case1PatientId')));",
            "pm.test('fullName', () => pm.expect(p.fullName).to.eql('Ana Kovač'));",
            "pm.test('category ADULT', () => pm.expect(p.category).to.eql('ADULT'));",
            "pm.test('phone', () => pm.expect(p.phone).to.eql('+38761111222'));",
            "pm.test('age', () => pm.expect(p.age).to.eql(ageOn('1985-04-12')));"
        ]
    },
    {
        n: 9, method: 'GET', name: 'PAT-999999 -> 404 PATIENT_NOT_FOUND',
        path: 'PAT-999999',
        tests: expectError(404, 'PATIENT_NOT_FOUND')
    },
    // Bonus: search by last name, through all three layers.
    {
        n: 10, method: 'GET', name: 'search lastName=KOVAČ -> 200, only Ana Kovač (case 4 was rejected)',
        query: { lastName: 'KOVAČ' },
        tests: [
            "pm.test('200 OK', () => pm.response.to.have.status(200));",
            "const list = pm.response.json();",
            "pm.test('exactly one match', () => pm.expect(list).to.have.lengthOf(1));",
            "pm.test('the patient of case 1', () => pm.expect(list[0].patientId).to.eql(pm.collectionVariables.get('case1PatientId')));",
            "pm.test('portal view', () => pm.expect(list[0].fullName).to.eql('Ana Kovač'));",
            "pm.test('age', () => pm.expect(list[0].age).to.eql(ageOn('1985-04-12')));"
        ]
    },
    {
        n: 11, method: 'GET', name: 'search lastName=Nepoznat -> 200, empty array',
        query: { lastName: 'Nepoznat' },
        tests: [
            "pm.test('200 OK', () => pm.response.to.have.status(200));",
            "pm.test('empty array', () => pm.expect(pm.response.json()).to.eql([]));"
        ]
    }
];

// Age in completed years on the current date (portal age rule), inlined where needed.
const AGE_ON = [
    'function ageOn(isoBirthDate) {',
    "    const [y, m, d] = isoBirthDate.split('-').map(Number);",
    '    const t = new Date();',
    '    const reached = (t.getMonth() + 1 > m) || (t.getMonth() + 1 === m && t.getDate() >= d);',
    '    return t.getFullYear() - y - (reached ? 0 : 1);',
    '}'
];

function expectError(status, code) {
    return [
        `pm.test('${status} ${code}', () => pm.response.to.have.status(${status}));`,
        "const e = pm.response.json().error;",
        `pm.test('error code ${code}', () => pm.expect(e.code).to.eql('${code}'));`,
        "pm.test('standard error body', () => pm.expect(Object.keys(e).sort()).to.eql(['code','correlationId','message','timestamp']));",
        "pm.test('error body carries the correlation ID', () => pm.expect(e.correlationId).to.eql(pm.variables.get('correlationId')));",
        "pm.test('timestamp is UTC', () => pm.expect(e.timestamp).to.match(/^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$/));"
    ];
}

const item = cases.map((c) => {
    const request = {
        method: c.method,
        header: [
            { key: 'X-Correlation-ID', value: '{{correlationId}}', type: 'text' },
            ...(c.body ? [{ key: 'Content-Type', value: 'application/json', type: 'text' }] : [])
        ],
        url: {
            raw: `{{baseUrl}}/api/patients${c.path ? '/' + c.path : ''}` +
                (c.query ? '?' + Object.entries(c.query).map(([k, v]) => `${k}=${v}`).join('&') : ''),
            host: ['{{baseUrl}}'],
            path: ['api', 'patients', ...(c.path ? [c.path] : [])],
            ...(c.query ? { query: Object.entries(c.query).map(([key, value]) => ({ key, value })) } : {})
        }
    };
    if (c.body) {
        request.body = { mode: 'raw', raw: JSON.stringify(c.body, null, 2), options: { raw: { language: 'json' } } };
    }
    return {
        name: `${c.n}. ${c.method} ${c.name}`,
        event: [{ listen: 'test', script: { type: 'text/javascript', exec: c.tests.some((l) => l.includes('ageOn(')) ? [...AGE_ON, ...c.tests] : c.tests } }],
        request
    };
});

const collection = {
    info: {
        name: 'Patient Registration APIs: sample cases',
        description: [
            'The nine sample cases of the assignment, against the Experience API, followed by two',
            'searches by last name (bonus endpoint). Run in order (case 4 is a duplicate of case 1;',
            'cases 8 and 10 read the patient created by case 1) against an empty patient table.',
            'Select the "local" or "cloudhub" environment for {{baseUrl}}.'
        ].join('\n'),
        schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json'
    },
    event: [
        {
            listen: 'prerequest',
            script: {
                type: 'text/javascript',
                exec: [
                    '// A fresh correlation ID per request; the tests check it comes back.',
                    "pm.variables.set('correlationId', pm.variables.replaceIn('{{$guid}}'));"
                ]
            }
        },
        {
            listen: 'test',
            script: {
                type: 'text/javascript',
                exec: [
                    "pm.test('X-Correlation-ID echoed', () => pm.expect(pm.response.headers.get('X-Correlation-ID')).to.eql(pm.variables.get('correlationId')));",
                    "pm.test('JSON response', () => pm.expect(pm.response.headers.get('Content-Type')).to.include('application/json'));"
                ]
            }
        }
    ],
    variable: [{ key: 'case1PatientId', value: '' }],
    item
};

const out = path.join(__dirname, '..', 'postman', 'patient-registration.postman_collection.json');
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify(collection, null, 2) + '\n', 'utf8');
console.log(`wrote ${path.relative(process.cwd(), out)} (${item.length} requests)`);
