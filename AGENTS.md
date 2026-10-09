# Reseebo agent instructions

## Working conventions

- Work sequentially. Ask before using parallel agents.
- Present material questions and suggestions before implementing a plan.
- Preserve unrelated staged and unstaged changes.
- Use Flutter with Dart, on-device SQLite, and bundled on-device OCR. The app
  must work fully offline from first launch. App path is TBD until scaffolded;
  run Flutter commands from the app root once it exists.
- Follow `SARI-SARI-RECEIPT-IDEA.md` and `1. Project_Scoping_Prompt.md` for
  business rules; use `1.1 Frontend_Prompt.md` for UI direction.
- Keep services, models, state, and screens separate. Extract feature-specific
  UI into the feature's `widgets/` folder when a screen becomes too long.
- Reuse shared components for controls used across features.
- Centralize shared design tokens in a shared Flutter theme when needed;
  reuse and extend them to maintain a consistent design system.
- Put schema changes in versioned local SQLite migrations. Validate purchases at
  the local service/database boundary and save each receipt and its lines atomically.
- Keep purchase history and original receipt images. Match the exact product
  brand, variant, and size; confirm unclear fields before calculating unit costs.
- Bundle required OCR models, fonts, and assets. Accounts, hosted backends,
  cloud backup, runtime downloads, and cloud AI calls are outside the current scope.
- Add comments or API documentation where they explain intent, contracts,
  invariants, security boundaries, lifecycle/concurrency behavior, or a
  non-obvious workaround. Avoid obvious or repeated explanations; document each
  contract at its owning boundary. Update or remove stale comments with the change.
- Prefer code that explains what, comments that explain why, and API documentation
  that explains the caller contract, including units, side effects, errors, and
  retry behavior when relevant.
- Inspect current code and contracts before changing behavior. Run checks
  appropriate to the change, including `flutter analyze` for Dart changes,
  and distinguish static checks, local storage checks, and real-device offline
  verification. Test first launch with internet disabled and persistence after restart.
