# assets/demo

`signup.json` is `examples/signup` in the single-file form
(`Project.toBundleJson`), bundled so the editor has a real project to open
where there is no filesystem to read one from — the web build, mainly.

It is generated, but committed: `flutter build web` needs it as an asset, so a
fresh clone should build without running a tool first. Regenerate it with:

```bash
dart run tool/make_signup_example.dart
```

which writes both `examples/signup/` and this file from one source.
