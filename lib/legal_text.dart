part of 'legal.dart';

// The legal documents of Resqponder, the response teams' app (items 64–65).
// The website shows the same text (App\Support\Legal on the server);
// ResQPulse has its own documents in its own legal_text.dart.
// When the text changes, change it here and on the server, and change
// kLegalVersion.

/// Version of the documents below.
const String kLegalVersion = '2026-11-06';

/// Shown at the top of each document.
const String kLegalUpdated = 'November 6, 2026';

/// This app's color for the documents' links and buttons.
const Color _legalAccent = Color(0xFF0D1B4C);

/// A navy app bar like the rest of the app (true), or a white one.
const bool _legalFilledAppBar = true;

const List<_LegalDocument> _documents = [
  _LegalDocument(
    doc: LegalDoc.privacy,
    title: 'Privacy Policy',
    path: 'resqponder/privacy-policy',
    summary: 'Your team\'s information, and the information you handle',
    intro: [
      'This Privacy Policy explains how Resqponder, the ResQPulse app '
          'for MDRRMO Rosales response teams, handles personal information: '
          'your team\'s, and that of the residents, casualties and evacuees '
          'you work with. It follows the Data Privacy Act of 2012 (Republic '
          'Act No. 10173).',
      'Residents have their own Privacy Policy in the ResQPulse app and '
          'at resqpulse.com/privacy-policy.',
    ],
    sections: [
      _LegalSection('Who we are', [
        'Resqponder is run by the Municipal Disaster Risk Reduction and '
            'Management Office (MDRRMO) of the Municipality of Rosales, '
            'Pangasinan, which decides how the information is used (the '
            '"personal information controller"). Agency teams use '
            'Resqponder for MDRRMO, so they must follow its rules when they '
            'handle residents\' information.',
        '**Questions or requests:** Call MDRRMO Rosales at #2441, or '
            'visit the MDRRMO office, and ask for the Data Protection '
            'Officer of the Municipality of Rosales.',
      ]),
      _LegalSection('Your team\'s information', [
        '• **The agency account:** the account name, agency, station or '
            'unit, badge number, email and mobile number. MDRRMO sets it '
            'up; there is one account per agency, shared by its team, and '
            'its password is stored hashed.',
        '• **What the team does:** incidents it accepts, joins as '
            'backup or declines, backup requests, incident reports, and '
            'evacuation centers and evacuees it adds, each with the time.',
        '• **Logins:** when the account logs in and out, with the '
            'internet (IP) address, in MDRRMO\'s Audit Log.',
        '• **The phone:** a notification token, so incidents can ring '
            'the phone.',
      ]),
      _LegalSection('Information you see and record about others', [
        '• **SOS alerts and reports:** the name and mobile number of '
            'the person who reported, where they are (address, landmark and '
            'GPS pin), what they wrote, their photos, and MDRRMO\'s '
            'instructions.',
        '• **Incident reports:** what the team found, effects, actions '
            'taken, a photo, and for each person dead, injured or missing: '
            'name, age, sex, address, cause and remarks. The law treats age '
            'and health information as sensitive personal information.',
        '• **Evacuees (MSWD):** the name, age, sex, barangay and '
            'contact number of people at evacuation centers.',
      ]),
      _LegalSection('How location is used', [
        '• Your phone\'s location is used on the phone, to show where '
            'you are on the maps and to draw routes. It isn\'t sent to '
            'MDRRMO, and your team isn\'t tracked.',
        '• To draw a route, the phone sends the start and end points to '
            'the OSRM route service.',
        '• Searching for a place when adding an evacuation center uses '
            'OpenStreetMap\'s search service (Nominatim). The center\'s '
            'location is saved, and MDRRMO and residents see it.',
      ]),
      _LegalSection('Why it is used', [
        '• To send incidents to the right teams, and to coordinate the '
            'response and backup.',
        '• To keep the MDRRMC incident reports, and evacuation and '
            'relief records.',
        '• To keep the accounts secure, and to know which team did what.',
        '• For disaster planning and statistics, using totals that '
            'don\'t identify anyone.',
      ]),
      _LegalSection('Our legal basis', [
        'Under Sections 12 and 13 of the Data Privacy Act, the '
            'information is used because:',
        '• it is needed to respond to emergencies, keep public order '
            'and safety, and carry out MDRRMO\'s duties under the Philippine '
            'Disaster Risk Reduction and Management Act of 2010 (Republic '
            'Act No. 10121) (Sections 12(e) and 13(b));',
        '• it is needed to protect people\'s life and health (Sections '
            '12(d) and 13(c));',
        '• the law requires records to be kept (Section 12(c)).',
      ]),
      _LegalSection('The AI photo check', [
        'Photos residents send may be checked by Google\'s Gemini AI '
            'service, which suggests what kind of emergency they show. '
            'Resqponder shows it as the "AI guess" and the "AI photo '
            'check". It is only a hint and can be wrong: check the photo '
            'and the place yourself.',
      ]),
      _LegalSection('Who sees it', [
        '• **MDRRMO Rosales staff** see everything, in the web panel.',
        '• **Other teams on the same incident** see your account\'s '
            'name, agency, badge number, station and mobile number, and the '
            'team\'s report.',
        '• **MSWD teams** see the list of evacuees.',
        '• **Service providers**, only to run Resqponder: Hostinger '
            '(our server and database); Google (Firebase Cloud Messaging '
            'for the ring, and Gemini for the AI photo check); '
            'OpenStreetMap (maps and place search); and the OSRM route '
            'service.',
        '• **Government authorities**, when the law requires it.',
        'Some of these providers keep information outside the '
            'Philippines. MDRRMO remains responsible for it under Section '
            '21 of the Data Privacy Act. Nothing is sold or used for '
            'advertising.',
      ]),
      _LegalSection('How long it is kept', [
        '• **The agency account** is kept while the agency works with '
            'MDRRMO. MDRRMO can deactivate it.',
        '• **Incident reports, evacuation records and the Audit Log** '
            'are government records, kept as long as they are needed and as '
            'records rules require (Republic Act No. 9470, the National '
            'Archives of the Philippines Act of 2007). Then they are '
            'deleted, or what identifies people is removed.',
        '• **The notification token** is removed when you log out, and '
            'when MDRRMO resets the password or deactivates the account.',
      ]),
      _LegalSection('How it is protected', [
        'MDRRMO\'s part:',
        '• Information travels over encrypted connections (HTTPS), and '
            'passwords are stored hashed.',
        '• Each team only gets the incidents MDRRMO sends it, and only '
            'MSWD sees evacuees.',
        '• A link to a report\'s PDF stops working after 30 minutes.',
        '• What is done in the system is recorded.',
        'Your part:',
        '• Lock the phone with a PIN, and don\'t leave it unattended '
            'while logged in.',
        '• If a phone is lost, or someone leaves the team, ask MDRRMO '
            'to reset the password: that signs out every phone.',
        '• Don\'t screenshot, forward or post residents\' information. '
            '"Copy for a message" leaves out the reporter\'s name and '
            'number; share it only with people working on the response.',
      ]),
      _LegalSection('Rights', [
        '• Team members can ask MDRRMO to see or correct the agency '
            'account\'s details.',
        '• Residents, casualties\' families and evacuees have rights '
            'under the Data Privacy Act, including to be told how their '
            'information is used, to get a copy, and to have it corrected. '
            'If someone asks you, refer them to MDRRMO Rosales.',
        '• Anyone can complain to the National Privacy Commission '
            '(privacy.gov.ph).',
        'Requests: Call MDRRMO Rosales at #2441, or visit the MDRRMO '
            'office, and ask for the Data Protection Officer of the '
            'Municipality of Rosales.',
      ]),
      _LegalSection('Changes to this policy', [
        'Changes will be posted in the app and at '
            'resqpulse.com/resqponder/privacy-policy, with the date at the '
            'top.',
      ]),
    ],
  ),
  _LegalDocument(
    doc: LegalDoc.terms,
    title: 'Terms and Conditions',
    path: 'resqponder/terms',
    summary: 'The rules for using Resqponder',
    intro: [
      'These Terms and Conditions are the rules for using Resqponder, '
          'the ResQPulse app for response teams, which is run by MDRRMO '
          'Rosales. By logging in, you agree to them and to Resqponder\'s '
          'Privacy Policy.',
    ],
    sections: [
      _LegalSection('Who may use Resqponder', [
        'Only authorized personnel of MDRRMO Rosales and its partner '
            'agencies, using the agency account MDRRMO set up for them.',
      ]),
      _LegalSection('The agency account', [
        '• It is shared by your agency\'s team. Keep the password within '
            'the agency and never share it outside.',
        '• Ask MDRRMO to reset the password when someone leaves the '
            'team or a phone is lost. A reset signs out every phone.',
        '• Log out of a phone the team doesn\'t control.',
        '• What is done with the account is recorded, with the time.',
      ]),
      _LegalSection('Residents\' information is confidential', [
        '• Use names, numbers, locations, photos and reports only for '
            'the response.',
        '• Don\'t screenshot, copy, forward or post them, including in '
            'group chats outside the response. Never post them online.',
        '• Don\'t contact residents for anything unrelated to the '
            'response.',
        'Misusing personal information can be a crime under the Data '
            'Privacy Act, and can also have consequences under your '
            'agency\'s rules.',
      ]),
      _LegalSection('Responding to incidents', [
        '• Accept an incident only if your team can respond. If it '
            'can\'t, decline it quickly, so MDRRMO can send another team.',
        '• Request backup when you need it. MDRRMO decides which teams '
            'to send.',
        '• Follow your agency\'s protocols and MDRRMO\'s instructions.',
      ]),
      _LegalSection('Incident reports', [
        '• Reports must be true and complete. They are official MDRRMC '
            'records.',
        '• Record casualties\' details only as needed for the report.',
        '• MDRRMO may correct a report before approving it, and says '
            'what it changed.',
      ]),
      _LegalSection('Evacuees (MSWD)', [
        '• Tell each person what is recorded and why before saving; the '
            'Log Evacuee screen says what to tell them.',
        '• Record only what the form asks. For a child, record the '
            'details with a parent or guardian present.',
      ]),
      _LegalSection('Resqponder is a tool, not the only channel', [
        '• It depends on the phone, the internet connection, GPS and '
            'the server. Incidents can ring late, or not at all, when the '
            'phone is offline.',
        '• The ring plays on the phone\'s alarm volume. Keep it up, and '
            'keep your radio on too.',
        '• Maps, routes, distances and times are estimates. Roads can '
            'be closed or flooded; trust what you see.',
        '• The AI guess can be wrong. Safety tips are general guidance; '
            'follow your training.',
      ]),
      _LegalSection('Changes and access', [
        'MDRRMO may change, pause or stop Resqponder, and may '
            'deactivate an account; that signs out its phones. These terms '
            'may be updated, with the date at the top.',
      ]),
      _LegalSection('Responsibility', [
        'MDRRMO works to keep Resqponder accurate and running, but '
            'provides it as it is. As far as Philippine law allows, MDRRMO '
            'Rosales is not responsible for losses caused by delays, '
            'outages, or problems with the phone or the internet connection.',
      ]),
      _LegalSection('Law that applies', [
        'These terms are governed by the laws of the Philippines.',
      ]),
      _LegalSection('Contact', [
        'Questions: call MDRRMO Rosales at #2441, or visit the MDRRMO '
            'office.',
      ]),
    ],
  ),
  _LegalDocument(
    doc: LegalDoc.cookies,
    title: 'Cookie Policy',
    path: 'resqponder/cookie-policy',
    summary: 'What Resqponder keeps on the phone',
    intro: [
      'Resqponder doesn\'t use browser cookies, and nothing in it is '
          'used for advertising or to follow you. This explains what it '
          'keeps on the phone.',
    ],
    sections: [
      _LegalSection('What Resqponder keeps on the phone', [
        '• **The login:** the agency account\'s login and its details '
            '(name, agency, station, badge number, email and mobile '
            'number), so the team stays logged in.',
        '• **A notification token** from Firebase Cloud Messaging, so '
            'incidents can ring the phone.',
        '• **Cleared alerts:** which disaster alerts you cleared.',
        '• **Photos for a report:** the photo you take or choose stays '
            'in the app\'s temporary storage until the phone clears it.',
        'Map pictures from OpenStreetMap are only kept while the app is '
            'open.',
      ]),
      _LegalSection('Outside the app', [
        '• A report\'s PDF opens in the phone\'s browser or PDF viewer, '
            'through a link that works for 30 minutes. The browser may keep '
            'the file in its downloads or history.',
        '• "Copy for a message" puts the incident\'s details on the '
            'phone\'s clipboard, without the reporter\'s name and number.',
      ]),
      _LegalSection('Your choices', [
        '• Logging out removes the login from the phone, and the '
            'notification token from MDRRMO\'s list.',
        '• You can clear the app\'s storage in the phone\'s settings. '
            'Uninstalling the app removes everything it saved.',
      ]),
      _LegalSection('Contact', [
        'Questions: call MDRRMO Rosales at #2441, or visit the MDRRMO '
            'office.',
      ]),
    ],
  ),
  _LegalDocument(
    doc: LegalDoc.accessibility,
    title: 'Accessibility',
    path: 'resqponder/accessibility',
    summary: 'How we make Resqponder usable for every responder',
    intro: [
      'MDRRMO Rosales wants every responder to be able to use '
          'Resqponder, including people with low vision or hearing loss.',
    ],
    sections: [
      _LegalSection('What we do', [
        '• A new incident rings like a call: an alarm on the phone\'s '
            'alarm volume and a full-screen alert. If the sound can\'t play, '
            'the phone vibrates instead.',
        '• Text follows the phone\'s font size setting.',
        '• We check new and updated screens for buttons that are large '
            'enough to tap, strong color contrast, and labels that screen '
            'readers such as TalkBack can read.',
        '• An incident\'s status and priority are written out, not shown '
            'by color alone.',
        '• Documents like this one use headings that screen readers can '
            'jump between.',
      ]),
      _LegalSection('What may still be hard to use', [
        '• If the alarm volume is down, the ring is silent. If you '
            'can\'t hear it, keep the phone where you can see the '
            'full-screen alert.',
        '• Maps and routes are hard to use with a screen reader. The '
            'address, landmark and Call buttons work without the map.',
        '• Some older screens haven\'t been fully checked yet. We are '
            'working through them.',
      ]),
      _LegalSection('Tell us about a problem', [
        'If something is hard to use, call MDRRMO Rosales at #2441. '
            'Tell us which screen it was and what happened.',
        'We are guided by the Magna Carta for Persons with Disability '
            '(Republic Act No. 7277, as amended).',
      ]),
    ],
  ),
];
