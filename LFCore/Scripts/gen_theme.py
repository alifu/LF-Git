#!/usr/bin/env python3
"""Generate LF-Git theme assets from Design/theme.json.

Outputs (committed to the repo):
  LF-Git/Assets.xcassets/Theme/lf<Token>.colorset   one per token, light + dark
  LF-Git/Assets.xcassets/AccentColor.colorset       mirrors the `accent` token
  LF-Git/Assets.xcassets/Theme/lf<Token><Choice>.colorset   the accent tokens again for every accent choice
  LF-Git/Theme/LFThemeToken.generated.swift         typed token enum and the accent choices

Usage:
  gen_theme.py           regenerate files and verify contrast
  gen_theme.py --check   fail if contrast is too low or generated files are stale (CI)
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
THEME_JSON = REPO_ROOT / "Design" / "theme.json"
ASSETS_DIR = REPO_ROOT / "LF-Git" / "Assets.xcassets"
THEME_ASSETS_DIR = ASSETS_DIR / "Theme"
SWIFT_OUT = REPO_ROOT / "LF-Git" / "Theme" / "LFThemeToken.generated.swift"
HEX_PATTERN = re.compile(r"^#[0-9A-Fa-f]{6}$")
TOKEN_PATTERN = re.compile(r"^[a-z][A-Za-z0-9]*$")
APPEARANCES = ("light", "dark")


class ThemeError(Exception):
    pass


def load_theme(path: Path) -> dict:
    try:
        theme = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ThemeError(f"cannot read {path}: {error}") from error
    validate_theme(theme)
    return theme


def validate_theme(theme: dict) -> None:
    palette = theme.get("palette", {})
    tokens = theme.get("tokens", {})
    if not palette or not tokens:
        raise ThemeError("theme.json needs non-empty 'palette' and 'tokens'")
    for name, value in palette.items():
        if not HEX_PATTERN.match(value):
            raise ThemeError(f"palette {name}: '{value}' is not #RRGGBB")
    for token, spec in tokens.items():
        if not TOKEN_PATTERN.match(token):
            raise ThemeError(f"token '{token}' must be lowerCamelCase")
        for appearance in APPEARANCES:
            ref = spec.get(appearance)
            if ref not in palette:
                raise ThemeError(f"token {token}.{appearance}: unknown palette color '{ref}'")
    for choice, overrides in theme.get("accentChoices", {}).items():
        if not TOKEN_PATTERN.match(choice):
            raise ThemeError(f"accent choice '{choice}' must be lowerCamelCase")
        for token, pair in overrides.items():
            if token not in tokens:
                raise ThemeError(f"accent choice {choice}: unknown token '{token}'")
            if len(pair) != 2 or any(ref not in palette for ref in pair):
                raise ThemeError(f"accent choice {choice}.{token}: needs [light, dark] palette colors")


def asset_name(token: str) -> str:
    return "lf" + token[0].upper() + token[1:]


def choice_asset_name(token: str, choice: str) -> str:
    return asset_name(token) + choice[0].upper() + choice[1:]


def accent_overrides(theme: dict) -> list[str]:
    """Tokens that change with the accent choice, in the order the choices list them."""
    names: list[str] = []
    for overrides in theme.get("accentChoices", {}).values():
        names += [token for token in overrides if token not in names]
    return names


def themed_for_choice(theme: dict, choice: str) -> dict:
    """The theme as it looks with `choice` selected: the choice's colors replace the base accent tokens."""
    tokens = dict(theme["tokens"])
    for token, (light, dark) in theme["accentChoices"][choice].items():
        tokens[token] = {**tokens[token], "light": light, "dark": dark}
    return {**theme, "tokens": tokens}


def hex_of(theme: dict, token: str, appearance: str) -> str:
    return theme["palette"][theme["tokens"][token][appearance]]


