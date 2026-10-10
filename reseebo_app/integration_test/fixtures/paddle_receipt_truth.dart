// Independently transcribed from the original public photographs on 2026-10-10.
// OCR output and parser output were not used to define these checks. Exact image
// hashes bind the transcription to the developer-only input, not bundled assets.
const paddleReceiptTruth = [
  (
    id: 'dali',
    source: 'https://note.com/oyako_tagaytay/n/n929317daedad',
    sha256: '3780251c52ef2ef361947ce623753f9deab4ca6d4934c5c65c97ea6ca2117ab2',
    supplier: 'DALI',
    date: '2026-07-15',
    totalCents: 60275,
    items: [
      (description: 'IceDream', quantity: 1, cents: 16975),
      (description: 'Happyflakes', quantity: 10, cents: 3750),
      (description: 'Fresh Egg', quantity: 1, cents: 10700),
    ],
    fields: <String, List<String>>{
      'supplier': ['DALI'],
      'transaction date': ['7/15/2026'],
      'total': ['602.75'],
      'IceDream item': ['IceDream', '169.75'],
      'Happyflakes quantity and line price': ['Happyflakes', '10', '37.50'],
      'egg item and price': ['Fresh Egg', '107.00'],
    },
  ),
  (
    id: 'savemore',
    source: 'https://note.com/norris_iloilo/n/n2f7474d537f5',
    sha256: '79aa855eec4091a1658689eb3324253e5846100e15f7bb8874a386b367591234',
    supplier: 'FESTIVE MARKET',
    date: '2026-04-17',
    totalCents: 19760,
    items: [
      (description: 'OISHIPATATA24G', quantity: 2, cents: 1590),
      (description: 'TangOrangeMango19g', quantity: 3, cents: 6300),
      (description: 'BEARBRAND200ml', quantity: 1, cents: 2950),
    ],
    fields: <String, List<String>>{
      'supplier': ['FESTIVE MARKET'],
      'transaction date': ['04/17/2026'],
      'total': ['197.60'],
      'Oishi quantity and line price': ['2', 'OISHIPATATA24G', '15.90'],
      'Tang Orange Mango quantity and line price': [
        '3',
        'TangOrangeMango19g',
        '63.00',
      ],
      'Bear Brand item and price': ['BEARBRAND200ml', '29.50'],
    },
  ),
];
