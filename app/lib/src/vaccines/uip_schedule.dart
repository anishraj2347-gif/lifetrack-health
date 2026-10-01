/// India's Universal Immunisation Programme (UIP) — the government schedule
/// for children, as published by the Ministry of Health & Family Welfare.
/// Private paediatricians often add vaccines (the IAP schedule); the screen
/// says to follow the child's doctor where they differ. Review against the
/// current MoHFW schedule before any pilot.
class VaccineDose {
  const VaccineDose(this.code, this.name, this.dueAt, this.ageLabel, this.protects);

  /// Stable key, e.g. `penta-2`.
  final String code;
  final String name;

  /// Age at which it becomes due.
  final ({int days, int months, int years}) dueAt;
  final String ageLabel;
  final String protects;

  DateTime dueDate(DateTime birth) => DateTime(birth.year + dueAt.years, birth.month + dueAt.months, birth.day + dueAt.days);
}

const _birth = (days: 0, months: 0, years: 0);
const _w6 = (days: 42, months: 0, years: 0);
const _w10 = (days: 70, months: 0, years: 0);
const _w14 = (days: 98, months: 0, years: 0);
const _m9 = (days: 0, months: 9, years: 0);
const _m16 = (days: 0, months: 16, years: 0);
const _y5 = (days: 0, months: 0, years: 5);
const _y10 = (days: 0, months: 0, years: 10);
const _y16 = (days: 0, months: 0, years: 16);

const uipSchedule = <VaccineDose>[
  VaccineDose('bcg', 'BCG', _birth, 'At birth', 'Tuberculosis'),
  VaccineDose('opv-0', 'OPV 0 (polio drops)', _birth, 'At birth', 'Polio'),
  VaccineDose('hepb-0', 'Hepatitis B birth dose', _birth, 'At birth', 'Hepatitis B · give within 24 hours'),
  VaccineDose('opv-1', 'OPV 1', _w6, '6 weeks', 'Polio'),
  VaccineDose('penta-1', 'Pentavalent 1', _w6, '6 weeks', 'Diphtheria, pertussis, tetanus, hepatitis B, Hib'),
  VaccineDose('rota-1', 'Rotavirus 1', _w6, '6 weeks', 'Rotavirus diarrhoea'),
  VaccineDose('fipv-1', 'fIPV 1 (polio injection)', _w6, '6 weeks', 'Polio'),
  VaccineDose('pcv-1', 'PCV 1', _w6, '6 weeks', 'Pneumococcal pneumonia'),
  VaccineDose('opv-2', 'OPV 2', _w10, '10 weeks', 'Polio'),
  VaccineDose('penta-2', 'Pentavalent 2', _w10, '10 weeks', 'Diphtheria, pertussis, tetanus, hepatitis B, Hib'),
  VaccineDose('rota-2', 'Rotavirus 2', _w10, '10 weeks', 'Rotavirus diarrhoea'),
  VaccineDose('opv-3', 'OPV 3', _w14, '14 weeks', 'Polio'),
  VaccineDose('penta-3', 'Pentavalent 3', _w14, '14 weeks', 'Diphtheria, pertussis, tetanus, hepatitis B, Hib'),
  VaccineDose('rota-3', 'Rotavirus 3', _w14, '14 weeks', 'Rotavirus diarrhoea'),
  VaccineDose('fipv-2', 'fIPV 2', _w14, '14 weeks', 'Polio'),
  VaccineDose('pcv-2', 'PCV 2', _w14, '14 weeks', 'Pneumococcal pneumonia'),
  VaccineDose('mr-1', 'MR 1 (measles, rubella)', _m9, '9–12 months', 'Measles, rubella'),
  VaccineDose('je-1', 'JE 1', _m9, '9–12 months', 'Japanese encephalitis · only where JE is common'),
  VaccineDose('pcv-b', 'PCV booster', _m9, '9–12 months', 'Pneumococcal pneumonia'),
  VaccineDose('mr-2', 'MR 2', _m16, '16–24 months', 'Measles, rubella'),
  VaccineDose('je-2', 'JE 2', _m16, '16–24 months', 'Japanese encephalitis · only where JE is common'),
  VaccineDose('dpt-b1', 'DPT booster 1', _m16, '16–24 months', 'Diphtheria, pertussis, tetanus'),
  VaccineDose('opv-b', 'OPV booster', _m16, '16–24 months', 'Polio'),
  VaccineDose('dpt-b2', 'DPT booster 2', _y5, '5–6 years', 'Diphtheria, pertussis, tetanus'),
  VaccineDose('td-10', 'Td', _y10, '10 years', 'Tetanus, diphtheria'),
  VaccineDose('td-16', 'Td', _y16, '16 years', 'Tetanus, diphtheria'),
];

/// A dose was given: when, and optionally where.
class VaccineGiven {
  const VaccineGiven({required this.on, this.place});
  final DateTime on;
  final String? place;

  Map<String, Object?> toJson() => {'on': on.toIso8601String().substring(0, 10), 'place': place};
  static VaccineGiven fromJson(Map<String, Object?> j) => VaccineGiven(on: DateTime.parse(j['on']! as String), place: j['place'] as String?);
}

enum VaccineStatus { given, due, upcoming }

/// Where each dose stands for a child born on [birth], at [at]. "Due" means
/// its age has come and it is not marked given — not a judgement; the
/// child's doctor may have given it under another name or schedule.
List<(VaccineDose, VaccineStatus, VaccineGiven?)> vaccineStatus(DateTime birth, Map<String, VaccineGiven> given, DateTime at) => [
      for (final d in uipSchedule)
        (
          d,
          given[d.code] != null ? VaccineStatus.given : (d.dueDate(birth).isAfter(at) ? VaccineStatus.upcoming : VaccineStatus.due),
          given[d.code],
        ),
    ];