def relative_luminance(hex_color: str) -> float:
    channels = [int(hex_color[i : i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast_ratio(first: str, second: str) -> float:
    lighter, darker = sorted((relative_luminance(first), relative_luminance(second)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


def contrast_failures(theme: dict) -> list[str]:
    failures = base_contrast_failures(theme)
    for choice in theme.get("accentChoices", {}):
        failures += [f"[accent {choice}] {line}" for line in base_contrast_failures(themed_for_choice(theme, choice))]
    return failures


def base_contrast_failures(theme: dict) -> list[str]:
    minimum = theme["contrast"]["minimum"]
    failures = []
    for foreground, background in theme["contrast"]["pairs"]:
        for appearance in APPEARANCES:
            ratio = contrast_ratio(hex_of(theme, foreground, appearance), hex_of(theme, background, appearance))
            if ratio < minimum:
                failures.append(f"{appearance}: {foreground} on {background} = {ratio:.2f} (< {minimum})")
    return failures


def color_component(hex_color: str) -> dict:
    return {
        "color-space": "srgb",
        "components": {
            "alpha": "1.000",
            "red": f"0x{hex_color[1:3].upper()}",
            "green": f"0x{hex_color[3:5].upper()}",
            "blue": f"0x{hex_color[5:7].upper()}",
        },
    }


def colorset_contents(light_hex: str, dark_hex: str) -> str:
    contents = {
        "colors": [
            {"color": color_component(light_hex), "idiom": "universal"},
            {
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "color": color_component(dark_hex),
                "idiom": "universal",
            },
        ],
        "info": {"author": "gen_theme.py", "version": 1},
    }
    return json.dumps(contents, indent=2) + "\n"


def folder_contents() -> str:
    return json.dumps({"info": {"author": "gen_theme.py", "version": 1}}, indent=2) + "\n"


def swift_source(theme: dict) -> str:
    lines = [
        "// Generated by LFCore/Scripts/gen_theme.py from Design/theme.json — do not edit.",
        "",
        "/// Semantic color tokens. Each case names a light/dark color set in Assets.xcassets/Theme.",
        "enum LFThemeToken: String, CaseIterable, Sendable {",
    ]
    for token, spec in theme["tokens"].items():
        lines.append(f"    /// {spec.get('use', '')}")
        lines.append(f'    case {token} = "{asset_name(token)}"')
    lines.append("}")
    lines += swift_accent_choices(theme)
    return "\n".join(lines) + "\n"


def swift_accent_choices(theme: dict) -> list[str]:
    choices = list(theme.get("accentChoices", {}))
    overridden = ", ".join(f".{token}" for token in accent_overrides(theme))
    lines = [
        "",
        "/// The accent colors the user can pick in Settings. The first is the default; its colors are the base tokens.",
        "enum LFAccentChoice: String, CaseIterable, Sendable {",
    ]
    lines += [f"    case {choice}" for choice in choices]
    lines += [
        "",
        f"    /// The tokens a choice replaces; every other token is the same whatever the choice.",
        f"    static let overriddenTokens: Set<LFThemeToken> = [{overridden}]",
        "",
        "    /// Added to the base color set's name to get this choice's color set (empty for the default).",
        "    var assetSuffix: String {",
        "        switch self {",
    ]
    for index, choice in enumerate(choices):
        suffix = "" if index == 0 else choice[0].upper() + choice[1:]
        lines.append(f'        case .{choice}: "{suffix}"')
    lines += ["        }", "    }", "}"]
    return lines


def expected_files(theme: dict) -> dict[Path, str]:
    files: dict[Path, str] = {THEME_ASSETS_DIR / "Contents.json": folder_contents()}
    for token in theme["tokens"]:
        light, dark = hex_of(theme, token, "light"), hex_of(theme, token, "dark")
        files[THEME_ASSETS_DIR / f"{asset_name(token)}.colorset" / "Contents.json"] = colorset_contents(light, dark)
    for index, (choice, overrides) in enumerate(theme.get("accentChoices", {}).items()):
        if index == 0:
            continue  # the default choice is the base color sets
        for token, (light_ref, dark_ref) in overrides.items():
            path = THEME_ASSETS_DIR / f"{choice_asset_name(token, choice)}.colorset" / "Contents.json"
            files[path] = colorset_contents(theme["palette"][light_ref], theme["palette"][dark_ref])
    accent_light, accent_dark = hex_of(theme, "accent", "light"), hex_of(theme, "accent", "dark")
    files[ASSETS_DIR / "AccentColor.colorset" / "Contents.json"] = colorset_contents(accent_light, accent_dark)
    files[SWIFT_OUT] = swift_source(theme)
    return files


def stale_colorsets(theme: dict) -> list[Path]:
    if not THEME_ASSETS_DIR.exists():
        return []
    wanted = {f"{asset_name(token)}.colorset" for token in theme["tokens"]}
    for index, (choice, overrides) in enumerate(theme.get("accentChoices", {}).items()):
        if index > 0:
            wanted |= {f"{choice_asset_name(token, choice)}.colorset" for token in overrides}
    return [path for path in THEME_ASSETS_DIR.glob("*.colorset") if path.name not in wanted]


def write_files(files: dict[Path, str], stale: list[Path]) -> None:
    for path in stale:
        for child in path.iterdir():
            child.unlink()
        path.rmdir()
    for path, content in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def drifted_files(files: dict[Path, str], stale: list[Path]) -> list[Path]:
    drifted = [path for path, content in files.items() if not path.exists() or path.read_text(encoding="utf-8") != content]
    return drifted + stale


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="verify only; do not write files")
    args = parser.parse_args()

    try:
        theme = load_theme(THEME_JSON)
    except ThemeError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    failures = contrast_failures(theme)
    if failures:
        print("error: contrast below WCAG AA:\n  " + "\n  ".join(failures), file=sys.stderr)
        return 1

    files = expected_files(theme)
    stale = stale_colorsets(theme)
    if args.check:
        drifted = drifted_files(files, stale)
        if drifted:
            listed = "\n  ".join(str(path.relative_to(REPO_ROOT)) for path in drifted)
            print(f"error: generated theme files are stale; run gen_theme.py:\n  {listed}", file=sys.stderr)
            return 1
        print(f"theme OK: {len(theme['tokens'])} tokens, {len(theme['contrast']['pairs']) * 2} contrast checks passed")
        return 0

    write_files(files, stale)
    print(f"generated {len(theme['tokens'])} color sets + AccentColor + {SWIFT_OUT.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
