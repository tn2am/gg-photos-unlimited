# Localization

GoToHP supports English and Japanese. The default follows the device's preferred language list; if none of the supported languages appears, English is used. Regional variants such as `ja-JP` and `en-GB` are supported.

In the embedded settings, choose **Appearance → Language** to select System default, Japanese or English. This preference belongs to the host app and does not change Google Photos or iOS language settings. The GoToHP screen updates immediately; reopen the profile menu to update its entry. System-owned controls and system errors follow iOS localization. Raw upstream/server diagnostic messages remain unchanged.

The catalogs in `Localization/en.json` and `Localization/ja.json` use English fallback text as keys. A generated header embeds them in the tweak and jailed dylib. Sideloadly and LiveContainer users do not need a separate resource bundle.

To change translations:

1. Edit the JSON catalogs, keeping the same keys and format arguments in every language.
2. Wrap new user-facing strings with `GSL(@"English fallback text")`.
3. Run `python3 scripts/localization.py` and commit the generated header with the catalogs.
4. Run `python3 scripts/localization.py --check`.

For an additional language, add its catalog, then add its code and display name to the language selector in `GSPanel.m`. Locale resolution automatically recognizes embedded catalogs.

CI validates key coverage, format arguments and generated output. A Foundation fixture checks locale selection and fallback, and a UIKit fixture renders both Japanese and English settings. Protocol keys, quality values, account identifiers and credentials are never translated.
