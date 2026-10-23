# MedSafe

## Supabase backend

The app supports Supabase-backed accounts while retaining an offline Hive fallback when no Supabase configuration is supplied.

1. Create a Supabase project.
2. In the Supabase SQL editor, run [`supabase/schema.sql`](supabase/schema.sql).
3. Start the app with the project URL and publishable key:

```bash
flutter run \
	--dart-define=SUPABASE_URL=https://your-project.supabase.co \
	--dart-define=SUPABASE_PUBLISHABLE_KEY=your-publishable-key
```

When configured, the login screen uses email/password authentication. The schema includes profiles, patient/caregiver roles, groups, memberships, medications, and dose events with row-level security policies.

The Supabase service-role key must never be placed in the app or committed to the repository.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
