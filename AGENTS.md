# The Pickle agent instructions

## Working conventions

- Work sequentially. Ask before using parallel agents.
- Present material questions and suggestions before implementing a plan.
- Preserve unrelated staged and unstaged changes.
- Use Expo, React Native, and TypeScript in `react-native/`, with Supabase for
  the backend. Run npm workspace commands from the repository root.
- Follow `docs/product-concept.txt` for business rules and
  `docs/design-reference.md` for the visual direction.
- Keep services, models, state/hooks, and screens separate. Extract feature-specific
  UI into the feature's `components/` folder when a screen becomes too long.
- Reuse shared components for controls used across features.
- Centralize shared design tokens in `react-native/src/theme.ts` when needed;
  reuse and extend them to maintain a consistent design system.
- Reuse `getSupabaseClient()` from `react-native/src/lib/supabase.ts`. Put schema
  changes and access policies in Supabase migrations; keep secrets out of the app.
- Keep booking and payment statuses separate; scope manager access by location.
- Add comments or API documentation where they explain intent, contracts,
  invariants, security boundaries, lifecycle/concurrency behavior, or a
  non-obvious workaround. Avoid obvious or repeated explanations; document each
  contract at its owning boundary. Update or remove stale comments with the change.
- Prefer code that explains what, comments that explain why, and API documentation
  that explains the caller contract, including units, side effects, errors, and
  retry behavior when relevant.
- Inspect current code and contracts before changing behavior. Run checks
  appropriate to the change, including `npm run typecheck` for TypeScript changes,
  and distinguish static, local runtime, device, and hosted verification.
