-- FABRICATED SAMPLE DATA. Invented for testing; not real immigration
-- requirements and not usable for any actual application.
INSERT INTO public.residency_requirement (country_id, document_name, description, mandatory) VALUES
-- Denmark (country.id = 1)
(1, 'Valid passport',            'Machine-readable passport valid at least 6 months beyond application date.', true),
(1, 'Residence permit history',  'Documentation of 8 years continuous lawful residence.',                      true),
(1, 'Danish language certificate','Proof of passing Proeve i Dansk 2 or higher.',                              true),
(1, 'Employment record',         'Full-time employment for at least 3 years 6 months of the last 4 years.',    true),
(1, 'Proof of self-support',     'Statement that no public assistance was received in the last 4 years.',      true),
(1, 'Active citizenship proof',  'Evidence of civic participation, e.g. association or volunteer work.',       false),
-- Finland (country.id = 3)
(3, 'Valid passport',            'Passport or other accepted travel document.',                                true),
(3, 'Residence permit history',  'Four years continuous residence on an A permit.',                            true),
(3, 'Proof of income',           'Payslips or tax records covering the qualifying period.',                    true),
(3, 'Criminal record extract',   'Extract issued within the last 3 months.',                                   true),
(3, 'Language certificate',      'YKI level 3 in Finnish or Swedish. Speeds up processing.',                   false),
-- Sweden (country.id = 5)
(5, 'Valid passport',            'Passport valid for the full permit period.',                                 true),
(5, 'Residence permit history',  'Four years of residence permits within the last seven years.',               true),
(5, 'Proof of employment',       'Employment contract or business accounts showing self-support.',             true),
(5, 'Housing contract',          'Rental or ownership documentation for suitable accommodation.',              true),
(5, 'Criminal record check',     'Extract from Polismyndigheten.',                                             false);
